import 'dart:async';

import 'package:flutter/foundation.dart';

import 'config_store.dart';
import 'ffi/core_library.dart';
import 'tunnel.dart';

/// A [TunnelClient] backed by the real Go core.
///
/// The tunnel it brings up is a real AmneziaWG tunnel with the full obfuscation
/// set, but it runs on a userspace network stack inside this process. Traffic
/// from other applications does not go through it. Routing the machine needs a
/// system tunnel device, which on macOS means a NetworkExtension — until that
/// lands, "connected" here means the handshake completed and this process can
/// reach the internet through the endpoint.
///
/// The core cannot yet tell us anything we did not ask for, so a tunnel that
/// drops on its own will be reported as connected until something asks. That
/// goes away with the gRPC contract, which is the reason it exists.
class CoreTunnelClient implements TunnelClient {
  final _controller = StreamController<TunnelStatus>.broadcast();

  TunnelStatus _current = const TunnelStatus.disconnected();

  @override
  TunnelStatus get current => _current;

  @override
  Stream<TunnelStatus> get changes => _controller.stream;

  @override
  bool get coversWholeMachine => false;

  void _emit(TunnelStatus status) {
    _current = status;
    if (!_controller.isClosed) _controller.add(status);
  }

  @override
  Future<void> connect() async {
    if (_current.phase == TunnelPhase.connecting) return;

    _emit(const TunnelStatus(phase: TunnelPhase.connecting));

    try {
      final configText = await ConfigStore.read();
      if (configText == null) {
        // Nothing to connect to is not a failure of the tunnel. Saying
        // "could not connect" would send someone hunting for a network problem
        // that does not exist.
        _emit(const TunnelStatus.disconnected());
        return;
      }

      final tunnel = await CoreLibrary.connect(configText);

      // The device being up says nothing about the peer. This is the request
      // that decides whether we are actually connected, and its round trip is
      // an honest number to show a person.
      final reachability = await CoreLibrary.check();

      _emit(
        TunnelStatus(
          phase: TunnelPhase.connected,
          node:
              reachability['address'] as String? ??
              tunnel['endpoint'] as String?,
          protocol: (tunnel['obfuscated'] == true)
              ? TunnelProtocol.amneziaWg
              : TunnelProtocol.vless,
          pingMs: (reachability['elapsed_ms'] as num?)?.round(),
        ),
      );
    } on Object catch (error, stack) {
      // Reported rather than swallowed: "could not connect" with nothing
      // behind it is the least actionable message this app can produce.
      debugPrint('Caelo: in-process connect failed: $error\n$stack');
      // Leaving a half-open device behind would make the next attempt fail for
      // a reason that has nothing to do with why this one did.
      await CoreLibrary.disconnect().catchError((_) {});
      _emit(const TunnelStatus(phase: TunnelPhase.failed));
    }
  }

  @override
  Future<void> disconnect() async {
    _emit(const TunnelStatus(phase: TunnelPhase.disconnecting));
    try {
      await CoreLibrary.disconnect();
    } on Object {
      // Nothing useful to do: the intent was to stop, and reporting a tunnel as
      // still up because tearing it down complained helps nobody.
    }
    _emit(const TunnelStatus.disconnected());
  }

  @override
  Future<void> reconnectDifferently() async {
    // There is one configuration and therefore one node. This becomes real with
    // subscriptions, and doing something arbitrary in the meantime would teach
    // the wrong thing about what the button does.
    await disconnect();
    await connect();
  }

  @override
  Future<void> dispose() async {
    await CoreLibrary.disconnect().catchError((_) {});
    await _controller.close();
  }
}
