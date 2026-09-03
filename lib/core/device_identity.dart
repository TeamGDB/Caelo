import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'app_storage.dart';

/// What this installation calls itself when it asks a subscription for nodes.
///
/// A subscription cannot hand the same configuration to a phone and a laptop.
/// A WireGuard peer is identified by its public key and the server remembers
/// one endpoint address for it, so two devices carrying the same keys take that
/// peer from each other with every handshake: the connection drops on both, by
/// turns, and it reads as the internet failing rather than as a conflict. A
/// server that knows which device is asking can keep a separate set for each.
///
/// Random, generated once, stored. Deliberately not derived from anything about
/// the machine: an identifier built from hardware is both less stable — it
/// moves when the OS decides to rotate what it exposes — and more identifying
/// than this job needs. What goes to the server should say "the same client as
/// last time" and nothing else about who or what is asking.
abstract final class DeviceIdentity {
  static const _fileName = 'device.json';

  static String? _cache;

  /// The identifier, made on first use and unchanged afterwards.
  static Future<String> get() async {
    final cached = _cache;
    if (cached != null) return cached;

    // Nothing below may throw. This is called while building the headers of a
    // subscription request, and an identifier that cannot be read is not a
    // reason to fail the refresh — the server treats a missing header as "an
    // older client" and answers exactly as it always did. Losing the whole
    // subscription because a small file went bad would be the wrong trade by a
    // wide margin.
    File? file;
    try {
      file = await AppStorage.file(_fileName);
      if (await file.exists()) {
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is Map && decoded['id'] is String) {
          final stored = decoded['id'] as String;
          if (stored.isNotEmpty) return _cache = stored;
        }
      }
    } on Object {
      // Unreadable is the same as absent: a new identifier costs one extra set
      // of configurations on the server, and no storage at all costs nothing
      // but a device that is forgotten between launches.
    }

    final made = _generate();
    _cache = made;
    try {
      await file?.writeAsString(jsonEncode({'id': made}));
    } on Object {
      // Kept in memory even if it could not be written. A run that cannot
      // persist should still be one device rather than a new one per request.
    }
    return made;
  }

  /// Forgets the identifier, so the next request looks like a new device.
  ///
  /// Exists for the person who has given their link to somebody else and wants
  /// their own copy to stop sharing a set of keys with it.
  static Future<void> reset() async {
    _cache = null;
    try {
      final file = await AppStorage.file(_fileName);
      if (await file.exists()) await file.delete();
    } on Object {
      // Forgetting what was never stored is already done.
    }
  }

  static String _generate() {
    // Random.secure rather than Random: this is not a secret, but it is a
    // long-lived identifier, and one that a server could predict would let it
    // tell two installations apart before either had spoken.
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }
}
