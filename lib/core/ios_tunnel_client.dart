import 'dart:async';

import 'package:flutter/services.dart';

import 'config_store.dart';
import 'diagnostics.dart';
import 'tunnel.dart';

/// A [TunnelClient] that asks the system to run the tunnel.
///
/// On iOS the app never touches a tunnel. It describes one, asks the system to
/// start it, and is told what happened; the tunnel itself runs in
/// CaeloPacketTunnel, in another process. So unlike every other platform, this
/// client does not drive the core at all — the extension does, and this asks
/// the extension.
///
/// The consequence worth knowing: the tunnel outlives the app completely. It
/// keeps running with the app closed, and the system may stop it without the
/// app being involved, which is why status arrives as a notification rather
/// than as the result of anything requested here.
class IosTunnelClient implements TunnelClient {
  IosTunnelClient() {
    _channel.setMethodCallHandler(_onPlatformCall);
    unawaited(_adoptExistingTunnel());
  }

  static const _channel = MethodChannel('team.gdb.caelo/vpn');

  final _controller = StreamController<TunnelStatus>.broadcast();

  TunnelStatus _current = const TunnelStatus.disconnected();

  /// Remembered so a status notification, which carries only a phase, can keep
  /// saying which endpoint it is about.
  String? _endpoint;

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
    if (call.method != 'status') return;

    final phase = switch (call.arguments as String?) {
      'connected' => TunnelPhase.connected,
      'connecting' => TunnelPhase.connecting,
      'disconnecting' => TunnelPhase.disconnecting,
      _ => TunnelPhase.disconnected,
    };

    Diagnostics.record('system reports the tunnel is $phase');

    _emit(
      TunnelStatus(
        phase: phase,
        node: phase == TunnelPhase.connected ? _endpoint : null,
        protocol: phase == TunnelPhase.connected
            ? TunnelProtocol.amneziaWg
            : null,
      ),
    );
  }

  Future<void> _adoptExistingTunnel() async {
    try {
      if (await _channel.invokeMethod<bool>('isRunning') == true) {
        _emit(const TunnelStatus(phase: TunnelPhase.connected));
      }
    } on Object {
      // Nothing running, or no configuration saved yet. Neither is worth
      // reporting before the user has asked for anything.
    }
  }

  @override
  Future<void> connect() async {
    if (_current.phase == TunnelPhase.connecting) return;

    _emit(const TunnelStatus(phase: TunnelPhase.connecting));
    Diagnostics.record('connect requested');

    try {
      final configText = await ConfigStore.read();
      if (configText == null) {
        // Nothing to connect to is not a failure of the tunnel.
        _emit(const TunnelStatus.disconnected());
        return;
      }

      _endpoint = _endpointIn(configText);

      // Saving the configuration is what raises the system's consent prompt.
      // The result says the system accepted and started it, not that the peer
      // answered — that arrives as a status notification.
      await _channel.invokeMethod<void>('connect', configText);
    } on Object catch (error) {
      Diagnostics.record('connect failed', error: error);
      _emit(const TunnelStatus(phase: TunnelPhase.failed));
    }
  }

  @override
  Future<void> disconnect() async {
    _emit(const TunnelStatus(phase: TunnelPhase.disconnecting));
    try {
      await _channel.invokeMethod<void>('disconnect');
    } on Object catch (error) {
      Diagnostics.record('disconnect failed', error: error);
    }
  }

  @override
  Future<void> reconnectDifferently() async {
    // There is one configuration and therefore one node. This becomes real
    // with subscriptions.
    await disconnect();
    await connect();
  }

  /// The tunnel's own log, fetched from the process that has it.
  ///
  /// The two share no memory, so this is the only way the interface can show
  /// what the handshake did.
  static Future<List<String>> extensionLog() async {
    try {
      final reply = await _channel.invokeMethod<String>('log');
      if (reply == null || reply.isEmpty) return const [];
      return reply.split('\n').where((line) => line.isNotEmpty).toList();
    } on Object {
      // The extension is not running, which is an ordinary state: there is
      // simply nothing to say yet.
      return const [];
    }
  }

  static String? _endpointIn(String config) {
    for (final line in config.split('\n')) {
      if (line.trimLeft().toLowerCase().startsWith('endpoint')) {
        return line.split('=').last.trim();
      }
    }
    return null;
  }

  @override
  Future<void> dispose() async {
    // The tunnel deliberately outlives the app: the system owns it, and
    // closing Caelo is not the same as asking to be exposed.
    await _controller.close();
  }
}
