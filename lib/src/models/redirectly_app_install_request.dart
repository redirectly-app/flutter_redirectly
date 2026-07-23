/// App install request model for Redirectly
class RedirectlyAppInstallRequest {
  /// App platform
  final String? appPlatform;

  /// App version
  final String? appVersion;

  /// App build number
  final String? appBuildNumber;

  /// Operating system
  final String? os;

  /// Operating system version
  final String? osVersion;

  /// Device language
  final String? language;

  /// Device timezone
  final String? timezone;

  /// Raw Google Play Install Referrer string (Android only)
  final String? installReferrer;

  /// Additional metadata
  final Map<String, dynamic>? metadata;

  const RedirectlyAppInstallRequest({
    this.appPlatform,
    this.appVersion,
    this.appBuildNumber,
    this.os,
    this.osVersion,
    this.language,
    this.timezone,
    this.installReferrer,
    this.metadata,
  });

  /// Convert to JSON for API request
  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};

    if (appPlatform != null) json['app_platform'] = appPlatform;
    if (appVersion != null) json['app_version'] = appVersion;
    if (appBuildNumber != null) json['app_build_number'] = appBuildNumber;
    if (os != null) json['os'] = os;
    if (osVersion != null) json['os_version'] = osVersion;
    if (language != null) json['language'] = language;
    if (timezone != null) json['timezone'] = timezone;
    if (installReferrer != null) json['install_referrer'] = installReferrer;
    if (metadata != null) json['metadata'] = metadata;

    return json;
  }

  /// Create from JSON
  factory RedirectlyAppInstallRequest.fromJson(Map<String, dynamic> json) {
    return RedirectlyAppInstallRequest(
      appPlatform: json['app_platform'] as String?,
      appVersion: json['app_version'] as String?,
      appBuildNumber: json['app_build_number'] as String?,
      os: json['os'] as String?,
      osVersion: json['os_version'] as String?,
      language: json['language'] as String?,
      timezone: json['timezone'] as String?,
      installReferrer: json['install_referrer'] as String?,
      metadata: json['metadata'] as Map<String, dynamic>?,
    );
  }

  @override
  String toString() {
    return 'RedirectlyAppInstallRequest{appPlatform: $appPlatform, appVersion: $appVersion, appBuildNumber: $appBuildNumber, os: $os, osVersion: $osVersion, language: $language, timezone: $timezone, installReferrer: $installReferrer, metadata: $metadata}';
  }
}

class AppInfo {
  final String appName;
  final String packageName;
  final String version;
  final String buildNumber;

  AppInfo({
    required this.appName,
    required this.packageName,
    required this.version,
    required this.buildNumber,
  });
}
