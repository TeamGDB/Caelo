import 'package:caelo/core/handshake_watchdog.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime.utc(2026, 11, 6, 12);
  int unix(DateTime t) => t.millisecondsSinceEpoch ~/ 1000;

  HandshakeWatchdog watch(Future<int?> Function() read, void Function() dead) =>
      HandshakeWatchdog(read: read, onDead: dead, now: () => now);

  test('a recent handshake is a live session', () async {
    var dead = 0;
    await watch(
      () async => unix(now.subtract(const Duration(seconds: 90))),
      () => dead++,
    ).check();
    expect(dead, 0);
  });

  test('a handshake older than the limit is a dead one (#118)', () async {
    var dead = 0;
    await watch(
      () async => unix(now.subtract(const Duration(minutes: 4))),
      () => dead++,
    ).check();
    expect(dead, 1);
  });

  test('a tunnel that is no longer up is dead', () async {
    var dead = 0;
    await watch(() async => -1, () => dead++).check();
    expect(dead, 1);
  });

  test('a tunnel that cannot be asked is dead', () async {
    var dead = 0;
    await watch(() async => throw StateError('gone'), () => dead++).check();
    expect(dead, 1);
  });

  test('no handshake time at all concludes nothing', () async {
    var dead = 0;
    await watch(() async => null, () => dead++).check();
    expect(dead, 0, reason: 'an older core or service does not report it');
  });
}
