import 'dart:async';
import 'dart:convert';
import 'dart:io';

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
  /// Deliberately not "is it running". Under socket activation the answer to
  /// that is almost always no, and it does not matter: the socket is there, and
  /// opening it brings the service into existence. A `File.exists` would not
  /// do — this is a socket, not a file.
  static bool get isInstalled =>
      Platform.isLinux &&
      FileSystemEntity.typeSync(socketPath) != FileSystemEntityType.notFound;

  static Future<Map<String, dynamic>> _send(
    Map<String, dynamic> request, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    if (!Platform.isLinux) {
      throw const ServiceUnavailable('no service transport on this platform');
    }

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
      final line = await socket
          .cast<List<int>>()
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .first
          .timeout(timeout);

      final response = jsonDecode(line) as Map<String, dynamic>;
      if (response['ok'] != true) {
        throw ServiceRefused(
          response['error'] as String? ?? 'the service did not say why',
        );
      }
      return response;
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
