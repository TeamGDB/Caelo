import 'dart:io';

import 'package:caelo/core/service_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('a service speaking a different protocol', () {
    // The two remedies are different -- one reinstalls Caelo, the other updates
    // it -- so naming the wrong side sends somebody to do a thing that will not
    // help and leaves them believing they already tried.
    test('knows which half is behind', () {
      const serviceBehind = ServiceVersionMismatch(expected: 2, found: 1);
      expect(serviceBehind.serviceIsOlder, isTrue);
      expect(serviceBehind.toString(), contains('Reinstall'));

      const appBehind = ServiceVersionMismatch(expected: 1, found: 2);
      expect(appBehind.serviceIsOlder, isFalse);
      expect(appBehind.toString(), contains('Update the application'));
    });

    // A service old enough to predate the field answers nothing at all, which
    // reads as zero. That is not a missing value to be excused: it is proof the
    // service is older than the app asking.
    test('treats a silent service as an old one', () {
      const silent = ServiceVersionMismatch(
        expected: ServiceClient.protocolVersion,
        found: 0,
      );
      expect(silent.serviceIsOlder, isTrue);
    });

    test('reports both versions, so a log says what disagreed', () {
      const mismatch = ServiceVersionMismatch(expected: 4, found: 3);
      expect(mismatch.toString(), contains('4'));
      expect(mismatch.toString(), contains('3'));
    });
  });

  // The same number lives in two languages with no generated boundary between
  // them. Nothing but this test stops one side from being bumped alone, and a
  // silent disagreement here is exactly the failure the version check exists to
  // prevent -- an app and a service each certain the other is the broken one.
  test('agrees with the protocol version the core speaks', () {
    final source = File('core/internal/ipc/protocol.go').readAsStringSync();
    final declared = RegExp(r'ProtocolVersion\s*=\s*(\d+)').firstMatch(source);

    expect(
      declared,
      isNotNull,
      reason: 'ipc.ProtocolVersion is gone or has been renamed in the core',
    );
    expect(
      int.parse(declared!.group(1)!),
      ServiceClient.protocolVersion,
      reason: 'the core and the app disagree about the wire format',
    );
  });
}
