import 'dart:async';

import 'package:caelo/core/tunnel.dart';

/// A [TunnelClient] that does exactly what a test tells it to and records what
/// it was asked to do. Unlike the stub the app runs against, nothing here is
/// timed or random.
class FakeTunnelClient implements TunnelClient {
  final _controller = StreamController<TunnelStatus>.broadcast();
  final calls = <String>[];

  @override
  TunnelStatus current = const TunnelStatus.disconnected();

  @override
  Stream<TunnelStatus> get changes => _controller.stream;

  /// Push a state as though the core had reported it.
  void emit(TunnelStatus status) {
    current = status;
    _controller.add(status);
  }

  @override
  Future<void> connect() async => calls.add('connect');

  @override
  Future<void> disconnect() async => calls.add('disconnect');

  @override
  Future<void> reconnectDifferently() async => calls.add('reconnect');

  @override
  Future<void> dispose() async {
    calls.add('dispose');
    await _controller.close();
  }
}
