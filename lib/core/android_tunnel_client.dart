import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:flutter/services.dart';

import 'config_store.dart';
import 'ffi/core_library.dart';
import 'tunnel.dart';

/// A [TunnelClient] that routes the whole device through the tunnel.
///
/// Android does not let an application open a tun device. The platform side
/// asks the system for one — which is where the consent dialog comes from —
/// and hands back a descriptor already addressed and routed. Everything after
/// that is the Go core, driven from here over FFI.
///
/// So the split is the opposite of macOS: there, the privileged half does the
/// networking and the core rides along; here, the system does the networking
/// and the core does nothing else.
class AndroidTunnelClient implements TunnelClient {
  AndroidTunnelClient() {
    _channel.setMethodCallHandler(_onPlatformCall);
    unawaited(_adoptExistingTunnel());
  }

  static const _channel = MethodChannel('team.gdb.caelo/vpn');

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

  Future<void> _onPlatformCall(MethodCall call) async {
    // The system can take the tunnel away at any moment: another VPN starts,
    // or the user revokes permission. The core goes on running against a
    // descriptor that no longer carries anything, so being told is the only way
    // the screen stops claiming to be connected.
    if (call.method == 'revoked') {
      await CoreLibrary.disconnectFd().catchError((_) {});
      _emit(const TunnelStatus(phase: TunnelPhase.disconnected));
    }
  }

  Future<void> _adoptExistingTunnel() async {
    try {
      final running = await _channel.invokeMethod<bool>('isRunning');
      if (running == true) {
        _emit(const TunnelStatus(phase: TunnelPhase.connected));
      }
    } on Object catch (error, stack) {
      // Reported rather than swallowed: "could not connect" with nothing
      // behind it is the least actionable message this app can produce.
      debugPrint('Caelo: android connect failed: $error\n$stack');
      // Nothing to adopt. The app has not been asked to do anything yet.
    }
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

      // Permission is the user's to give, and the dialog is the system's. A
      // refusal is a decision, not an error, so it reads as still disconnected
      // rather than as something having gone wrong.
      final permitted = await _channel.invokeMethod<bool>('prepare');
      if (permitted != true) {
        _emit(const TunnelStatus.disconnected());
        return;
      }

      final description = await CoreLibrary.describe(configText);

      final fd = await _channel.invokeMethod<int>('establish', {
        'addresses': (description['addresses'] as List?)?.cast<String>() ?? [],
        'routes': (description['allowed_ips'] as List?)?.cast<String>() ?? [],
        'dns': (description['dns'] as List?)?.cast<String>() ?? [],
        'mtu': description['mtu'] as int? ?? 1420,
      });
      if (fd == null || fd < 0) {
        throw StateError('the system did not provide a tunnel descriptor');
      }

      await CoreLibrary.connectFd(fd, configText);

      // The tunnel's own packets must not be routed into the tunnel. Skipping
      // this produces a connection that looks established and reaches nothing,
      // which is the hardest kind of failure to read.
      await _channel.invokeMethod<bool>(
        'protect',
        await CoreLibrary.socketFds(),
      );

      _emit(
        TunnelStatus(
          phase: TunnelPhase.connected,
          node: description['endpoint'] as String?,
          protocol: description['obfuscated'] == true
              ? TunnelProtocol.amneziaWg
              : TunnelProtocol.vless,
        ),
      );
    } on Object {
      // A half-established tunnel would make the next attempt fail for a reason
      // that has nothing to do with why this one did.
      await CoreLibrary.disconnectFd().catchError((_) {});
      await _channel.invokeMethod<void>('stop').catchError((_) {});
      _emit(const TunnelStatus(phase: TunnelPhase.failed));
    }
  }

  @override
  Future<void> disconnect() async {
    _emit(const TunnelStatus(phase: TunnelPhase.disconnecting));
    // The core closes the descriptor, so it goes first: stopping the service
    // beneath a device that is still being read is the wrong order.
    await CoreLibrary.disconnectFd().catchError((_) {});
    await _channel.invokeMethod<void>('stop').catchError((_) {});
    _emit(const TunnelStatus.disconnected());
  }

  @override
  Future<void> reconnectDifferently() async {
    // There is one configuration and therefore one node. This becomes real
    // with subscriptions.
    await disconnect();
    await connect();
  }

  @override
  Future<void> dispose() async {
    // The tunnel outlives the app on purpose. Leaving the screen is not the
    // same as asking to be exposed, and the foreground service exists so that
    // it does not have to be.
    await _controller.close();
  }
}
