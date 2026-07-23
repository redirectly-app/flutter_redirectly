/// Signature of a callback that returns the raw Google Play Install
/// Referrer string, for example via the `android_play_install_referrer`
/// package. Return null when the referrer is unavailable.
typedef InstallReferrerProvider = Future<String?> Function();

/// Configuration for initializing Flutter Redirectly
class RedirectlyConfig {
  /// API key for authentication with Redirectly backend
  final String apiKey;

  /// Whether to enable debug logging
  final bool enableDebugLogging;

  /// Optional callback that supplies the Google Play Install Referrer
  /// (Android only, used once, on the first launch install tracking call).
  ///
  /// When an install came through a Redirectly Play Store redirect, the
  /// referrer carries the click identifier, which makes deferred deep link
  /// attribution deterministic instead of relying on the server side IP
  /// fingerprint (which breaks when the IP changes between click and first
  /// launch). Keeping this a callback keeps the SDK free of native code;
  /// see the README for a ready-made implementation.
  final InstallReferrerProvider? installReferrerProvider;

  const RedirectlyConfig({
    required this.apiKey,
    this.enableDebugLogging = false,
    this.installReferrerProvider,
  });

  /// Default base URL for Redirectly API
  static const String defaultBaseUrl = 'https://redirectly.app';

  /// Get the effective base URL
  String get effectiveBaseUrl => defaultBaseUrl;

  @override
  String toString() {
    return 'RedirectlyConfig(apiKey: ${apiKey.substring(0, 8)}..., baseUrl: $effectiveBaseUrl, debug: $enableDebugLogging)';
  }
}
