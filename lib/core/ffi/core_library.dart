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
typedef _ProbeNative =
    Pointer<Utf8> Function(Pointer<Utf8>, Pointer<Utf8>, Int32);
typedef _VerifyNative =
    Pointer<Utf8> Function(Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>);
typedef _Probe = Pointer<Utf8> Function(Pointer<Utf8>, Pointer<Utf8>, int);
typedef _SetFlagNative = Pointer<Utf8> Function(Int32);
typedef _SetFlag = Pointer<Utf8> Function(int);
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
  /// Each platform's loader has its own idea of what a shared library is
  /// called, and each finds it by name on a path it already searches: the APK's
  /// lib directory on Android, the runner's rpath on Linux, the executable's
  /// own directory on Windows. Which is why nothing here builds a path.
  ///
  /// The Apple platforms are absent because they have no file at all: there the
  /// core is a static archive linked into the executable. See [_open].
  static String get _libraryName =>
      Platform.isWindows ? 'caelo.dll' : 'libcaelo.so';

  /// Set `CAELO_CORE_DYLIB` to load a specific build — how you point a running
  /// app at a core you just rebuilt without reinstalling it.
  static const _overrideVariable = 'CAELO_CORE_DYLIB';

  static DynamicLibrary _open() {
    // On Apple platforms the core is linked into the binary rather than loaded
    // from one. Opening a path would fail even though the symbols are right
    // there, and the resulting error would send someone looking for a missing
    // file that was never supposed to exist.
    if (Platform.isIOS || Platform.isMacOS) return DynamicLibrary.process();

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

    // A development checkout where the core has been built but not yet
    // bundled — running from the project root rather than from an install.
    yield 'core/build/$_libraryName';
    yield '../core/build/$_libraryName';
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

  /// Answers whether one configuration carries traffic, without touching the
  /// machine's networking or a tunnel that is already up.
  ///
  /// This is how a list of candidates is worked down. Connecting each one for
  /// real to find out would raise and drop a system tunnel per candidate, and
  /// on iOS and Android that restarts the tunnel extension and drops every
  /// connection on the device each time round.
  ///
  /// It is also a stronger answer than a ping: a server can answer ICMP and
  /// still refuse the handshake, and an obfuscated endpoint is supposed to
  /// ignore anything that is not the right first packet.
  static Future<Map<String, dynamic>> probe(
    String configText, {
    String url = 'https://ifconfig.me/ip',
    Duration timeout = const Duration(seconds: 20),
  }) {
    final timeoutMs = timeout.inMilliseconds;
    return Isolate.run(() {
      final library = _open();
      final config = configText.toNativeUtf8();
      final target = url.toNativeUtf8();
      try {
        return _require(
          _consume(
            library,
            library.lookupFunction<_ProbeNative, _Probe>('caelo_probe')(
              config,
              target,
              timeoutMs,
            ),
          ),
        );
      } finally {
        malloc.free(config);
        malloc.free(target);
      }
    });
  }

  /// Measures a warm HTTPS round trip after first proving that the tunnel is
  /// usable. Unlike [probe]'s elapsed time, `latency_ms` excludes the initial
  /// WireGuard handshake and is the value intended for the server list.
  static Future<Map<String, dynamic>> measureLatency(
    String configText, {
    String url = 'https://ifconfig.me/ip',
    Duration timeout = const Duration(seconds: 20),
  }) {
    final timeoutMs = timeout.inMilliseconds;
    return Isolate.run(() {
      final library = _open();
      final config = configText.toNativeUtf8();
      final target = url.toNativeUtf8();
      try {
        return _require(
          _consume(
            library,
            library.lookupFunction<_ProbeNative, _Probe>(
              'caelo_measure_latency',
            )(config, target, timeoutMs),
          ),
        );
      } finally {
        malloc.free(config);
        malloc.free(target);
      }
    });
  }

  /// Whether a downloaded file was signed by one of the keys this build trusts.
  ///
  /// Throws [CoreFailure] when it was not, and the message deliberately does not
  /// say which way it failed: a wrong signature, an unknown key and a truncated
  /// download are the same event to somebody deciding whether to install, and
  /// distinguishing them helps whoever is trying combinations more than it helps
  /// anyone else.
  static Future<void> verifyRelease({
    required String path,
    required String signature,
    required List<String> trustedKeys,
  }) {
    final keysJson = jsonEncode(trustedKeys);
    return Isolate.run(() {
      final library = _open();
      final pathC = path.toNativeUtf8();
      final signatureC = signature.toNativeUtf8();
      final keysC = keysJson.toNativeUtf8();
      try {
        _require(
          _consume(
            library,
            library.lookupFunction<_VerifyNative, _VerifyNative>(
              'caelo_verify_release',
            )(pathC, signatureC, keysC),
          ),
        );
      } finally {
        malloc.free(pathC);
        malloc.free(signatureC);
        malloc.free(keysC);
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

  /// The core's recent history, oldest line first.
  ///
  /// Cheap: it reads a ring in memory. Key material never appears in it —
  /// redaction happens where each line is recorded, not here.
  static ({List<String> lines, bool verbose}) log() {
    final library = _open();
    final decoded = _consume(
      library,
      library.lookupFunction<_StringNative, _StringNative>('caelo_log')(),
    );

    return (
      lines: (decoded['lines'] as List?)?.cast<String>() ?? const <String>[],
      verbose: decoded['verbose'] == true,
    );
  }

  /// Turns the core's detailed logging on or off, including for a tunnel that
  /// is already up — which is the case that matters, because nobody reconnects
  /// to reproduce a problem they are having right now.
  static void setVerbose(bool on) {
    final library = _open();
    _consume(
      library,
      library.lookupFunction<_SetFlagNative, _SetFlag>('caelo_set_verbose')(
        on ? 1 : 0,
      ),
    );
  }

  static void clearLog() {
    final library = _open();
    _consume(
      library,
      library.lookupFunction<_StringNative, _StringNative>('caelo_clear_log')(),
    );
  }
}
