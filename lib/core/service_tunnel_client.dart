import 'dart:async';

import 'package:flutter/foundation.dart';

import 'config_store.dart';
import 'diagnostics.dart';
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
  ServiceTunnelClient() {
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
      final configText = await ConfigStore.read();
      if (configText == null) {
        // Nothing to connect to is not a failure of the tunnel. Saying "could
        // not connect" would send someone hunting for a network problem that
        // does not exist.
        _emit(const TunnelStatus.disconnected());
        return;
      }

      _emit(_statusFrom(await ServiceClient.connect(configText)));
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
    // The tunnel deliberately outlives the app. Quitting Caelo is not the same
    // as asking to be exposed, and tearing the tunnel down here would make it
    // exactly that.
    await _controller.close();
  }
}
