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

/// Raised when the service is reachable but speaks a different protocol.
///
/// This is not a transient failure and retrying will not fix it, which is why
/// it is its own type: treated as an ordinary connect failure it would present
/// as a tunnel that will not come up, and someone would go looking at their
/// network for a problem that is on their disk.
class ServiceVersionMismatch implements Exception {
  const ServiceVersionMismatch({required this.expected, required this.found});

  /// What this application was built against.
  final int expected;

  /// What the service answered. Zero means it is old enough not to have
  /// answered at all, which is itself the answer.
  final int found;

  bool get serviceIsOlder => found < expected;

  @override
  String toString() =>
      'The Caelo service speaks protocol $found and this application speaks '
      '$expected. ${serviceIsOlder ? 'Reinstall Caelo to update the service.' : 'Update the application.'}';
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

  /// The wire format this application was built against.
  ///
  /// Kept in step with `ipc.ProtocolVersion` in the core by hand, because there
  /// is no generated boundary between the two yet. It changes when the meaning
  /// of what crosses the socket changes, not when Caelo is released.
  static const protocolVersion = 1;

  static Future<Map<String, dynamic>> _send(
    Map<String, dynamic> request, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    // On every request rather than only where it is checked: the service
    // refuses anything privileged from a protocol it does not speak, and it can
    // only do that if every request says which one it is.
    final stamped = {...request, 'protocol_version': protocolVersion};
    if (Platform.isWindows) return _decode(await _overPipe(stamped, timeout));
    if (Platform.isLinux) return _decode(await _overSocket(stamped, timeout));
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

  /// Confirms the service on the other end speaks the same protocol, and throws
  /// [ServiceVersionMismatch] if it does not.
  ///
  /// Asked before every attempt rather than once at launch. The service can be
  /// replaced while the app is running — that is precisely what an automatic
  /// update does — and a cached answer from before the upgrade would be a
  /// confident report about a program that no longer exists. It costs one round
  /// trip over a local socket, next to a call that is about to make another.
  static Future<void> ensureCompatible() async {
    final spoken = (await version())['protocol_version'] as int? ?? 0;
    if (spoken == protocolVersion) return;
    throw ServiceVersionMismatch(expected: protocolVersion, found: spoken);
  }
}
