import 'dart:async';

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

    test('ignores a press while tearing down (#11)', () async {
      await toggleFrom(TunnelPhase.disconnecting);
      expect(client.calls, isEmpty);
    });
  });

  group('choosing where to connect', () {
    late _ScriptedClient scripted;

    setUp(() => scripted = _ScriptedClient());

    test('prepares before connecting, every time', () async {
      final order = <String>[];
      final controller = TunnelController(
        scripted..onConnect = () => order.add('connect'),
        prepare: (tried, cancelled) async {
          order.add('prepare');
          return const PreparedConnection.ready('a', retryable: true);
        },
      );
      addTearDown(controller.dispose);

      await controller.toggle();
      expect(order, ['prepare', 'connect']);
      expect(controller.value.phase, TunnelPhase.connected);
    });

    test('shows connecting while the choice is being made', () async {
      final gate = Completer<PreparedConnection>();
      final controller = TunnelController(
        scripted,
        prepare: (tried, cancelled) => gate.future,
      );
      addTearDown(controller.dispose);

      final pending = controller.toggle();
      expect(controller.value.phase, TunnelPhase.connecting);
      gate.complete(const PreparedConnection.ready('a'));
      await pending;
      expect(controller.value.phase, TunnelPhase.connected);
    });

    test('moves to the next server when one does not come up', () async {
      scripted.outcomes = [TunnelPhase.failed, TunnelPhase.connected];
      final seen = <Set<String>>[];
      var n = 0;
      final controller = TunnelController(
        scripted,
        prepare: (tried, cancelled) async {
          seen.add({...tried});
          return PreparedConnection.ready('node-${n++}', retryable: true);
        },
      );
      addTearDown(controller.dispose);

      await controller.toggle();
      expect(seen, [
        <String>{},
        {'node-0'},
      ]);
      expect(scripted.connects, 2);
      expect(controller.value.phase, TunnelPhase.connected);
    });

    test('does not go elsewhere when the server was picked by hand', () async {
      scripted.outcomes = [TunnelPhase.failed];
      var prepared = 0;
      final controller = TunnelController(
        scripted,
        prepare: (tried, cancelled) async {
          prepared++;
          return const PreparedConnection.ready('manual');
        },
      );
      addTearDown(controller.dispose);

      await controller.toggle();
      expect(prepared, 1);
      expect(controller.value.phase, TunnelPhase.failed);
    });

    test('gives up after the attempt limit', () async {
      scripted.outcomes = List.filled(10, TunnelPhase.failed);
      var n = 0;
      final controller = TunnelController(
        scripted,
        maxAttempts: 3,
        prepare: (tried, cancelled) async =>
            PreparedConnection.ready('n${n++}', retryable: true),
      );
      addTearDown(controller.dispose);

      await controller.toggle();
      expect(scripted.connects, 3);
      expect(controller.value.phase, TunnelPhase.failed);
    });

    test('says why when nothing could be chosen', () async {
      final controller = TunnelController(
        scripted,
        prepare: (tried, cancelled) async =>
            const PreparedConnection.failed(TunnelFailure.noServerReachable),
      );
      addTearDown(controller.dispose);

      await controller.toggle();
      expect(controller.value.phase, TunnelPhase.failed);
      expect(controller.value.failure, TunnelFailure.noServerReachable);
      expect(scripted.connects, 0);
    });

    test('a second press while choosing stops it', () async {
      final gate = Completer<PreparedConnection>();
      var sawCancel = false;
      final controller = TunnelController(
        scripted,
        prepare: (tried, cancelled) async {
          final result = await gate.future;
          sawCancel = cancelled();
          return result;
        },
      );
      addTearDown(controller.dispose);

      final pending = controller.toggle();
      await controller.toggle();
      expect(controller.value.phase, TunnelPhase.disconnected);
      gate.complete(const PreparedConnection.ready('a'));
      await pending;
      expect(sawCancel, isTrue);
      expect(scripted.connects, 0);
      expect(controller.value.phase, TunnelPhase.disconnected);
    });

    test('shows the latency the probe measured once connected', () async {
      final controller = TunnelController(
        scripted,
        prepare: (tried, cancelled) async =>
            const PreparedConnection.ready('a', latencyMs: 87),
      );
      addTearDown(controller.dispose);

      await controller.toggle();
      await Future<void>.delayed(Duration.zero);
      expect(controller.value.pingMs, 87);
    });

    test(
      'reconnect goes down and comes back up, choosing again (#111)',
      () async {
        var prepared = 0;
        final controller = TunnelController(
          scripted,
          prepare: (tried, cancelled) async =>
              PreparedConnection.ready('n${prepared++}', retryable: true),
        );
        addTearDown(controller.dispose);

        await controller.toggle();
        await controller.reconnect();

        expect(prepared, 2);
        expect(scripted.connects, 2);
        expect(controller.value.phase, TunnelPhase.connected);
      },
    );

    test('reconnect leaves a tunnel that is down alone', () async {
      var prepared = 0;
      final controller = TunnelController(
        scripted,
        prepare: (tried, cancelled) async {
          prepared++;
          return const PreparedConnection.ready('a');
        },
      );
      addTearDown(controller.dispose);

      await controller.reconnect();
      expect(prepared, 0);
      expect(scripted.connects, 0);
    });

    test('a server that stops answering is left for another (#118)', () async {
      final seen = <Set<String>>[];
      var n = 0;
      final controller = TunnelController(
        scripted,
        prepare: (tried, cancelled) async {
          seen.add({...tried});
          return PreparedConnection.ready('n${n++}', retryable: true);
        },
      );
      addTearDown(controller.dispose);

      await controller.toggle();
      expect(controller.value.phase, TunnelPhase.connected);

      scripted.lose();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(seen, [
        <String>{},
        {'n0'},
      ]);
      expect(scripted.connects, 2);
      expect(controller.value.phase, TunnelPhase.connected);
    });

    test('a prepare that throws reads as a failed attempt', () async {
      final controller = TunnelController(
        scripted,
        prepare: (tried, cancelled) async => throw StateError('disk'),
      );
      addTearDown(controller.dispose);

      await controller.toggle();
      expect(controller.value.phase, TunnelPhase.failed);
    });
  });

  test('reconnectDifferently reaches the core', () async {
    await controller.reconnectDifferently();
    expect(client.calls, ['reconnect']);
  });
}

