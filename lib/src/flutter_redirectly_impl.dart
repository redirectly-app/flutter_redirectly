import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:app_links/app_links.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:rxdart/rxdart.dart';

import '../flutter_redirectly.dart';
import 'services/device_service.dart';
import 'version.dart';

/// Implementation of Flutter Redirectly plugin
///
/// This class provides functionality similar to Firebase Dynamic Links
/// but uses your own Redirectly backend. No native code required!
final class FlutterRedirectlyImpl implements FlutterRedirectly {
  static final FlutterRedirectlyImpl _instance =
      FlutterRedirectlyImpl._internal();

  /// Singleton instance
  static FlutterRedirectlyImpl get instance => _instance;

  /// Private constructor
  FlutterRedirectlyImpl._internal();

  /// App links instance for handling deep links
  final _appLinks = AppLinks();

  /// Configuration
  RedirectlyConfig? _config;

  /// Stream controller for link clicks
  final _linkClickController =
      StreamController<RedirectlyLinkClick>.broadcast();

  /// BehaviorSubject for app install events - automatically handles late subscribers
  final _appInstallSubject = BehaviorSubject<RedirectlyAppInstallResponse>();

  /// HTTP client
  final _httpClient = http.Client();

  /// Device service for collecting device information
  final _deviceService = DeviceService();

  bool _initialized = false;
  StreamSubscription<Uri>? _linkSubscription;

  /// In-flight or completed initialize() call. Assigned before the first
  /// await so concurrent initialize() calls share one initialization.
  Future<void>? _initFuture;

  /// In-flight or completed install tracking. Assigned before the first
  /// await so the install POST cannot be issued twice in one process.
  Future<void>? _installTrackingFuture;

  /// File name for tracking app install
  static const String _trackingFileName = '.redirectly_install_tracked';

  /// Sentinel states: 'pending' claims the install before the POST,
  /// 'tracked' means the POST succeeded, 'failed' means retry next launch.
  static const String _statusPending = 'pending';
  static const String _statusTracked = 'tracked';
  static const String _statusFailed = 'failed';

  /// How long a 'pending' claim suppresses a re-POST before it is assumed
  /// to belong to a launch that died mid-flight and is retried.
  static const Duration _pendingClaimTtl = Duration(minutes: 5);

  @override

  /// Initialize the plugin with configuration
  Future<void> initialize(RedirectlyConfig config) async {
    if (_initialized) {
      throw RedirectlyError.configError(
          'FlutterRedirectly is already initialized');
    }

    return _initFuture ??= _doInitialize(config);
  }

  Future<void> _doInitialize(RedirectlyConfig config) async {
    _config = config;

    try {
      // Set up app links listening
      await _setupAppLinks();

      _initialized = true;

      if (config.enableDebugLogging) {
        print(
            'FlutterRedirectly v$packageVersion initialized successfully (Pure Dart - no native code!)');
      }

      // Automatically track app install (one-time only)
      await _trackAppInstallIfNeeded();
    } catch (e) {
      // Allow the caller to retry a failed initialize()
      _initFuture = null;
      throw RedirectlyError.configError('Failed to initialize: $e');
    }
  }

  /// Set up app links for handling deep links
  Future<void> _setupAppLinks() async {
    // Listen to incoming links when app is already running
    _linkSubscription = _appLinks.uriLinkStream.listen(
      _handleIncomingLink,
      onError: (error) {
        final linkClick = RedirectlyLinkClick(
          originalUrl: 'unknown',
          slug: 'unknown',
          username: 'unknown',
          error: RedirectlyError.linkError('Failed to process link: $error'),
          receivedAt: DateTime.now(),
        );
        _linkClickController.add(linkClick);
      },
    );

    // Handle initial link if app was opened via a link
    try {
      final initialUri = await _appLinks.getInitialLink();
      if (initialUri != null) {
        await _handleIncomingLink(initialUri);
      }
    } catch (e) {
      if (_config?.enableDebugLogging == true) {
        print('No initial link found: $e');
      }
    }
  }

  /// Handle incoming link
  Future<void> _handleIncomingLink(Uri uri) async {
    if (!_initialized || _config == null) {
      _linkClickController.add(
        RedirectlyLinkClick(
          originalUrl: uri.toString(),
          slug: 'unknown',
          username: 'unknown',
          error: RedirectlyError.configError('Plugin not initialized'),
          receivedAt: DateTime.now(),
        ),
      );
      return;
    }

    try {
      final linkClick = await _processRedirectlyLink(uri);
      _linkClickController.add(linkClick);
    } catch (e) {
      _linkClickController.add(
        RedirectlyLinkClick(
          originalUrl: uri.toString(),
          slug: 'unknown',
          username: 'unknown',
          error: RedirectlyError.linkError('Failed to process link: $e'),
          receivedAt: DateTime.now(),
        ),
      );
    }
  }

