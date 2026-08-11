import 'dart:convert';
import 'dart:math';

import 'app_storage.dart';
import 'subscription.dart';

/// Where subscriptions live between launches.
///
/// One JSON file, like the settings. It holds the links, what the person called
/// them, and the last node list each one served — so the app opens with
/// something to connect to rather than with a spinner and a network request.
///
/// The file contains private keys, because a node's configuration does. It is
/// restricted to its owner where the platform has a mode to set, and belongs in
/// the Keychain and in Keystore-backed storage on the platforms that have them,
/// exactly as `ConfigStore` says of the file it writes. Both are the same debt.
abstract final class SubscriptionStore {
  static const _fileName = 'subscriptions.json';

  static List<Subscription>? _cache;

  static Future<List<Subscription>> all() async {
    final cached = _cache;
    if (cached != null) return cached;

    final file = await AppStorage.file(_fileName);
    if (!await file.exists()) return _cache = const [];

    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! List) return _cache = const [];
      return _cache = decoded
          .whereType<Map<String, dynamic>>()
          .map(Subscription.fromJson)
          .where((subscription) => subscription.id.isNotEmpty)
          .toList();
    } on Object {
      // A corrupt file is not worth failing to start over, and the links are
      // recoverable by pasting them again. Losing them silently is bad; not
      // opening at all is worse, because then there is nothing to paste into.
      return _cache = const [];
    }
  }

  static Future<Subscription?> byId(String id) async {
    for (final subscription in await all()) {
      if (subscription.id == id) return subscription;
    }
    return null;
  }

  /// Adds a subscription. Returns the existing one if the link is already here,
  /// rather than a second copy of it: two entries pointing at one URL differ
  /// only in which of them is stale.
  static Future<Subscription> add(String url, {String name = ''}) async {
    final trimmed = url.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('a subscription needs a link');
    }
    final parsed = Uri.tryParse(trimmed);
    if (parsed == null || !parsed.hasScheme || !parsed.hasAuthority) {
      throw ArgumentError('$trimmed is not a link');
    }
    if (parsed.scheme != 'https' && parsed.scheme != 'http') {
      throw ArgumentError(
        'a subscription link is http or https, not ${parsed.scheme}',
      );
    }

    final existing = await all();
    for (final subscription in existing) {
      if (subscription.url == trimmed) return subscription;
    }

    final added = Subscription(id: _newId(), url: trimmed, name: name);
    await _write([...existing, added]);
    return added;
  }

  /// Replaces one subscription, matched by id.
  ///
  /// By id rather than by position, because a refresh running while somebody
  /// removes a different subscription would otherwise write its result over
  /// whichever entry happened to move into that slot.
  static Future<void> save(Subscription subscription) async {
    final all = await SubscriptionStore.all();
    final updated = [
      for (final existing in all)
        if (existing.id == subscription.id) subscription else existing,
    ];
    await _write(updated);
  }

  static Future<void> remove(String id) async {
    final remaining = (await all())
        .where((subscription) => subscription.id != id)
        .toList();
    await _write(remaining);
  }

  /// Moves a subscription in the list. The order here is the person's, not the
  /// server's: the server orders nodes, the person orders subscriptions.
  static Future<void> reorder(int from, int to) async {
    final all = [...await SubscriptionStore.all()];
    if (from < 0 || from >= all.length) return;
    final moved = all.removeAt(from);
    all.insert(to.clamp(0, all.length), moved);
    await _write(all);
  }

  static Future<void> _write(List<Subscription> subscriptions) async {
    _cache = subscriptions;
    final file = await AppStorage.file(_fileName);
    await file.writeAsString(
      jsonEncode(subscriptions.map((each) => each.toJson()).toList()),
      flush: true,
    );
    try {
      await AppStorage.restrict(file);
    } on Object {
      // Same trade ConfigStore makes: a file holding private keys that could
      // not be protected is deleted rather than left readable.
      await file.delete();
      _cache = null;
      rethrow;
    }
  }

  /// Only has to be unique within this file, and never leaves the device.
  static String _newId() {
    final random = Random.secure();
    final bytes = List<int>.generate(8, (_) => random.nextInt(256));
    return bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
  }

  /// Forgets what was read, so the next call goes back to the file. For tests
  /// and for anything that edits the file underneath us.
  static void forget() => _cache = null;
}
