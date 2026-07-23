library flutter_redirectly;

import 'dart:async';

import 'src/flutter_redirectly_impl.dart';
import 'src/models/models.dart';

// Export all models and types
export 'src/models/models.dart';
export 'src/models/redirectly_link_extension.dart';

/// Abstract interface for Flutter Redirectly plugin
///
/// This interface provides functionality similar to Firebase Dynamic Links
/// but using your own Redirectly backend.
abstract interface class FlutterRedirectly {
  /// Factory constructor that returns the singleton instance
  factory FlutterRedirectly() => FlutterRedirectlyImpl.instance;

  /// Initialize the plugin with configuration
  Future<void> initialize(RedirectlyConfig config);

  /// Create a permanent link
  Future<RedirectlyLink> createLink({
    required String slug,
    required String target,
    Map<String, dynamic>? metadata,
  });

  /// Create a temporary link
  Future<RedirectlyTempLink> createTempLink({
    required String target,
    String? slug,
    int ttlSeconds = 900,
  });

  /// Get all permanent links
  Future<List<RedirectlyLink>> getLinks();

  /// Get a specific permanent link by slug
  Future<RedirectlyLink> getLink(String slug);

  /// Get a specific temporary link by slug
  Future<RedirectlyTempLink> getTempLink(String slug);

  /// Resolve a link by username and slug (public endpoint)
  Future<RedirectlyLinkResolution> resolveLink(
    String username,
    String slug,
  );

  /// Update a permanent link
  Future<RedirectlyLink> updateLink(
    String slug, {
    required String target,
    Map<String, dynamic>? metadata,
  });

  /// Delete a permanent link
  Future<void> deleteLink(String slug);

  /// Delete a temporary link
  Future<void> deleteTempLink(String slug);

  /// Stream of incoming link clicks
  Stream<RedirectlyLinkClick> get onLinkClick;

  /// Stream of app install events
  Stream<RedirectlyAppInstallResponse> get onAppInstalled;

  /// Get the current app install response (if available)
  RedirectlyAppInstallResponse? get currentAppInstall;

  /// Get the initial link if app was opened via a link
  Future<RedirectlyLinkClick?> getInitialLink();

  /// Dispose resources
  Future<void> dispose();
}
