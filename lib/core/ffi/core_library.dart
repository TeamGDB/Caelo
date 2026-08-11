import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';

typedef _StringNative = Pointer<Utf8> Function();
typedef _ConnectNative = Pointer<Utf8> Function(Pointer<Utf8>);
typedef _ConnectFdNative = Pointer<Utf8> Function(Int32, Pointer<Utf8>);
typedef _ConnectFd = Pointer<Utf8> Function(int, Pointer<Utf8>);
typedef _CheckNative = Pointer<Utf8> Function(Pointer<Utf8>, Int32);
typedef _Check = Pointer<Utf8> Function(Pointer<Utf8>, int);
typedef _FreeNative = Void Function(Pointer<Utf8>);
typedef _Free = void Function(Pointer<Utf8>);

/// What the core reports about itself.
class CoreVersion {
  const CoreVersion({required this.core, required this.amneziaWg});

  final String core;
  final String amneziaWg;
}

/// Raised when the core cannot be loaded. Carries the paths that were tried,
/// because "library not found" without them is the least useful error message
/// in software.
class CoreUnavailable implements Exception {
  CoreUnavailable(this.attempted, this.cause);

  final List<String> attempted;
  final Object cause;

  @override
  String toString() =>
      'Could not load the Caelo core. Tried: ${attempted.join(', ')}. ($cause)';
}

/// Raised when the core was reached but refused to do the thing.
class CoreFailure implements Exception {
  CoreFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Binds the Go core's C interface.
///
/// Every call into the core blocks — bringing a tunnel up waits on a netstack,
/// and checking it waits on the network. So each one runs on its own isolate.
/// The library itself is loaded per process rather than per isolate, and the
/// tunnel lives in the core's own memory, so a tunnel opened from one call is
/// the same tunnel a later call tears down.
///
/// This is scaffolding. The real contract is gRPC over a proto, which lets the
/// core push state instead of being asked for it — a tunnel that drops on its
/// own cannot announce itself through a function that returns once.
abstract final class CoreLibrary {
  /// Apple platforms want a dylib; everywhere else it is a plain shared
  /// object. On Android the loader finds it by name inside the APK's lib
  /// directory, which is why nothing here builds a path.
  static String get _libraryName =>
      Platform.isMacOS || Platform.isIOS ? 'libcaelo.dylib' : 'libcaelo.so';

  /// Set `CAELO_CORE_DYLIB` to load a specific build — how you point a running
  /// app at a core you just rebuilt without reinstalling it.
  static const _overrideVariable = 'CAELO_CORE_DYLIB';

  static DynamicLibrary _open() {
    final attempted = <String>[];
    Object? lastError;

    for (final candidate in _candidatePaths()) {
      attempted.add(candidate);
      try {
        return DynamicLibrary.open(candidate);
      } on ArgumentError catch (error) {
        lastError = error;
      }
    }

    throw CoreUnavailable(attempted, lastError ?? 'no candidates');
  }

  static Iterable<String> _candidatePaths() sync* {
    final override = Platform.environment[_overrideVariable];
    if (override != null && override.isNotEmpty) yield override;

    // Inside an installed app the dylib sits in Contents/Frameworks, which is
    // already on the executable's rpath, so the bare name resolves.
    yield _libraryName;

    // A checkout with caelo-core beside it, built but not yet bundled.
    yield '../caelo-core/build/$_libraryName';
  }

  /// Reads a string the core allocated, then hands the memory back. Every
  /// string crossing this boundary is ours and leaks if we forget.
  static Map<String, dynamic> _consume(
    DynamicLibrary library,
    Pointer<Utf8> pointer,
  ) {
    if (pointer == nullptr) return const {};
    try {
      return jsonDecode(pointer.toDartString()) as Map<String, dynamic>;
    } finally {
      library.lookupFunction<_FreeNative, _Free>('caelo_free')(pointer);
    }
  }

  static Map<String, dynamic> _require(Map<String, dynamic> result) {
    if (result['ok'] == true) return result;
    throw CoreFailure(result['error'] as String? ?? 'the core did not say why');
  }