  /// Process a Redirectly link using pure Dart URL parsing
  Future<RedirectlyLinkClick> _processRedirectlyLink(Uri uri) async {
    final originalUrl = uri.toString();

    // Parse username and slug using pure Dart
    final parseResult = _parseRedirectlyUrl(uri);
    if (parseResult == null) {
      return RedirectlyLinkClick(
        originalUrl: originalUrl,
        slug: 'unknown',
        username: 'unknown',
        error: RedirectlyError.linkError('Invalid Redirectly URL format'),
        receivedAt: DateTime.now(),
      );
    }

    final username = parseResult['username']!;
    final slug = parseResult['slug']!;

    if (_config!.enableDebugLogging) {
      print('Processing Redirectly link: username=$username, slug=$slug');
    }

    // Try to resolve link details from backend
    RedirectlyLinkResolution? linkResolution;
    try {
      linkResolution = await resolveLink(username, slug);

      if (_config!.enableDebugLogging) {
        print(
            'Link resolved: ${linkResolution.type} link targeting ${linkResolution.target}');
      }

      // Log the click in background (fire-and-forget)
      _logMobileClick(username, slug, uri).catchError((error) {
        if (_config!.enableDebugLogging) {
          print('Failed to log mobile click: $error');
        }
      });
    } catch (e) {
      if (_config!.enableDebugLogging) {
        print('Failed to resolve link details: $e');
      }
      // Continue without link details - not a fatal error
    }

    return RedirectlyLinkClick(
      originalUrl: originalUrl,
      slug: slug,
      username: username,
      linkResolution: linkResolution,
      receivedAt: DateTime.now(),
    );
  }

  /// Parse Redirectly URL using pure Dart
  Map<String, String>? _parseRedirectlyUrl(Uri uri) {
    final host = uri.host;
    final pathSegments = uri.pathSegments;

    if (host.contains('redirectly.app')) {
      // Production URL: username.redirectly.app/slug
      final hostParts = host.split('.');
      if (hostParts.length < 3 || pathSegments.isEmpty) {
        return null;
      }
      return {
        'username': hostParts[0],
        'slug': pathSegments[0],
      };
    } else if (host.contains('localhost') &&
        uri.queryParameters.containsKey('user')) {
      // Development URL: localhost:3000?user=username/slug
      final userParam = uri.queryParameters['user']!;
      final parts = userParam.split('/');
      if (parts.length != 2) {
        return null;
      }
      return {
        'username': parts[0],
        'slug': parts[1],
      };
    }

    return null;
  }

  @override

