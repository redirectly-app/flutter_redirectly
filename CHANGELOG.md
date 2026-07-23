# Changelog

All notable changes to the Flutter Redirectly plugin will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.2.0] - 2026-07-23

- Added automatic deterministic Android install attribution via the Google
  Play Install Referrer. On the first launch the SDK reads the referrer
  through the bundled `play_install_referrer` plugin and sends it as
  `install_referrer` on the `/api/v1/app-installs` call; the backend then
  matches the deferred click by the embedded click identifier instead of
  the IP based fingerprint. No setup required. On iOS, without Google Play
  Services, or when the read fails or times out (5s), the field is omitted
  and the backend falls back to fingerprint matching as before.
- `RedirectlyConfig` accepts an optional `installReferrerProvider` callback
  that overrides the built-in referrer read for custom sources.
- NOTE: this reintroduces an Android native dependency
  (`play_install_referrer`), ending the "pure Dart, no native code" stance
  held since 2.0.0, and raises the minimums to Dart 3.7 / Flutter 3.29.
  See the README section "Deterministic Android attribution
  (Install Referrer)".

## [2.1.8] - 2026-07-23

- Fixed duplicate `/api/v1/app-installs` POST on first launch. Concurrent
  `initialize()` calls now share a single initialization instead of both
  passing the already-initialized guard, and install tracking is memoized so
  the install POST can run at most once per process.
- The install sentinel file is now written as a `pending` claim before the
  POST and updated to `tracked` on success or `failed` on error. Failed
  installs still retry on the next launch, and sentinels written by older
  versions are still honored.
- Replaced the runtime pubspec.yaml version lookup (which never worked in
  consuming apps and fell back to a stale `2.0.1`) with a compile time
  version constant, kept in sync with pubspec.yaml by a test.

## [2.1.7] - 2026-01-03

- Updated dependencies to latest versions:
  - `app_links`: ^6.4.1
  - `http`: ^1.6.0
  - `package_info_plus`: ^9.0.0
  - `path_provider`: ^2.1.5
  - `rxdart`: ^0.28.0
  - `flutter_lints`: ^6.0.0

## [2.1.6] - 2025-12-12

- Bug fixes

## [2.1.4] - 2025-12-11

- Added custom parameters to app install response

## [2.1.3] - 2025-12-11

- Bug fixes

## [2.1.2] - 2025-10-1

- Bug fixes

## [2.1.1] - 2025-09-03

- Beta support of deferred deep linking. Bugfixes

## [2.1.0] - 2025-09-02

- Beta support of deferred deep linking
