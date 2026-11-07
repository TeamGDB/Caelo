import 'dart:async';

import 'package:caelo/core/apple_tunnel_client.dart';
import 'package:caelo/core/tunnel.dart';
import 'package:caelo/core/tunnel_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_tunnel_client.dart';

/// The live ping on the main screen (#156).
void main() {
  late FakeTunnelClient client;
  late TunnelController controller;
  var built = false;

  const connected = TunnelStatus(
    phase: TunnelPhase.connected,
    node: 'Aurora',
    protocol: TunnelProtocol.amneziaWg,
    pingMs: 120,
  );

  TunnelController build({Duration interval = const Duration(hours: 1)}) {
    built = true;
    return TunnelController(
      client,
      isConfigured: () async => true,
      livePingInterval: interval,
    );
  }

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  setUp(() {
    client = FakeTunnelClient();
    built = false;
  });
  tearDown(() {
    if (built) controller.dispose();
  });

  group('asking', () {
    test('nothing is asked while not connected', () async {
      controller = build(interval: const Duration(milliseconds: 5));
      for (final phase in [
        TunnelPhase.disconnected,
        TunnelPhase.connecting,
        TunnelPhase.disconnecting,
        TunnelPhase.failed,
      ]) {
        client.emit(TunnelStatus(phase: phase));
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(client.latencyAsked, 0);
      expect(controller.livePingMs.value, isNull);
    });

    test('asked at once on connecting, then every interval', () async {
      client.latencyAnswer = () async => 48;
      controller = build(interval: const Duration(milliseconds: 10));
      client.emit(connected);
      await settle();
      expect(client.latencyAsked, 1, reason: 'at once, not after a wait');
      expect(controller.livePingMs.value, 48);

      await Future<void>.delayed(const Duration(milliseconds: 55));
      expect(client.latencyAsked, greaterThanOrEqualTo(4));
    });

    test('a tunnel already up when the app starts is asked too', () async {
      client.current = connected;
      client.latencyAnswer = () async => 37;
      controller = build();
      await settle();
      expect(controller.livePingMs.value, 37);
    });

    test('a slow answer is not asked again over the top of', () async {
      final pending = Completer<int?>();
      client.latencyAnswer = () => pending.future;
      controller = build(interval: const Duration(milliseconds: 5));
      client.emit(connected);
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(client.latencyAsked, 1);
      pending.complete(51);
      await settle();
      expect(controller.livePingMs.value, 51);
    });
  });

  group('the figure', () {
    test('follows the answers', () async {
      var answer = 48;
      client.latencyAnswer = () async => answer;
      controller = build();
      client.emit(connected);
      await settle();
      expect(controller.livePingMs.value, 48);

      answer = 61;
      await controller.askLatency();
      expect(controller.livePingMs.value, 61);
    });

    test('no figure keeps the last one rather than going back to the '
        "probe's", () async {
      int? answer = 48;
      client.latencyAnswer = () async => answer;
      controller = build();
      client.emit(connected);
      await settle();

      answer = null;
      await controller.askLatency();
      expect(controller.livePingMs.value, 48);
    });

    test('nothing that is not a positive figure is shown', () async {
      int? answer = 0;
      client.latencyAnswer = () async => answer;
      controller = build();
      client.emit(connected);
      await settle();
      expect(controller.livePingMs.value, isNull);
      answer = -5;
      await controller.askLatency();
      expect(controller.livePingMs.value, isNull);
    });

    test('a failure to ask is no figure, not a crash', () async {
      client.latencyAnswer = () async => throw StateError('extension gone');
      controller = build();
      client.emit(connected);
      await settle();
      expect(controller.livePingMs.value, isNull);
      expect(controller.value.phase, TunnelPhase.connected);
    });

    test('an older core that never reports one leaves the probe figure in '
        'place', () async {
      controller = build();
      client.emit(connected);
      await settle();
      expect(controller.livePingMs.value, isNull);
      expect(controller.value.pingMs, 120);
    });

    test('is forgotten when the tunnel goes down', () async {
      client.latencyAnswer = () async => 48;
      controller = build();
      client.emit(connected);
      await settle();
      client.emit(const TunnelStatus(phase: TunnelPhase.disconnecting));
      await settle();
      expect(controller.livePingMs.value, isNull);
    });

    test('is forgotten on the way to another server, so the old one is not '
        'shown for the new', () async {
      client.latencyAnswer = () async => 48;
      controller = build();
      client.emit(connected);
      await settle();
      client.emit(const TunnelStatus(phase: TunnelPhase.connecting));
      await settle();
      expect(controller.livePingMs.value, isNull);
    });

    test(
      'an answer that arrives after the tunnel went down is dropped',
      () async {
        final pending = Completer<int?>();
        client.latencyAnswer = () => pending.future;
        controller = build();
        client.emit(connected);
        await settle();
        client.emit(const TunnelStatus.disconnected());
        await settle();
        pending.complete(48);
        await settle();
        expect(controller.livePingMs.value, isNull);
      },
    );
  });

  group('in the background', () {
    test('nothing is asked, and asking resumes on return', () async {
      client.latencyAnswer = () async => 48;
      controller = build(interval: const Duration(milliseconds: 5));
      client.emit(connected);
      await settle();
      controller.foreground = false;
      final asked = client.latencyAsked;
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(client.latencyAsked, asked);
      // The last figure stays for when the app comes back.
      expect(controller.livePingMs.value, 48);

      controller.foreground = true;
      await settle();
      expect(client.latencyAsked, asked + 1);
    });

    test(
      'a tunnel that comes up in the background is asked on return',
      () async {
        controller = build();
        controller.foreground = false;
        client.emit(connected);
        await settle();
        expect(client.latencyAsked, 0);
        controller.foreground = true;
        await settle();
        expect(client.latencyAsked, 1);
      },
    );
  });

  test('the figure does not touch the status, so nothing that listens to it '
      'is set off every two seconds', () async {
    var answer = 40;
    client.latencyAnswer = () async => answer++;
    controller = build();
    client.emit(connected);
    await settle();
    var notified = 0;
    controller.addListener(() => notified++);
    final before = controller.value;

    for (var i = 0; i < 5; i++) {
      await controller.askLatency();
    }
    expect(controller.livePingMs.value, 45);
    expect(notified, 0);
    expect(identical(controller.value, before), isTrue);
  });

  test('stops with the controller, and a late answer does not throw', () async {
    final pending = Completer<int?>();
    client.latencyAnswer = () => pending.future;
    controller = TunnelController(
      client,
      isConfigured: () async => true,
      livePingInterval: const Duration(milliseconds: 5),
    );
    client.emit(connected);
    await settle();
    controller.dispose();
    pending.complete(48);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(client.latencyAsked, 1);
    // tearDown disposes again; a fresh one keeps that harmless.
    controller = build();
  });

  group('reading the status reply', () {
    test('the figure in a reply from a tunnel that is up', () {
      expect(liveLatencyIn({'ok': true, 'up': true, 'latency_ms': 47}), 47);
      expect(liveLatencyIn({'up': true, 'latency_ms': 46.6}), 47);
    });

    test('none from an older core or service, which does not send it', () {
      expect(
        liveLatencyIn({'ok': true, 'up': true, 'handshake_unix': 1700000000}),
        isNull,
      );
    });

    test('none from a tunnel that is not up', () {
      expect(liveLatencyIn({'up': false, 'latency_ms': 47}), isNull);
      expect(liveLatencyIn({'latency_ms': 47}), isNull);
      expect(liveLatencyIn({'ok': false, 'error': 'x'}), isNull);
    });

    test('none from anything that is not a figure', () {
      for (final value in <Object?>[0, -3, '47', null, double.nan, true]) {
        expect(
          liveLatencyIn({'up': true, 'latency_ms': value}),
          isNull,
          reason: '$value',
        );
      }
      expect(liveLatencyIn(null), isNull);
      expect(liveLatencyIn('up'), isNull);
    });

    test("the extension's reply, as text", () {
      expect(
        AppleTunnelClient.latencyIn('{"ok":true,"up":true,"latency_ms":52}'),
        52,
      );
      expect(AppleTunnelClient.latencyIn('{"ok":true,"up":true}'), isNull);
      expect(AppleTunnelClient.latencyIn(null), isNull);
      expect(AppleTunnelClient.latencyIn(''), isNull);
      expect(AppleTunnelClient.latencyIn('not json'), isNull);
      expect(AppleTunnelClient.latencyIn('[1,2]'), isNull);
    });
  });
}
