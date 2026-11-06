import 'dart:async';

import 'package:flutter/foundation.dart';

import 'config_store.dart';
import 'reachability.dart';
import 'diagnostics.dart';
import 'handshake_watchdog.dart';
import 'service_client.dart';
import 'tunnel.dart';

/// A [TunnelClient] that drives the privileged service, so the whole machine
/// goes through the tunnel rather than only this process.
///
/// The service owns the tunnel, not the app. That is the point: closing Caelo
/// does not drop the connection, and a crash does not leave the machine routed
/// through an interface nobody is holding open. It also means the app has to
/// ask what is up rather than assume, because the answer can change without the
/// app being involved.
class ServiceTunnelClient implements TunnelClient {
  ServiceTunnelClient({Reachability? reachability})
    : _reachability = reachability ?? Reachability() {
    // The service may already have a tunnel up from a previous run of the app.
    // Starting from "disconnected" and letting someone find out otherwise would
    // be the app lying about the state of their machine.
    unawaited(_adoptExistingTunnel());
  }

  final _controller = StreamController<TunnelStatus>.broadcast();

  TunnelStatus _current = const TunnelStatus.disconnected();

  @override
  TunnelStatus get current => _current;

  @override
  Stream<TunnelStatus> get changes => _controller.stream;

  @override
  bool get coversWholeMachine => true;

  void _emit(TunnelStatus status) {
    _current = status;
    if (status.phase == TunnelPhase.connected) {
      if (!_watchdog.running) _watchdog.start();
      if (_reachabilityTimer == null) _watchReachability(true);
    } else {
      _watchdog.stop();
      _watchReachability(false);
    }
    if (!_controller.isClosed) _controller.add(status);
  }

  Future<void> _adoptExistingTunnel() async {
    if (!ServiceClient.isInstalled) return;
    try {
      final status = await ServiceClient.status();
      if (status['up'] == true) _emit(_statusFrom(status));
    } on Object catch (error, stack) {
      // Reported rather than swallowed: "could not connect" with nothing behind
      // it is the least actionable message this app can produce.
      Diagnostics.record('asking the service what is up failed', error: error);
      debugPrint('Caelo: service status failed: $error\n$stack');
    }
  }

  final Reachability _reachability;
  Timer? _reachabilityTimer;
  int _misses = 0;

  /// The machine's own traffic goes through this tunnel, so an ordinary
  /// request is the test that matters: a server can accept the handshake and
  /// forward nothing, and spidernet revokes a removed server's peers at once
  /// (#121). Two misses in a row, twenty seconds apart, is a lost connection.
  void _watchReachability(bool on) {
    _reachabilityTimer?.cancel();
    _reachabilityTimer = null;
    _misses = 0;
    if (!on) return;
    _reachabilityTimer = Timer.periodic(_reachability.interval, (_) async {
      if (_current.phase != TunnelPhase.connected) return;
      if (await _reachability.check()) {
        _misses = 0;
        return;
      }
      if (++_misses < 2 || _current.phase != TunnelPhase.connected) return;
      Diagnostics.record('nothing loads through the tunnel');
      await _lose();
    });
  }

  Future<void> _lose() async {
    _watchReachability(false);
    // Down before saying so: the controller connects again at once, and a
    // dead tunnel left holding the routes would fail that attempt too.
    await ServiceClient.disconnect().catchError((_) => <String, dynamic>{});
    _emit(
      const TunnelStatus(
        phase: TunnelPhase.failed,
        failure: TunnelFailure.connectionLost,
      ),
    );
  }

  late final _watchdog = HandshakeWatchdog(
    read: () async {
      final status = await ServiceClient.status();
      if (status['up'] != true) return -1;
      return (status['handshake_unix'] as num?)?.toInt();
    },
    onDead: () {
      Diagnostics.record('the server stopped answering');
      _emit(
        const TunnelStatus(
          phase: TunnelPhase.failed,
          failure: TunnelFailure.connectionLost,
        ),
      );
    },
  );

  TunnelStatus _statusFrom(Map<String, dynamic> response) {
    return TunnelStatus(
      phase: TunnelPhase.connected,
      node: response['endpoint'] as String?,
      protocol: response['obfuscated'] == true
          ? TunnelProtocol.amneziaWg
          : TunnelProtocol.vless,
    );
  }

  @override
  Future<void> connect() async {
    if (_current.phase == TunnelPhase.connecting) return;

    _emit(const TunnelStatus(phase: TunnelPhase.connecting));

    try {
      // Before the configuration is read, because a mismatch is not something
      // that having a configuration would fix, and reading one first would
      // report "nothing to connect to" on a machine that has plenty.
      await ServiceClient.ensureCompatible();

      final configText = await ConfigStore.read();
      if (configText == null) {
        // Nothing to connect to is not a failure of the tunnel. Saying "could
        // not connect" would send someone hunting for a network problem that
        // does not exist.
        _emit(const TunnelStatus.disconnected());
        return;
      }

      final up = await ServiceClient.connect(configText);
      // The handshake said the server is there; this says it carries traffic.
      if (!await _reachability.check()) {
        Diagnostics.record('connected, and nothing loads');
        await ServiceClient.disconnect().catchError((_) => <String, dynamic>{});
        _emit(const TunnelStatus(phase: TunnelPhase.failed));
        return;
      }
      _emit(_statusFrom(up));
    } on ServiceVersionMismatch catch (error) {
      // Named rather than folded into the failure below, because retrying is
      // useless and the interface has something specific to tell them. Left as
      // a plain failure it would look like a network problem, and they would go
      // looking for one.
      Diagnostics.record('the app and the service disagree', error: error);
      _emit(
        TunnelStatus(
          phase: TunnelPhase.failed,
          failure: error.serviceIsOlder
              ? TunnelFailure.serviceOlderThanApp
              : TunnelFailure.appOlderThanService,
        ),
      );
    } on Object catch (error) {
      Diagnostics.record('connect failed', error: error);
      _emit(const TunnelStatus(phase: TunnelPhase.failed));
    }
  }

  @override
  Future<void> disconnect() async {
    _emit(const TunnelStatus(phase: TunnelPhase.disconnecting));
    try {
      await ServiceClient.disconnect();
    } on Object catch (error) {
      // The intent was to stop. Reporting the tunnel as still up because
      // tearing it down complained helps nobody, and the service restores the
      // routing on its own way out regardless.
      Diagnostics.record('disconnect complained', error: error);
    }
    _emit(const TunnelStatus.disconnected());
  }

  @override
  Future<void> reconnectDifferently() async {
    // There is one configuration and therefore one node. This becomes real with
    // subscriptions.
    await disconnect();
    await connect();
  }

  @override
  Future<void> dispose() async {
    _watchdog.stop();
    _watchReachability(false);
    // The tunnel deliberately outlives the app. Quitting Caelo is not the same
    // as asking to be exposed, and tearing the tunnel down here would make it
    // exactly that.
    await _controller.close();
  }
}
