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

  /// Optional override for how the Google Play Install Referrer is read
  /// (Android only, used once, on the first launch install tracking call).
  ///
  /// By default the SDK reads the referrer itself via the
  /// `play_install_referrer` plugin; when an install came through a
  /// Redirectly Play Store redirect, the referrer carries the click
  /// identifier, which makes deferred deep link attribution deterministic
  /// instead of relying on the server side IP fingerprint (which breaks
  /// when the IP changes between click and first launch). Supply this
  /// callback only if you need a custom referrer source; returning null
  /// falls back to fingerprint matching.
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
