import 'dart:async';

import 'package:flutter/widgets.dart';

import 'tunnel.dart';

/// Holds the latest [TunnelStatus] and forwards user intent to the core.
///
/// Deliberately thin. It does not decide anything — no retry logic, no node
/// preference, no reconnection on network change. All of that belongs to the
/// core, and duplicating any of it here would mean two implementations
/// disagreeing about what is connected.
class TunnelController extends ValueNotifier<TunnelStatus> {
  TunnelController(TunnelClient client)
    : _client = client,
      super(client.current) {
    // Subscribing to a broadcast stream attaches synchronously, so nothing the
    // core reports between construction and this line can slip past.
    _subscription = _client.changes.listen((status) => value = status);
  }

  final TunnelClient _client;
  late final StreamSubscription<TunnelStatus> _subscription;

  /// Whether "connected" means the whole machine or only this process.
  bool get coversWholeMachine => _client.coversWholeMachine;

  /// The single action the main screen offers. What it means depends on where
  /// the tunnel currently is, which is why the button has one label and not two.
  ///
  /// If the tunnel is up or on its way up, tapping takes it down — including
  /// mid-connect, where the tap reads as "stop trying". Otherwise it brings the
  /// tunnel up, including mid-disconnect, where it reads as "I changed my mind".
  Future<void> toggle() {
    return switch (value.phase) {
      TunnelPhase.connected || TunnelPhase.connecting => _client.disconnect(),
      TunnelPhase.disconnected ||
      TunnelPhase.disconnecting ||
      TunnelPhase.failed => _client.connect(),
    };
  }

  Future<void> reconnectDifferently() => _client.reconnectDifferently();

  @override
  void dispose() {
    unawaited(_subscription.cancel());
    unawaited(_client.dispose());
    super.dispose();
  }
}

/// Makes the [TunnelController] reachable from the widget tree.
class TunnelScope extends InheritedNotifier<TunnelController> {
  const TunnelScope({
    required TunnelController super.notifier,
    required super.child,
    super.key,
  });

  static TunnelController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<TunnelScope>();
    assert(scope != null, 'No TunnelScope above this widget');
    return scope!.notifier!;
  }
}
