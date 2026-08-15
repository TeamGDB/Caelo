import 'dart:io';

import 'package:caelo/core/build_info.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the version the app reports is the version it was built as', () {
    // Two places already carried this string and one of them was the only one
    // anybody looked at. It is now a constant, and this is what keeps the
    // constant honest: a release that bumps pubspec and forgets it would
    // otherwise ship a diagnostic header and a user agent naming the build
    // before it.
    final pubspec = File('pubspec.yaml').readAsLinesSync();
    final line = pubspec.firstWhere((line) => line.startsWith('version:'));
    final value = line.split(':')[1].trim();

    expect(appVersion, value.split('+').first);
    // And the build number, which is what an update check actually compares.
    // A release that moved only this — which is most of them — would otherwise
    // leave the app certain it was already current.
    expect(appBuild, int.parse(value.split('+').last));
  });
}
