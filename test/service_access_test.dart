import 'dart:io';

import 'package:caelo/core/service_client.dart';
import 'package:caelo/core/service_tunnel_client.dart';
import 'package:caelo/core/tunnel.dart';
import 'package:flutter_test/flutter_test.dart';

/// A socket the user may not open says why, and what to do (#116).
void main() {
  group('which advice', () {
    const status = 'Name:\tcaelo\nGroups:\t4 24 27 1000 \nVmPeak:\t1 kB\n';

    bool decide(String etcGroup, {String? user = 'anna', String? proc}) =>
        ServiceAccessDenied.listedButNotCarried(
          etcGroup: etcGroup,
          user: user,
          procStatus: proc ?? status,
        );

    test('listed, and this login predates it: log in again', () {
      expect(decide('sudo:x:27:anna\ncaelo:x:991:bob,anna\n'), isTrue);
    });

    test('listed and carried: not a login problem', () {
      expect(
        decide('caelo:x:991:anna\n', proc: 'Groups:\t4 991 1000\n'),
        isFalse,
      );
    });

    test('not listed: add to the group', () {
      expect(decide('caelo:x:991:bob\n'), isFalse);
      expect(decide('caelo:x:991:\n'), isFalse);
    });

    test('a name that only starts the same is not the user', () {
      expect(decide('caelo:x:991:annabel\n'), isFalse);
      expect(decide('caelonet:x:991:anna\n'), isFalse);
    });

    test('nothing to go on: the general advice', () {
      expect(decide('', user: 'anna'), isFalse);
      expect(decide('caelo:x:991:anna\n', user: null), isFalse);
      expect(decide('caelo:x:991:anna\n', user: ''), isFalse);
    });
  });

  group('a socket that refuses this user', () {
    late Directory directory;
    late ServerSocket server;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('caelo-socket-');
      final path = '${directory.path}/caelo.sock';
      server = await ServerSocket.bind(
        InternetAddress(path, type: InternetAddressType.unix),
        0,
      );
      await Process.run('chmod', ['000', path]);
      ServiceClient.testSocketPath = path;
    });

    tearDown(() async {
      ServiceClient.testSocketPath = null;
      await server.close();
      await directory.delete(recursive: true);
    });

    test('is told apart from a service that is not there', () async {
      await expectLater(
        ServiceClient.status(),
        throwsA(
          isA<ServiceAccessDenied>().having(
            (e) => e.toString(),
            'advice',
            contains('caelo'),
          ),
        ),
      );
      // Still a ServiceUnavailable to anything that catches that.
      await expectLater(
        ServiceClient.status(),
        throwsA(isA<ServiceUnavailable>()),
      );
    });

    test('becomes a failure the screen can name', () async {
      final client = ServiceTunnelClient();
      final seen = <TunnelStatus>[];
      final subscription = client.changes.listen(seen.add);
      await client.connect();
      await Future<void>.delayed(Duration.zero);
      await subscription.cancel();

      expect(seen.last.phase, TunnelPhase.failed);
      expect(seen.last.failure, TunnelFailure.serviceNeedsGroup);
    });

    test('a missing socket stays an ordinary failure', () async {
      ServiceClient.testSocketPath = '${directory.path}/absent.sock';
      await expectLater(
        ServiceClient.status(),
        throwsA(
          isA<ServiceUnavailable>().having(
            (e) => e is ServiceAccessDenied,
            'access denied',
            isFalse,
          ),
        ),
      );
    });
  }, skip: !Platform.isLinux || _isRoot() ? 'needs Linux, not root' : null);
}

bool _isRoot() {
  if (!Platform.isLinux) return false;
  return Process.runSync('id', ['-u']).stdout.toString().trim() == '0';
}
