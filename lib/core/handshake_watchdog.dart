import 'dart:async';

/// Watches a tunnel that says it is up for a server that has stopped answering
/// (#118).
///
/// WireGuard re-handshakes at least every two minutes on a live session, and
/// subscription configurations carry a keepalive, so a last handshake older
/// than [maxAge] means nothing is coming back. Without this the screen went on
/// saying "connected" over a server that had been removed or had died.
class HandshakeWatchdog {
  HandshakeWatchdog({
    required this.read,
    required this.onDead,
    this.interval = const Duration(seconds: 20),
    this.maxAge = const Duration(seconds: 200),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  /// When the server last answered, as Unix seconds; null when the tunnel
  /// reports a handshake time it does not have (an older core or service),
  /// in which case nothing is concluded. Throws, or returns a negative
  /// number, when the tunnel is not up at all.
  final Future<int?> Function() read;

  final void Function() onDead;
  final Duration interval;
  final Duration maxAge;
  final DateTime Function() _now;
  Timer? _timer;
  bool _checking = false;

  void start() {
    stop();
    _timer = Timer.periodic(interval, (_) => unawaited(check()));
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  bool get running => _timer != null;

  /// One look. Public so a test can drive it without waiting.
  Future<void> check() async {
    if (_checking) return;
    _checking = true;
    try {
      int? at;
      try {
        at = await read();
      } on Object {
        at = -1;
      }
      if (at == null) return;
      final age = _now().difference(
        DateTime.fromMillisecondsSinceEpoch(at * 1000),
      );
      if (at < 0 || age > maxAge) {
        stop();
        onDead();
      }
    } finally {
      _checking = false;
    }
  }
}
