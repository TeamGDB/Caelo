import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

typedef _VersionNative = Pointer<Utf8> Function();
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

/// Binds the Go core's C interface.
///
/// This is scaffolding. The real contract between core and interface is gRPC
/// over a proto, which can push state changes; a C function that returns once
/// cannot represent a connection that comes and goes. What it is good for today
/// is proving the two halves link and load.
class CoreLibrary {
  CoreLibrary._(this._library);

  final DynamicLibrary _library;

  static CoreLibrary? _instance;

  static const _libraryName = 'libcaelo.dylib';

  /// Set `CAELO_CORE_DYLIB` to load a specific build — how you point a running
  /// app at a core you just rebuilt without reinstalling it.
  static const _overrideVariable = 'CAELO_CORE_DYLIB';

  static CoreLibrary open() {
    final existing = _instance;
    if (existing != null) return existing;

    final attempted = <String>[];
    Object? lastError;

    for (final candidate in _candidatePaths()) {
      attempted.add(candidate);
      try {
        final library = CoreLibrary._(DynamicLibrary.open(candidate));
        _instance = library;
        return library;
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

  CoreVersion version() {
    final version = _library.lookupFunction<_VersionNative, _VersionNative>(
      'caelo_version',
    );
    final decoded = _consume(version());

    return CoreVersion(
      core: decoded['core'] as String? ?? 'unknown',
      amneziaWg: decoded['amneziawg'] as String? ?? 'unknown',
    );
  }

  /// Reads a string the core allocated, then hands the memory back. Every
  /// string that crosses this boundary is owned by us and leaks if we forget.
  Map<String, dynamic> _consume(Pointer<Utf8> pointer) {
    if (pointer == nullptr) return const {};
    try {
      return jsonDecode(pointer.toDartString()) as Map<String, dynamic>;
    } finally {
      _library.lookupFunction<_FreeNative, _Free>('caelo_free')(pointer);
    }
  }
}
