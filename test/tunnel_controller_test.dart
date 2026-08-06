import 'package:caelo/core/tunnel.dart';
import 'package:caelo/core/tunnel_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_tunnel_client.dart';

void main() {
  late FakeTunnelClient client;
  late TunnelController controller;

  setUp(() {
    client = FakeTunnelClient();
    controller = TunnelController(client);
  });

  tearDown(() => controller.dispose());

  test('starts disconnected', () {
    expect(controller.value.phase, TunnelPhase.disconnected);
  });

  test('adopts whatever state the core reports', () async {
    client.emit(
      const TunnelStatus(
        phase: TunnelPhase.connected,
        node: 'Frankfurt 3',
        protocol: TunnelProtocol.amneziaWg,
        pingMs: 42,
      ),
    );
    await Future<void>.delayed(Duration.zero);

    expect(controller.value.phase, TunnelPhase.connected);
    expect(controller.value.node, 'Frankfurt 3');
  });

  test('notifies listeners when the core reports a change', () async {
    var notifications = 0;
    controller.addListener(() => notifications++);

    client.emit(const TunnelStatus(phase: TunnelPhase.connecting));
    await Future<void>.delayed(Duration.zero);

    expect(notifications, 1);
  });

  group('toggle', () {
    Future<void> toggleFrom(TunnelPhase phase) async {
      client.emit(TunnelStatus(phase: phase));
      await Future<void>.delayed(Duration.zero);
      await controller.toggle();
    }

    test('connects when the tunnel is down', () async {
      await toggleFrom(TunnelPhase.disconnected);
      expect(client.calls, ['connect']);
    });

    test('retries after a failure', () async {
      await toggleFrom(TunnelPhase.failed);
      expect(client.calls, ['connect']);
    });

    test('disconnects when the tunnel is up', () async {
      await toggleFrom(TunnelPhase.connected);
      expect(client.calls, ['disconnect']);
    });

    test('cancels an attempt that is still in flight', () async {
      await toggleFrom(TunnelPhase.connecting);
      expect(client.calls, ['disconnect']);
    });

    test('reconnects if pressed while tearing down', () async {
      await toggleFrom(TunnelPhase.disconnecting);
      expect(client.calls, ['connect']);
    });
  });

  test('reconnectDifferently reaches the core', () async {
    await controller.reconnectDifferently();
    expect(client.calls, ['reconnect']);
  });
}