  /// Create a permanent link
  Future<RedirectlyLink> createLink({
    required String slug,
    required String target,
    Map<String, dynamic>? metadata,
  }) async {
    _ensureInitialized();

    try {
      final response = await _httpClient.post(
        Uri.parse('${_config!.effectiveBaseUrl}/api/v1/links'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${_config!.apiKey}',
        },
        body: jsonEncode({
          'slug': slug,
          'target': target,
          if (metadata != null) 'metadata': metadata,
        }),
      );

      if (response.statusCode == 201) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        return RedirectlyLink.fromJson(json);
      } else {
        final error = jsonDecode(response.body) as Map<String, dynamic>;
        throw RedirectlyError.apiError(
          message: error['error'] as String? ?? 'Failed to create link',
          statusCode: response.statusCode,
          details: error,
        );
      }
    } catch (e) {
      if (e is RedirectlyError) rethrow;
      throw RedirectlyError.networkError('Network error: $e');
    }
  }

  @override

  /// Create a temporary link
  Future<RedirectlyTempLink> createTempLink({
    required String target,
    String? slug,
    int ttlSeconds = 900,
  }) async {
    _ensureInitialized();

    try {
      final response = await _httpClient.post(
        Uri.parse('${_config!.effectiveBaseUrl}/api/v1/temp-links'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${_config!.apiKey}',
        },
        body: jsonEncode({
          'target': target,
          if (slug != null) 'slug': slug,
          'ttlSeconds': ttlSeconds,
        }),
      );

      if (response.statusCode == 201) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        return RedirectlyTempLink.fromJson(json);
      } else {
        final error = jsonDecode(response.body) as Map<String, dynamic>;
        throw RedirectlyError.apiError(
          message:
              error['error'] as String? ?? 'Failed to create temporary link',
          statusCode: response.statusCode,
          details: error,
        );
      }
    } catch (e) {
      if (e is RedirectlyError) rethrow;
      throw RedirectlyError.networkError('Network error: $e');
    }
  }

  @override

  /// Get all permanent links
  Future<List<RedirectlyLink>> getLinks() async {
    _ensureInitialized();

    try {
      final response = await _httpClient.get(
        Uri.parse('${_config!.effectiveBaseUrl}/api/v1/links'),
        headers: {
          'Authorization': 'Bearer ${_config!.apiKey}',
        },
      );

      if (response.statusCode == 200) {
        final jsonList = jsonDecode(response.body) as List<dynamic>;
        return jsonList
            .cast<Map<String, dynamic>>()
            .map((json) => RedirectlyLink.fromJson(json))
            .toList();
      } else {
        final error = jsonDecode(response.body) as Map<String, dynamic>;
        throw RedirectlyError.apiError(
          message: error['error'] as String? ?? 'Failed to fetch links',
          statusCode: response.statusCode,
          details: error,
        );
      }
    } catch (e) {
      if (e is RedirectlyError) rethrow;
      throw RedirectlyError.networkError('Network error: $e');
    }
  }

  @override

  /// Get a specific permanent link by slug
  Future<RedirectlyLink> getLink(String slug) async {
    _ensureInitialized();

    try {
      final response = await _httpClient.get(
        Uri.parse('${_config!.effectiveBaseUrl}/api/v1/links/$slug'),
        headers: {
          'Authorization': 'Bearer ${_config!.apiKey}',
        },
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        return RedirectlyLink.fromJson(json);
      } else {
        final error = jsonDecode(response.body) as Map<String, dynamic>;
        throw RedirectlyError.apiError(
          message: error['error'] as String? ?? 'Failed to fetch link',
          statusCode: response.statusCode,
          details: error,
        );
      }
    } catch (e) {
      if (e is RedirectlyError) rethrow;
      throw RedirectlyError.networkError('Network error: $e');
    }
  }

  @override

  /// Get a specific temporary link by slug
  Future<RedirectlyTempLink> getTempLink(String slug) async {
    _ensureInitialized();

    try {
      final response = await _httpClient.get(
        Uri.parse('${_config!.effectiveBaseUrl}/api/v1/temp-links/$slug'),
        headers: {
          'Authorization': 'Bearer ${_config!.apiKey}',
        },
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        return RedirectlyTempLink.fromJson(json);
      } else {
        final error = jsonDecode(response.body) as Map<String, dynamic>;
        throw RedirectlyError.apiError(
          message:
              error['error'] as String? ?? 'Failed to fetch temporary link',
          statusCode: response.statusCode,
          details: error,
        );
      }
    } catch (e) {
      if (e is RedirectlyError) rethrow;
      throw RedirectlyError.networkError('Network error: $e');
    }
  }

  @override

  /// Resolve a link by username and slug (public endpoint)
  Future<RedirectlyLinkResolution> resolveLink(
      String username, String slug) async {
    _ensureInitialized();

    try {
      final response = await _httpClient.get(
        Uri.parse(
            '${_config!.effectiveBaseUrl}/api/v1/resolve/$username/$slug'),
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        return RedirectlyLinkResolution.fromJson(json);
      } else {
        final error = jsonDecode(response.body) as Map<String, dynamic>;
        throw RedirectlyError.apiError(
          message: error['error'] as String? ?? 'Failed to resolve link',
          statusCode: response.statusCode,
          details: error,
        );
      }
    } catch (e) {
      if (e is RedirectlyError) rethrow;
      throw RedirectlyError.networkError('Network error: $e');
    }
  }

  @override

  /// Update a permanent link
  Future<RedirectlyLink> updateLink(
    String slug, {
    required String target,
    Map<String, dynamic>? metadata,
  }) async {
    _ensureInitialized();

    try {
      final response = await _httpClient.put(
        Uri.parse('${_config!.effectiveBaseUrl}/api/v1/links/$slug'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${_config!.apiKey}',
        },
        body: jsonEncode({
          'target': target,
          if (metadata != null) 'metadata': metadata,
        }),
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        return RedirectlyLink.fromJson(json);
      } else {
        final error = jsonDecode(response.body) as Map<String, dynamic>;
        throw RedirectlyError.apiError(
          message: error['error'] as String? ?? 'Failed to update link',
          statusCode: response.statusCode,
          details: error,
        );
      }
    } catch (e) {
      if (e is RedirectlyError) rethrow;
      throw RedirectlyError.networkError('Network error: $e');
    }
  }

  @override

  /// Delete a permanent link
  Future<void> deleteLink(String slug) async {
    _ensureInitialized();

    try {
      final response = await _httpClient.delete(
        Uri.parse('${_config!.effectiveBaseUrl}/api/v1/links/$slug'),
        headers: {
          'Authorization': 'Bearer ${_config!.apiKey}',
        },
      );

      if (response.statusCode != 200) {
        final error = jsonDecode(response.body) as Map<String, dynamic>;
        throw RedirectlyError.apiError(
          message: error['error'] as String? ?? 'Failed to delete link',
          statusCode: response.statusCode,
          details: error,
        );
      }
    } catch (e) {
      if (e is RedirectlyError) rethrow;
      throw RedirectlyError.networkError('Network error: $e');
    }
  }

  @override

  /// Delete a temporary link
  Future<void> deleteTempLink(String slug) async {
    _ensureInitialized();

    try {
      final response = await _httpClient.delete(
        Uri.parse('${_config!.effectiveBaseUrl}/api/v1/temp-links/$slug'),
        headers: {
          'Authorization': 'Bearer ${_config!.apiKey}',
        },
      );

      if (response.statusCode != 200) {
        final error = jsonDecode(response.body) as Map<String, dynamic>;
        throw RedirectlyError.apiError(
          message:
              error['error'] as String? ?? 'Failed to delete temporary link',
          statusCode: response.statusCode,
          details: error,
        );
      }
    } catch (e) {
      if (e is RedirectlyError) rethrow;
      throw RedirectlyError.networkError('Network error: $e');
    }
  }

  @override

  /// Stream of incoming link clicks
  Stream<RedirectlyLinkClick> get onLinkClick => _linkClickController.stream;

  @override

  /// Stream of app install events
  Stream<RedirectlyAppInstallResponse> get onAppInstalled =>
      _appInstallSubject.stream;

  @override

  /// Get the current app install response (if available)
  RedirectlyAppInstallResponse? get currentAppInstall =>
      _appInstallSubject.valueOrNull;

  @override

  /// Get the initial link if app was opened via a link
  Future<RedirectlyLinkClick?> getInitialLink() async {
    _ensureInitialized();

    try {
      final initialUri = await _appLinks.getInitialLink();
      if (initialUri != null) {
        return await _processRedirectlyLink(initialUri);
      }
      return null;
    } catch (e) {
      return RedirectlyLinkClick(
        originalUrl: 'unknown',
        slug: 'unknown',
        username: 'unknown',
        error: RedirectlyError.linkError('Failed to get initial link: $e'),
        receivedAt: DateTime.now(),
      );
    }
  }

  /// Ensure the plugin is initialized
  void _ensureInitialized() {
    if (!_initialized || _config == null) {
      throw RedirectlyError.configError(
        'FlutterRedirectly not initialized. Call initialize() first.',
      );
    }
  }

  /// Log mobile app click to backend (fire-and-forget)
  Future<void> _logMobileClick(
      String username, String slug, Uri originalUri) async {
    if (_config == null) return;

    try {
      // Extract UTM parameters from original URI
      final utmParams = <String, String>{};
      originalUri.queryParameters.forEach((key, value) {
        if (key.startsWith('utm_')) {
          utmParams[key] = value;
        }
      });

      // Collect device information
      final clickData = <String, dynamic>{
        'slug': slug,
        'username': username,
        'device_type':
            'mobile', // Could be enhanced with actual device detection
        'is_mobile_app': true,
        'app_platform': 'flutter',
        'session_id': _generateSessionId(),
        'timezone': DateTime.now().timeZoneOffset.toString(),
        'metadata': {
          'original_url': originalUri.toString(),
          'flutter_plugin_version': packageVersion,
          'dart_version': _getDartVersion(),
        },
      };

      // Add UTM parameters if present
      utmParams.forEach((key, value) {
        clickData[key] = value;
      });

      // Enhanced device info could be added here
      // You might want to use packages like:
      // - device_info_plus for device details
      // - package_info_plus for app version
      // - connectivity_plus for network info

      final response = await _httpClient.post(
        Uri.parse('${_config!.effectiveBaseUrl}/api/v1/clicks'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${_config!.apiKey}',
        },
        body: jsonEncode(clickData),
      );

      if (_config!.enableDebugLogging) {
        if (response.statusCode == 200) {
          print(
              'Mobile click logged successfully: $username/$slug (plugin v$packageVersion)');
        } else {
          print(
              'Failed to log mobile click: ${response.statusCode} ${response.body}');
        }
      }
    } catch (e) {
      if (_config!.enableDebugLogging) {
        print('Error logging mobile click: $e');
      }
      // Fail silently - don't break user experience for analytics
    }
  }

  /// Get Dart version information
  String _getDartVersion() {
    try {
      // This will return something like "3.2.0 (stable)"
      return Platform.version.split(' ').first;
    } catch (e) {
      return 'unknown';
    }
  }

  /// Generate a session ID for tracking user sessions
  String _generateSessionId() {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final random = DateTime.now().microsecondsSinceEpoch % 10000;
    return '${timestamp}_$random';
  }

  /// Track app install if it hasn't been tracked yet
  Future<void> _trackAppInstallIfNeeded() {
    return _installTrackingFuture ??= _trackAppInstallOnce();
  }

  Future<void> _trackAppInstallOnce() async {
    try {
      final hasBeenLogged = await _hasAppInstallBeenTracked();

      if (!hasBeenLogged) {
        if (_config?.enableDebugLogging == true) {
          print('First app launch detected - tracking app install');
        }

        // Claim the install before the POST so a launch that dies mid-flight
        // is visible to the next one (see _hasAppInstallBeenTracked)
        await _writeTrackingSentinel(_statusPending);

        RedirectlyAppInstallResponse response;
        try {
          response = await _logAppInstallInternal();
        } catch (e) {
          // Downgrade the claim to a retry marker: the next launch re-POSTs
          await _writeTrackingSentinel(_statusFailed);
          rethrow;
        }

        // Emit the app install event to the stream
        _appInstallSubject.add(response);

        await _writeTrackingSentinel(_statusTracked);

        if (_config?.enableDebugLogging == true) {
          if (response.matched) {
            print(
                'App install matched to deferred click: ${response.username}/${response.slug}');
          } else {
            print('App install tracked as organic');
          }
        }
      } else {
        if (_config?.enableDebugLogging == true) {
          print('App install already tracked - skipping');
        }
      }
    } catch (e) {
      if (_config?.enableDebugLogging == true) {
        print('Failed to track app install: $e');
      }
      // Don't throw - this shouldn't break initialization
    }
  }

  /// Check if app install has been tracked by looking for tracking file
  Future<bool> _hasAppInstallBeenTracked() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/$_trackingFileName');
      if (!await file.exists()) {
        return false;
      }

      Map<String, dynamic> data;
      try {
        data = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      } catch (_) {
        // Unreadable or legacy sentinel (pre-2.1.8 wrote no status field).
        // Treat as tracked rather than risk a duplicate install POST.
        return true;
      }

      switch (data['status']) {
        case _statusFailed:
          // Retry marker from a failed POST: re-POST on this launch
          return false;
        case _statusPending:
          // Claim from a launch that never finished. A recent claim is
          // likely still in flight in another launch; an expired one is
          // assumed dead and retried to keep at-least-once delivery.
          final attemptedAt =
              DateTime.tryParse(data['attempted_at'] as String? ?? '');
          if (attemptedAt == null) {
            return false;
          }
          return DateTime.now().difference(attemptedAt) < _pendingClaimTtl;
        default:
          // 'tracked', or a legacy sentinel without a status field
          return true;
      }
    } catch (e) {
      if (_config?.enableDebugLogging == true) {
        print('Error checking install tracking file: $e');
      }
      // If we can't check, assume it hasn't been tracked to be safe
      return false;
    }
  }

  /// Write the install tracking sentinel with the given status
  Future<void> _writeTrackingSentinel(String status) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/$_trackingFileName');

      final now = DateTime.now().toIso8601String();
      final data = {
        'status': status,
        // attempted_at ages out a dead pending claim; tracked_at matches
        // the pre-2.1.8 sentinel field
        if (status == _statusPending) 'attempted_at': now,
        if (status == _statusTracked) 'tracked_at': now,
        if (status == _statusFailed) 'last_attempt_at': now,
        'plugin_version': packageVersion,
      };

      await file.writeAsString(jsonEncode(data));

      if (_config?.enableDebugLogging == true) {
        print('App install tracking file written ($status): ${file.path}');
      }
    } catch (e) {
      if (_config?.enableDebugLogging == true) {
        print('Error writing install tracking file: $e');
      }
      // Don't throw - tracking failure shouldn't break the app
    }
  }

  Future<AppInfo> _getAppInfo() async {
    final packageInfo = await PackageInfo.fromPlatform();

    String appName = packageInfo.appName;
    String packageName = packageInfo.packageName;
    String version = packageInfo.version; // e.g. "1.0.3"
    String buildNumber = packageInfo.buildNumber; // e.g. "42"

    return AppInfo(
      appName: appName,
      packageName: packageName,
      version: version,
      buildNumber: buildNumber,
    );
  }

  /// Resolve the Google Play Install Referrer via the consumer provided
  /// callback, if any. Android only, best effort, never throws: without a
  /// referrer the backend simply falls back to fingerprint matching.
  Future<String?> _resolveInstallReferrer() async {
    final provider = _config?.installReferrerProvider;
    if (provider == null || !Platform.isAndroid) {
      return null;
    }
    try {
      // The Play Install Referrer API needs a service connection that can
      // stall on some devices; install tracking must not block on it.
      final value = await provider().timeout(const Duration(seconds: 5));
      if (value == null || value.isEmpty) {
        return null;
      }
      if (_config?.enableDebugLogging == true) {
        print('Install referrer resolved: $value');
      }
      return value;
    } catch (e) {
      if (_config?.enableDebugLogging == true) {
        print('Failed to resolve install referrer: $e');
      }
      return null;
    }
  }

  /// Internal method to log app install
  Future<RedirectlyAppInstallResponse> _logAppInstallInternal() async {
    try {
      // Collect device information
      final deviceInfo = _deviceService.getDeviceInfo();

      final appInfo = await _getAppInfo();

      // The Play Store redirect embeds the click identifier in the Install
      // Referrer; when present the backend prefers it over its IP
      // fingerprint, making deferred attribution deterministic on Android.
      final installReferrer = await _resolveInstallReferrer();

      // Build request with device info
      final request = RedirectlyAppInstallRequest(
        appPlatform: _deviceService.getAppPlatform(),
        appVersion: appInfo.version,
        appBuildNumber: appInfo.buildNumber,
        os: deviceInfo['os'] as String?,
        osVersion: deviceInfo['os_version'] as String?,
        language: deviceInfo['language'] as String?,
        timezone: deviceInfo['timezone'] as String?,
        installReferrer: installReferrer,
        metadata: {
          'flutter_plugin_version': packageVersion,
          'dart_version': deviceInfo['dart_version'],
          'platform': deviceInfo['platform'],
          'is_mobile': deviceInfo['is_mobile'],
          'api_version': 'v1',
          'logged_via': 'flutter_sdk_auto',
          'timestamp': DateTime.now().toIso8601String(),
        },
      );

      if (_config!.enableDebugLogging) {
        print('Logging app install automatically: ${request.toString()}');
      }

      final response = await _httpClient.post(
        Uri.parse('${_config!.effectiveBaseUrl}/api/v1/app-installs'),
        headers: {
          HttpHeaders.contentTypeHeader: 'application/json',
          HttpHeaders.authorizationHeader: 'Bearer ${_config!.apiKey}',
          HttpHeaders.userAgentHeader: Platform.operatingSystem,
        },
        body: jsonEncode(request.toJson()),
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final installResponse = RedirectlyAppInstallResponse.fromJson(json);

        if (_config!.enableDebugLogging) {
          print(
              'App install logged successfully: ${installResponse.toString()}');
        }

        return installResponse;
      } else {
        final error = jsonDecode(response.body) as Map<String, dynamic>;
        throw RedirectlyError.apiError(
          message: error['error'] as String? ?? 'Failed to log app install',
          statusCode: response.statusCode,
          details: error,
        );
      }
    } catch (e) {
      if (_config!.enableDebugLogging) {
        print('Failed to log app install: $e');
      }

      if (e is RedirectlyError) rethrow;
      throw RedirectlyError.networkError(
          'Network error while logging app install: $e');
    }
  }

  @override

  /// Dispose resources
  Future<void> dispose() async {
    await _linkSubscription?.cancel();
    await _linkClickController.close();
    await _appInstallSubject.close();
    _httpClient.close();
    _initialized = false;
    _config = null;
    _initFuture = null;
    _installTrackingFuture = null;
  }
}
