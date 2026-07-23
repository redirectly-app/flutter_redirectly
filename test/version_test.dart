import 'dart:io';

import 'package:flutter_redirectly/src/version.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('packageVersion matches pubspec.yaml', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final match =
        RegExp(r'^version:\s*(\S+)', multiLine: true).firstMatch(pubspec);

    expect(match, isNotNull, reason: 'pubspec.yaml must declare a version');
    expect(
      packageVersion,
      match!.group(1),
      reason: 'lib/src/version.dart must be updated together with '
          'the version in pubspec.yaml',
    );
  });
}
