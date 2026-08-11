import 'dart:async';

import 'package:flutter/widgets.dart';

import 'config_store.dart';
import 'tunnel.dart';

/// Holds the latest [TunnelStatus] and forwards user intent to the core.
///
/// Deliberately thin. It does not decide anything — no retry logic, no node
/// preference, no reconnection on network change. All of that belongs to the
/// core, and duplicating any of it here would mean two implementations
/// disagreeing about what is connected.
class TunnelController extends ValueNotifier<TunnelStatus> {
  TunnelController(TunnelClient client, {Future<bool> Function()? isConfigured})
    : _client = client,
      _isConfigured = isConfigured ?? _configurationExists,
      super(client.current) {
    // Subscribing to a broadcast stream attaches synchronously, so nothing the
    // core reports between construction and this line can slip past.
    _subscription = _client.changes.listen((status) => value = status);
    unawaited(refreshConfiguration());
  }

  final TunnelClient _client;
  final Future<bool> Function() _isConfigured;
  late final StreamSubscription<TunnelStatus> _subscription;

  bool _hasConfiguration = false;

  /// Whether "connected" means the whole machine or only this process.
  bool get coversWholeMachine => _client.coversWholeMachine;

  /// Whether there is anything to connect with.
  ///
  /// Separate from the tunnel's phase, and the two must not be confused: a
  /// tunnel that is down because nobody asked for it is a different thing to
  /// say than one that is down because there is nothing to dial.
  bool get hasConfiguration => _hasConfiguration;

  /// Re-reads whether a configuration exists. Called at startup and whenever
  /// the user comes back from a screen that could have changed it.
  Future<void> refreshConfiguration() async {
    final found = await _isConfigured().catchError((_) => false);
    if (found == _hasConfiguration) return;

    _hasConfiguration = found;
    // ValueNotifier only notifies when the value changes, and this is not part
    // of the value, so listeners are told directly.
    notifyListeners();
  }

  static Future<bool> _configurationExists() async =>
      await ConfigStore.read() != null;

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
