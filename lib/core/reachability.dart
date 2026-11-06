import 'dart:io';

import 'build_info.dart';

/// Whether an ordinary request gets an answer, from this process, along
/// whatever route the machine is using.
///
/// Used where this process's traffic goes through the tunnel (the desktop
/// service), which makes it the plainest proof that the tunnel carries
/// anything. Not on Android: the app is excluded from its own tunnel there.
class Reachability {
  Reachability({
    this.url = 'https://ifconfig.me/ip',
    this.timeout = const Duration(seconds: 8),
    this.interval = const Duration(seconds: 20),
    Future<bool> Function()? check,
  }) : _check = check;

  final String url;
  final Duration timeout;
  final Duration interval;
  final Future<bool> Function()? _check;

  Future<bool> check() async {
    if (_check case final custom?) return custom();
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final request = await client.getUrl(Uri.parse(url)).timeout(timeout);
      request.headers.set(HttpHeaders.userAgentHeader, 'Caelo/$appVersion');
      final response = await request.close().timeout(timeout);
      await response.drain<void>().timeout(timeout);
      return response.statusCode < 500;
    } on Object {
      return false;
    } finally {
      client.close(force: true);
    }
  }
}
