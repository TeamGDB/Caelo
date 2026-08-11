import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'service_pipe.dart';

/// Raised when the privileged service is not installed, or could not be
/// reached.
class ServiceUnavailable implements Exception {
  const ServiceUnavailable(this.cause);

  final Object cause;

  @override
  String toString() => 'The Caelo service is not reachable: $cause';
}

/// Raised when the service answered and said no.
class ServiceRefused implements Exception {
  const ServiceRefused(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Talks to the privileged service.
///
/// The service runs as root and does what the app may not: create a tunnel
/// interface and take over the machine's routing. Everything it accepts is
/// reachable by whoever can open its socket, so the protocol is four commands
/// and no more.
///
/// The configuration is sent over the socket rather than by path. Handing a
/// root process a filename would turn "connect" into "read any file on this
/// machine".
abstract final class ServiceClient {
  /// Where the service listens on Linux. The socket is created by systemd, not
  /// by the service, and exists whether or not anything is running: connecting
  /// to it is what starts the service.
  static const socketPath = '/run/caelo/caelo.sock';

  /// Whether this machine has the service installed.
  ///
  /// Deliberately not "is it running". Both platforms start it on demand — the
  /// socket on Linux, a named-pipe trigger on Windows — so the answer to "is it
  /// running" is almost always no and never useful. What is asked instead is
  /// whether the thing that starts it is present.
  static bool get isInstalled {
    if (Platform.isWindows) return ServicePipe.isInstalled;
    if (!Platform.isLinux) return false;
    // A socket, not a file, so File.exists would not do.
    return FileSystemEntity.typeSync(socketPath) !=
        FileSystemEntityType.notFound;
  }

  static Future<Map<String, dynamic>> _send(
    Map<String, dynamic> request, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    if (Platform.isWindows) return _decode(await _overPipe(request, timeout));
    if (Platform.isLinux) return _decode(await _overSocket(request, timeout));
    throw const ServiceUnavailable('no service transport on this platform');
  }

  static Map<String, dynamic> _decode(String line) {
    final response = jsonDecode(line) as Map<String, dynamic>;
    if (response['ok'] != true) {
      throw ServiceRefused(
        response['error'] as String? ?? 'the service did not say why',
      );
    }
    return response;
  }

  static Future<String> _overPipe(
    Map<String, dynamic> request,
    Duration timeout,
  ) async {
    try {
      return await ServicePipe.exchange(jsonEncode(request), timeout);
    } on ServicePipeUnavailable catch (error) {
      throw ServiceUnavailable(error);
    }
  }

  static Future<String> _overSocket(
    Map<String, dynamic> request,
    Duration timeout,
  ) async {
    Socket socket;
    try {
      socket = await Socket.connect(
        InternetAddress(socketPath, type: InternetAddressType.unix),
        0,
      );
    } on Object catch (error) {
      throw ServiceUnavailable(error);
    }

    try {
      socket.add(utf8.encode('${jsonEncode(request)}\n'));
      await socket.flush();

      // One line, then the service closes. A reply that never arrives is the
      // same problem as a service that is not there, and is reported as one.
      return await socket
          .cast<List<int>>()
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .first
          .timeout(timeout);
    } on TimeoutException catch (error) {
      throw ServiceUnavailable(error);
    } finally {
      socket.destroy();
    }
  }

  /// Brings the whole machine's traffic into the tunnel.
  static Future<Map<String, dynamic>> connect(String configText) =>
      _send({'command': 'connect', 'config': configText});

  static Future<Map<String, dynamic>> disconnect() =>
      _send({'command': 'disconnect'});

  /// Asks what is up.
  ///
  /// Short timeout: this runs at startup, and a service that is slow to answer
  /// should not hold the first frame. It is also the call that starts the
  /// service under socket activation, so "slow" here means "systemd is starting
  /// it", which is still a second or two at most.
  static Future<Map<String, dynamic>> status() =>
      _send({'command': 'status'}, timeout: const Duration(seconds: 5));

  static Future<Map<String, dynamic>> version() =>
      _send({'command': 'version'}, timeout: const Duration(seconds: 5));
}