  /// Cheap and synchronous — reads a constant out of the loaded image.
  static CoreVersion version() {
    final library = _open();
    final decoded = _consume(
      library,
      library.lookupFunction<_StringNative, _StringNative>('caelo_version')(),
    );

    return CoreVersion(
      core: decoded['core'] as String? ?? 'unknown',
      amneziaWg: decoded['amneziawg'] as String? ?? 'unknown',
    );
  }

  /// Brings up the tunnel described by an AmneziaWG `.conf`.
  ///
  /// Returning normally means the device is configured and running, not that
  /// the peer answered. WireGuard has no connect step; only traffic proves the
  /// far end is there, which is what [check] is for.
  static Future<Map<String, dynamic>> connect(String configText) {
    return Isolate.run(() {
      final library = _open();
      final config = configText.toNativeUtf8();
      try {
        return _require(
          _consume(
            library,
            library.lookupFunction<_ConnectNative, _ConnectNative>(
              'caelo_connect',
            )(config),
          ),
        );
      } finally {
        malloc.free(config);
      }
    });
  }

  /// Fetches [url] through the live tunnel. The response body is the evidence
  /// that traffic actually left through the endpoint.
  static Future<Map<String, dynamic>> check({
    String url = 'https://ifconfig.me/ip',
    Duration timeout = const Duration(seconds: 20),
  }) {
    final timeoutMs = timeout.inMilliseconds;
    return Isolate.run(() {
      final library = _open();
      final target = url.toNativeUtf8();
      try {
        return _require(
          _consume(
            library,
            library.lookupFunction<_CheckNative, _Check>('caelo_check')(
              target,
              timeoutMs,
            ),
          ),
        );
      } finally {
        malloc.free(target);
      }
    });
  }

  static Future<void> disconnect() {
    return Isolate.run(() {
      final library = _open();
      _consume(
        library,
        library.lookupFunction<_StringNative, _StringNative>(
          'caelo_disconnect',
        )(),
      );
    });
  }

  /// Reads the addresses, routes, MTU and DNS out of a configuration without
  /// connecting anything.
  ///
  /// Android's VpnService.Builder needs all of it before it will hand back a
  /// descriptor. It comes from the core because a second parser for this
  /// format would eventually disagree with the one that actually dials.
  static Future<Map<String, dynamic>> describe(String configText) {
    return Isolate.run(() {
      final library = _open();
      final config = configText.toNativeUtf8();
      try {
        return _require(
          _consume(
            library,
            library.lookupFunction<_ConnectNative, _ConnectNative>(
              'caelo_describe',
            )(config),
          ),
        );
      } finally {
        malloc.free(config);
      }
    });
  }

  /// Runs the tunnel over a tun descriptor the platform created.
  ///
  /// Ownership of [tunFd] passes to the core, which closes it on disconnect.
  /// The caller must not close it, and must not hand the same descriptor in
  /// twice: two devices reading one queue each see half the packets, which
  /// presents as a tunnel that is up and loses most of its traffic.
  static Future<Map<String, dynamic>> connectFd(int tunFd, String configText) {
    return Isolate.run(() {
      final library = _open();
      final config = configText.toNativeUtf8();
      try {
        return _require(
          _consume(
            library,
            library.lookupFunction<_ConnectFdNative, _ConnectFd>(
              'caelo_connect_fd',
            )(tunFd, config),
          ),
        );
      } finally {
        malloc.free(config);
      }
    });
  }

  /// The sockets carrying tunnel traffic, for the platform to exclude from its
  /// own routing. Either may be -1 on a device without that address family.
  static Future<List<int>> socketFds() async {
    final result = await Isolate.run(() {
      final library = _open();
      return _require(
        _consume(
          library,
          library.lookupFunction<_StringNative, _StringNative>(
            'caelo_socket_fds',
          )(),
        ),
      );
    });

    return [result['v4'] as int? ?? -1, result['v6'] as int? ?? -1];
  }

  static Future<void> disconnectFd() {
    return Isolate.run(() {
      final library = _open();
      _consume(
        library,
        library.lookupFunction<_StringNative, _StringNative>(
          'caelo_disconnect_fd',
        )(),
      );
    });
  }
}
