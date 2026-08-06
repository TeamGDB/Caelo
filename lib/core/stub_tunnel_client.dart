import 'dart:async';
import 'dart:math';

import 'tunnel.dart';

/// A [TunnelClient] that connects to nothing.
///
/// It exists so the interface can be built and reviewed before `caelo-core`
/// speaks gRPC. It moves through the same phases with plausible timing and
/// occasionally fails, because a status screen that has never rendered its own
/// failure state is a status screen that will get it wrong.
///
/// This class is scaffolding. It goes away with the first real core binding,
/// and nothing outside `main.dart` should ever name it.
class StubTunnelClient implements TunnelClient {
  StubTunnelClient({Random? random}) : _random = random ?? Random();

  final Random _random;
  final _controller = StreamController<TunnelStatus>.broadcast();

  TunnelStatus _current = const TunnelStatus.disconnected();
  Timer? _pending;

  static const _nodes = ['Frankfurt 3', 'Amsterdam 1', 'Helsinki 2'];

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

  void _schedule(Duration delay, void Function() action) {
    _pending?.cancel();
    _pending = Timer(delay, action);
  }

  @override
  Future<void> connect() async {
    if (_current.phase == TunnelPhase.connecting ||
        _current.phase == TunnelPhase.connected) {
      return;
    }

    _emit(const TunnelStatus(phase: TunnelPhase.connecting));

    _schedule(Duration(milliseconds: 900 + _random.nextInt(1400)), () {
      // One attempt in six fails, so the failure path stays exercised.
      if (_random.nextInt(6) == 0) {
        _emit(const TunnelStatus(phase: TunnelPhase.failed));
        return;
      }
      _emit(
        TunnelStatus(
          phase: TunnelPhase.connected,
          node: _nodes[_random.nextInt(_nodes.length)],
          protocol: _random.nextBool()
              ? TunnelProtocol.amneziaWg
              : TunnelProtocol.vless,
          pingMs: 24 + _random.nextInt(90),
        ),
      );
    });
  }

  @override
  Future<void> disconnect() async {
    if (_current.phase == TunnelPhase.disconnected) return;

    _emit(const TunnelStatus(phase: TunnelPhase.disconnecting));
    _schedule(const Duration(milliseconds: 450), () {
      _emit(const TunnelStatus.disconnected());
    });
  }

  @override
  Future<void> reconnectDifferently() async {
    final previous = _current.node;
    _emit(const TunnelStatus(phase: TunnelPhase.connecting));
    _schedule(Duration(milliseconds: 700 + _random.nextInt(900)), () {
      final candidates = _nodes.where((node) => node != previous).toList();
      _emit(
        TunnelStatus(
          phase: TunnelPhase.connected,
          node: candidates[_random.nextInt(candidates.length)],
          protocol: TunnelProtocol.amneziaWg,
          pingMs: 24 + _random.nextInt(90),
        ),
      );
    });
  }

  @override
  Future<void> dispose() async {
    _pending?.cancel();
    await _controller.close();
  }
}
