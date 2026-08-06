import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Raised when the helper is not installed or not running.
class HelperUnavailable implements Exception {
  const HelperUnavailable(this.cause);

  final Object cause;

  @override
  String toString() => 'The Caelo helper is not reachable: $cause';
}

/// Raised when the helper answered and said no.
class HelperRefused implements Exception {
  const HelperRefused(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Talks to the privileged helper over its Unix socket.
///
/// The helper runs as root and does what the app cannot: create a utun
/// interface and take over the machine's routing. Everything it accepts is
/// reachable by whoever can open this socket, so the protocol is four commands
/// and no more.
///
/// The configuration is sent over the socket rather than by path. Handing a
/// root process a filename would turn "connect" into "read any file on this
/// machine".
abstract final class HelperClient {
  static const socketPath = '/var/run/caelo-helper.sock';

  /// Whether the helper is running.
  ///
  /// The socket exists only while it is, which is the question worth asking —
  /// an installed helper that is not running cannot do anything. A plain
  /// `File.exists` would not do: this is a socket, not a file.
  static bool get isRunning =>
      FileSystemEntity.typeSync(socketPath) != FileSystemEntityType.notFound;

  static Future<Map<String, dynamic>> _send(
    Map<String, dynamic> request, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    Socket socket;
    try {
      socket = await Socket.connect(
        InternetAddress(socketPath, type: InternetAddressType.unix),
        0,
      );
    } on Object catch (error) {
      throw HelperUnavailable(error);
    }

    try {
      socket.add(utf8.encode('${jsonEncode(request)}\n'));
      await socket.flush();

      final line = await socket
          .cast<List<int>>()
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .first
          .timeout(timeout);

      final response = jsonDecode(line) as Map<String, dynamic>;
      if (response['ok'] != true) {
        throw HelperRefused(
          response['error'] as String? ?? 'the helper did not say why',
        );
      }
      return response;
    } on TimeoutException catch (error) {
      throw HelperUnavailable(error);
    } finally {
      socket.destroy();
    }
  }

  /// Brings the whole machine's traffic into the tunnel.
  static Future<Map<String, dynamic>> connect(String configText) =>
      _send({'command': 'connect', 'config': configText});

  static Future<Map<String, dynamic>> disconnect() =>
      _send({'command': 'disconnect'});

  /// Asks what is up. Short timeout: this runs on startup, and an unreachable
  /// helper should not hold the first frame.
  static Future<Map<String, dynamic>> status() =>
      _send({'command': 'status'}, timeout: const Duration(seconds: 3));

  static Future<Map<String, dynamic>> version() =>
      _send({'command': 'version'}, timeout: const Duration(seconds: 3));
}