/// A client whose connections end the way the test says, one per call.
class _ScriptedClient implements TunnelClient {
  final _changes = StreamController<TunnelStatus>.broadcast();
  List<TunnelPhase> outcomes = [];
  int connects = 0;
  void Function()? onConnect;

  @override
  TunnelStatus current = const TunnelStatus.disconnected();

  @override
  Stream<TunnelStatus> get changes => _changes.stream;

  @override
  bool get coversWholeMachine => true;

  @override
  Future<int?> latency() async => null;

  void _emit(TunnelStatus status) {
    current = status;
    _changes.add(status);
  }

  @override
  Future<void> connect() async {
    onConnect?.call();
    final outcome = connects < outcomes.length
        ? outcomes[connects]
        : TunnelPhase.connected;
    connects++;
    _emit(const TunnelStatus(phase: TunnelPhase.connecting));
    await Future<void>.delayed(Duration.zero);
    _emit(TunnelStatus(phase: outcome));
  }

  @override
  Future<void> disconnect() async {
    _emit(const TunnelStatus(phase: TunnelPhase.disconnecting));
    _emit(const TunnelStatus.disconnected());
  }

  /// The server went quiet under a live tunnel.
  void lose() => _emit(
    const TunnelStatus(
      phase: TunnelPhase.failed,
      failure: TunnelFailure.connectionLost,
    ),
  );

  @override
  Future<void> reconnectDifferently() async {}

  @override
  Future<void> dispose() => _changes.close();
}
