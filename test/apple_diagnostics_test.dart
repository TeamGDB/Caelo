import 'package:caelo/core/apple_tunnel_client.dart';
import 'package:caelo/core/tunnel.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('team.gdb.caelo/vpn');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test(
    'Apple export keeps live failure and packet counters from the host',
    () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'log');
        return '12:00:00.000  tunnel up\n'
            '12:00:01.000  core packet guard pressure\n'
            '12:00:02.000  state (live): {"guard_dropped_packets":3}\n';
      });
      expect(await AppleTunnelClient.extensionLog(), [
        '12:00:00.000  tunnel up',
        '12:00:01.000  core packet guard pressure',
        '12:00:02.000  state (live): {"guard_dropped_packets":3}',
      ]);
    },
  );

  test(
    'clear removes the extension history as well as the application log',
    () async {
      final calls = <String>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        return null;
      });
      await AppleTunnelClient.clearExtensionLog();
      expect(calls, ['clearLog']);
    },
  );

  test('old or unavailable hosts remain compatible', () async {
    messenger.setMockMethodCallHandler(
      channel,
      (_) async => throw MissingPluginException(),
    );
    expect(await AppleTunnelClient.extensionLog(), isEmpty);
    await AppleTunnelClient.clearExtensionLog();
  });
  test('local packet failure is shown without releasing VPN capture', () async {
    final calls = <String>[];
    var failed = true;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      if (call.method == 'isRunning') return true;
      if (call.method == 'tunnelStatus') {
        return failed
            ? '{"up":false,"diagnostics":{"failure":"closed descriptor"}}'
            : '{"up":true,"diagnostics":{"counters":{}}}';
      }
      return null;
    });
    final client = AppleTunnelClient();
    addTearDown(client.dispose);
    await Future<void>.delayed(Duration.zero);
    expect(client.current.phase, TunnelPhase.connected);
    expect(await client.latency(), isNull);
    expect(client.current.phase, TunnelPhase.failed);
    expect(client.current.failure, TunnelFailure.packetTransportStopped);
    expect(calls, ['isRunning', 'tunnelStatus']);
    for (final phase in ['connected', 'connecting']) {
      await messenger.handlePlatformMessage(
        channel.name,
        const StandardMethodCodec().encodeMethodCall(
          MethodCall('status', phase),
        ),
        (_) {},
      );
      expect(client.current.failure, TunnelFailure.packetTransportStopped);
    }
    failed = false;
    await messenger.handlePlatformMessage(
      channel.name,
      const StandardMethodCodec().encodeMethodCall(
        const MethodCall('status', 'connected'),
      ),
      (_) {},
    );
    expect(client.current.phase, TunnelPhase.connected);
    expect(client.current.failure, isNull);
    expect(calls, isNot(contains('disconnect')));
    await messenger.handlePlatformMessage(
      channel.name,
      const StandardMethodCodec().encodeMethodCall(
        const MethodCall('status', 'disconnected'),
      ),
      (_) {},
    );
    expect(client.current.phase, TunnelPhase.disconnected);
  });

  test(
    'missing diagnostics and pressure alone are not a permanent failure',
    () {
      for (final reply in [
        null,
        '',
        'bad json',
        '[]',
        '{"up":true}',
        '{"diagnostics":{"counters":{"guard_write_pressure_events":30}}}',
        '{"diagnostics":{"failure":""}}',
      ]) {
        expect(AppleTunnelClient.localFailureIn(reply), isNull);
      }
    },
  );
}
