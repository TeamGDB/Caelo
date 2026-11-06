import 'dart:async';

import 'package:flutter/widgets.dart';

import 'config_store.dart';
import 'tunnel.dart';

/// What deciding where to connect came to.
@immutable
class PreparedConnection {
  /// A candidate is now the active configuration. [id] names it so a retry can
  /// skip it, and [retryable] says whether another candidate may be tried if
  /// this one does not come up — true for an automatic choice, false for a
  /// server somebody picked by hand.
  const PreparedConnection.ready(
    String this.id, {
    this.retryable = false,
    this.latencyMs,
  }) : failure = null;

  const PreparedConnection.failed(TunnelFailure this.failure)
    : id = null,
      retryable = false,
      latencyMs = null;

  /// The attempt was abandoned before anything was chosen, and there is
  /// nothing to say about it.
  const PreparedConnection.cancelled()
    : id = null,
      failure = null,
      retryable = false,
      latencyMs = null;

  final String? id;
  final bool retryable;
  final TunnelFailure? failure;

  /// What the probe that chose it measured, if one did.
  final int? latencyMs;
}

/// Makes the next candidate the active configuration.
///
/// [tried] names what has already been attempted in this connection, so a
/// retry moves on rather than going round again. [cancelled] turns true when
/// the person pressed the button again; long work should look at it and stop.
typedef PrepareConnection =
    Future<PreparedConnection> Function(
      Set<String> tried,
      bool Function() cancelled,
    );

/// Holds the latest [TunnelStatus] and forwards user intent to the core.
///
/// The decision about *where* to connect is handed to [PrepareConnection],
/// which runs right before every connection: whatever the screen shows as the
/// choice and whatever the tunnel dials are then decided in one place, at one
/// moment, and cannot drift apart.
class TunnelController extends ValueNotifier<TunnelStatus> {
  TunnelController(
    TunnelClient client, {
    Future<bool> Function()? isConfigured,
    PrepareConnection? prepare,
    this.maxAttempts = 3,
  }) : _client = client,
       _isConfigured = isConfigured ?? _configurationExists,
       _prepare = prepare,
       super(client.current) {
    // Subscribing to a broadcast stream attaches synchronously, so nothing the
    // core reports between construction and this line can slip past.
    _subscription = _client.changes.listen(_onClientStatus);
    unawaited(refreshConfiguration());
  }

  final TunnelClient _client;
  final Future<bool> Function() _isConfigured;
  final PrepareConnection? _prepare;

  /// How many candidates one press of the button may go through.
  final int maxAttempts;

  late final StreamSubscription<TunnelStatus> _subscription;

  bool _hasConfiguration = false;

  /// Bumped by every press. An attempt that sees a different number has been
  /// superseded and stops touching state.
  int _attempt = 0;

  /// True while a candidate is being chosen, or between a failed candidate and
  /// the next one. The client's own "failed" and "disconnected" are not the
  /// outcome during that time and are not shown.
  bool _choosing = false;

  /// What the probe measured for the node in use. Shown until the tunnel
  /// reports a figure of its own.
  int? _preparedLatencyMs;

  void _onClientStatus(TunnelStatus status) {
    if (_choosing &&
        (status.phase == TunnelPhase.failed ||
            status.phase == TunnelPhase.disconnected)) {
      return;
    }
    if (status.phase == TunnelPhase.connected && status.pingMs == null) {
      value = TunnelStatus(
        phase: status.phase,
        node: status.node,
        protocol: status.protocol,
        pingMs: _preparedLatencyMs,
      );
      return;
    }
    value = status;
  }

  /// Whether "connected" means the whole machine or only this process.
  bool get coversWholeMachine => _client.coversWholeMachine;

  /// Whether there is anything to connect with.
  bool get hasConfiguration => _hasConfiguration;

  /// Re-reads whether a configuration exists. Called at startup and whenever
  /// the user comes back from a screen that could have changed it.
  Future<void> refreshConfiguration() async {
    final found = await _isConfigured().catchError((_) => false);
    if (found == _hasConfiguration) return;

    _hasConfiguration = found;
    notifyListeners();
  }

  static Future<bool> _configurationExists() async =>
      await ConfigStore.read() != null;

  /// The single action the main screen offers.
  ///
  /// Up or on its way up: take it down — mid-connect that reads as "stop
  /// trying". Down or failed: bring it up. While it is going down the button
  /// does nothing (#11): the teardown is seconds at most, and a press that
  /// queued a reconnect behind it would surprise whoever pressed it to make
  /// sure it was off.
  Future<void> toggle() {
    switch (value.phase) {
      case TunnelPhase.connected:
        return _client.disconnect();
      case TunnelPhase.connecting:
        if (_choosing) {
          _attempt++;
          _choosing = false;
          value = const TunnelStatus.disconnected();
          return Future.value();
        }
        _attempt++;
        return _client.disconnect();
      case TunnelPhase.disconnecting:
        return Future.value();
      case TunnelPhase.disconnected:
      case TunnelPhase.failed:
        return _connect();
    }
  }

  Future<void> _connect() async {
    final prepare = _prepare;
    if (prepare == null) return _client.connect();

    final attempt = ++_attempt;
    bool cancelled() => attempt != _attempt;

    _choosing = true;
    _preparedLatencyMs = null;
    value = const TunnelStatus(phase: TunnelPhase.connecting);
    final tried = <String>{};

    try {
      for (var round = 0; round < maxAttempts; round++) {
        final PreparedConnection prepared;
        try {
          prepared = await prepare(tried, cancelled);
        } on Object {
          if (cancelled()) return;
          value = const TunnelStatus(phase: TunnelPhase.failed);
          return;
        }
        if (cancelled()) return;

        if (prepared.failure case final failure?) {
          // Nothing was chosen this round. If an earlier candidate came up
          // and failed, that is the more truthful thing to report.
          value = TunnelStatus(
            phase: TunnelPhase.failed,
            failure: tried.isEmpty ? failure : null,
          );
          return;
        }
        final id = prepared.id;
        if (id == null) {
          value = const TunnelStatus.disconnected();
          return;
        }

        tried.add(id);
        _preparedLatencyMs = prepared.latencyMs;
        _choosing = false;
        await _client.connect();
        if (cancelled()) return;

        final outcome = _client.current.phase;
        if (outcome != TunnelPhase.failed) {
          // The client's last event may still be on its way through the
          // stream; what it reports now is the outcome.
          _onClientStatus(_client.current);
          return;
        }
        if (!prepared.retryable || round == maxAttempts - 1) {
          value = _client.current;
          return;
        }
        _choosing = true;
        value = const TunnelStatus(phase: TunnelPhase.connecting);
      }
    } finally {
      if (attempt == _attempt) _choosing = false;
    }
  }

  Future<void> reconnectDifferently() => _client.reconnectDifferently();

  /// Takes the tunnel down and brings it up again, choosing afresh. For when
  /// the server it was using went away (#111). Does nothing unless connected:
  /// an attempt in flight will choose from the current list anyway, and a
  /// tunnel that is down was not asked to come up.
  Future<void> reconnect() async {
    if (value.phase != TunnelPhase.connected) return;
    await _client.disconnect();
    await _connect();
  }

  @override
  void dispose() {
    _attempt++;
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
