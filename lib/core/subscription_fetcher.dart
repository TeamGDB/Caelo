import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'build_info.dart';
import 'device_identity.dart';
import 'diagnostics.dart';
import 'subscription.dart';
import 'subscription_store.dart';

/// Raised when a subscription could not be refreshed.
///
/// Carrying the reason rather than a flag: "could not update" sends somebody
/// looking at their network when the server said 404, and at their account when
/// the server was unreachable.
class SubscriptionFailed implements Exception {
  const SubscriptionFailed(this.message, {this.gone = false});

  final String message;

  /// The server answered, and said this subscription is not one. Distinct from
  /// every other failure: retrying will not help and the interface should say
  /// so rather than show a spinner for ever.
  final bool gone;

  @override
  String toString() => message;
}

/// Fetches subscriptions and keeps what came back.
abstract final class SubscriptionFetcher {
  /// How long to wait. Generous: these are people on networks that are being
  /// interfered with, and a client that gives up in three seconds is a client
  /// that gives up.
  static const timeout = Duration(seconds: 30);

  /// The largest document worth reading.
  ///
  /// A subscription is a list of nodes. Anything past this is either a mistake
  /// or somebody feeding us a stream to see what happens, and reading it into
  /// memory to find out would be the mistake.
  static const maxBytes = 4 * 1024 * 1024;

  /// Refreshes one subscription and stores the result.
  ///
  /// On success the nodes, the usage and the interval are replaced and the
  /// error is cleared. On failure the previously cached nodes are kept and the
  /// reason is recorded beside them: both are true at once, and a client that
  /// threw away a working list because a refresh failed would be broken by its
  /// own maintenance.
  static Future<Subscription> refresh(
    Subscription subscription, {
    bool throwOnFailure = false,
  }) async {
    try {
      final fetched = await _fetch(subscription.url);
      // Спрашиваем версию после того, как забрали список: она описывает то, что
      // мы только что получили, и записывать её раньше значило бы запомнить
      // состояние, которого у нас нет.
      final seen = await look(subscription);

      final updated = subscription.copyWith(
        nodes: fetched.nodes,
        usage: fetched.usage.isEmpty ? subscription.usage : fetched.usage,
        updateInterval: fetched.updateInterval,
        lastFetched: DateTime.now(),
        clearError: true,
        // A pin to a node the server has withdrawn is a pin to nothing, and
        // silently connecting somewhere else while still showing the old choice
        // would be worse than forgetting it.
        clearPin:
            subscription.pinnedId != null &&
            !fetched.nodes.any((node) => node.id == subscription.pinnedId),
        stateVersion: seen.version,
        available: seen.servers,
      );

      await SubscriptionStore.save(updated);
      Diagnostics.record(
        'subscription refreshed: ${fetched.nodes.length} nodes',
      );
      return updated;
    } on SubscriptionFailed catch (error) {
      final kept = subscription.copyWith(lastError: error.message);
      await SubscriptionStore.save(kept);
      Diagnostics.record('subscription refresh failed', error: error);
      if (throwOnFailure) rethrow;
      return kept;
    }
  }

  /// Asks whether anything changed, without fetching the keys.
  ///
  /// Returns the server's opaque version, or null if it does not offer the
  /// state endpoint — which is most of them, and not a failure. The whole point
  /// is that this is cheap enough to ask often: the document carries the
  /// private key of every node, and downloading all of it to discover that
  /// nothing moved is what the interval exists to limit.
  static Future<({String? version, List<AvailableServer> servers})> look(
    Subscription subscription,
  ) async {
    final version = await peek(subscription, catalogue: _catalogue);
    return (version: version, servers: _catalogue.toList());
  }

  /// Filled by the last [peek]. A field rather than a return value because the
  /// version is what most callers want and the catalogue is the exception.
  static final List<AvailableServer> _catalogue = [];

  static Future<String?> peek(
    Subscription subscription, {
    List<AvailableServer>? catalogue,
  }) async {
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final url = '${subscription.url.replaceAll(RegExp(r'/+$'), '')}/state';
      final request = await client.getUrl(Uri.parse(url)).timeout(timeout);
      request.headers.set(HttpHeaders.userAgentHeader, 'Caelo/$appVersion');
      request.headers.set('X-Caelo-Device', await DeviceIdentity.get());
      final response = await request.close().timeout(timeout);

      if (response.statusCode != 200) {
        // 404 from a server that does not implement this, 409 from one that
        // has too many devices on the link. Neither is worth reporting here:
        // the caller falls back to fetching the document, which says the same
        // thing properly.
        await response.drain<void>();
        return null;
      }

      final decoded = jsonDecode(await _read(response));
      if (decoded is! Map) return null;

      if (catalogue != null) {
        catalogue
          ..clear()
          ..addAll(
            (decoded['servers'] as List? ?? const [])
                .whereType<Map<String, dynamic>>()
                .map(AvailableServer.fromJson)
                .where((server) => server.id.isNotEmpty),
          );
      }

      final version = decoded['version'];
      return version is String && version.isNotEmpty ? version : null;
    } on Object {
      // Any failure means "we do not know", and not knowing sends the caller
      // to the full fetch — which is exactly what it did before this existed.
      return null;
    } finally {
      client.close(force: true);
    }
  }

  /// Asks the server to issue a node again, because it does not connect.
  ///
  /// A node can stop working while the server still lists it: its keys were
  /// rotated underneath, the server's protocol was upgraded, its peer was
  /// removed by hand. The client knows something the server does not — that
  /// this configuration does not connect.
  ///
  /// Expensive on the far side: it provisions on a real server. Servers
  /// rate-limit it and answer 429, and that answer is obeyed rather than
  /// retried, because the failure being reacted to may not be the node's fault
  /// at all — a device with no network cannot connect to anything, and a client
  /// that answers by rotating every node burns through a subnet before the
  /// wifi comes back.
  ///
  /// Returns true if the server issued a new one.
  static Future<bool> rotate(SubscriptionNode node) async {
    // Nothing here may throw. NodeChooser calls it without awaiting, while a
    // person is waiting to be connected, so an exception would surface as an
    // unhandled asynchronous error somewhere else entirely — and the thing it
    // was trying to repair is not worth breaking the connection over.
    try {
      return await _rotate(node);
    } on Object catch (error) {
      Diagnostics.record('node reissue failed', error: error);
      return false;
    }
  }

  static Future<bool> _rotate(SubscriptionNode node) async {
    Subscription? owner;
    for (final subscription in await SubscriptionStore.all()) {
      if (subscription.nodes.any((candidate) => candidate.id == node.id)) {
        owner = subscription;
        break;
      }
    }
    if (owner == null) return false;

    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final base = owner.url.replaceAll(RegExp(r'/+$'), '');
      final url = '$base/nodes/${Uri.encodeComponent(node.id)}/rotate';
      final request = await client.postUrl(Uri.parse(url)).timeout(timeout);
      request.headers.set(HttpHeaders.userAgentHeader, 'Caelo/$appVersion');
      request.headers.set('X-Caelo-Device', await DeviceIdentity.get());
      final response = await request.close().timeout(timeout);
      await response.drain<void>();

      if (response.statusCode == 429) {
        Diagnostics.record('node reissue refused: asked too soon');
        return false;
      }
      if (response.statusCode != 200) {
        // 404 from a server that does not offer this, which is most of them.
        return false;
      }

      Diagnostics.record('node reissued by the server');
      await refresh(owner);
      return true;
    } on Object catch (error) {
      Diagnostics.record('node reissue failed', error: error);
      return false;
    } finally {
      client.close(force: true);
    }
  }

  /// Asks the server for keys on one of the servers it offers.
  ///
  /// The subscription hands out what somebody actually picked rather than
  /// everything it could: provisioning happens on a real server over SSH, and
  /// doing it for every server on a link is how one subscription ended up with
  /// twenty-eight configurations nobody used and a minute and a half of waiting
  /// on the first launch.
  ///
  /// Returns the refreshed subscription, with the new node in it.
  static Future<Subscription?> enable(
    Subscription subscription,
    String serverId,
  ) async {
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final base = subscription.url.replaceAll(RegExp(r'/+$'), '');
      final url = '$base/servers/${Uri.encodeComponent(serverId)}';
      // Longer than the rest: this provisions on a live server, which is
      // seconds rather than milliseconds, and giving up early would leave the
      // peer created and the client not knowing about it.
      final request = await client
          .postUrl(Uri.parse(url))
          .timeout(const Duration(seconds: 60));
      request.headers.set(HttpHeaders.userAgentHeader, 'Caelo/$appVersion');
      request.headers.set('X-Caelo-Device', await DeviceIdentity.get());
      final response = await request.close().timeout(
        const Duration(seconds: 60),
      );
      await response.drain<void>();

      if (response.statusCode != 200) {
        Diagnostics.record('server not granted: ${response.statusCode}');
        return null;
      }

      Diagnostics.record('server granted, refreshing the list');
      return await refresh(subscription);
    } on Object catch (error) {
      Diagnostics.record('asking for a server failed', error: error);
      return null;
    } finally {
      client.close(force: true);
    }
  }

  /// Refreshes every subscription the server has asked us to come back to.
  ///
  /// One at a time rather than together: several requests leaving at once from
  /// a connection that is already struggling is how a refresh turns into a
  /// timeout. There are rarely more than a handful.
  static Future<List<Subscription>> refreshDue({bool force = false}) async {
    final results = <Subscription>[];
    for (final subscription in await SubscriptionStore.all()) {
      if (force || subscription.isDue) {
        results.add(await refresh(subscription));
        continue;
      }

      // Не пришло время по расписанию — но список мог поменяться раньше, чем
      // сервер просил вернуться. Сервер, который умеет отвечать версией,
      // говорит об этом за несколько сотен байт, и ждать полсуток, зная, что
      // конфиг уже не тот, незачем.
      final known = subscription.stateVersion;
      if (known == null) {
        results.add(subscription);
        continue;
      }
      final now = await peek(subscription);
      if (now != null && now != known) {
        Diagnostics.record('subscription changed ahead of schedule');
        results.add(await refresh(subscription));
        continue;
      }
      results.add(subscription);
    }
    return results;
  }

  /// Every node from every subscription, each subscription's own order kept.
  ///
  /// The list is what connecting works down: try, and if nothing comes back,
  /// try the next. Nothing here re-sorts by anything measured — the order came
  /// from the server, and recomputing it would be overriding a decision we were
  /// told rather than making one.
  static Future<List<SubscriptionNode>> candidates() async {
    final nodes = <SubscriptionNode>[];
    for (final subscription in await SubscriptionStore.all()) {
      nodes.addAll(subscription.candidates);
    }
    return nodes;
  }

  static Future<_Fetched> _fetch(String url) async {
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final request = await client.getUrl(Uri.parse(url)).timeout(timeout);
      // Servers that vary their answer by client are the reason this header
      // exists, and docs/subscriptions.md promises what we send. It says which
      // client and which build and nothing else: a user agent goes to every
      // server, including one that is only pretending to be a subscription.
      request.headers.set(HttpHeaders.userAgentHeader, 'Caelo/$appVersion');
      // Which installation is asking. A subscription cannot hand the same keys
      // to a phone and a laptop: a WireGuard peer is identified by its public
      // key and the server remembers one address for it, so two devices on one
      // configuration take that peer from each other with every handshake and
      // the connection drops on both. A server that understands this header
      // keeps a set per device; one that does not ignores it and answers
      // exactly as before, which is why sending it is safe everywhere.
      request.headers.set('X-Caelo-Device', await DeviceIdentity.get());
      // Offered, not demanded. A server that understands it answers with the
      // richer document; one that does not answers with plain sing-box JSON,
      // and which arrived is decided by the response rather than by this.
      request.headers.set(
        HttpHeaders.acceptHeader,
        '$caeloDocumentType, application/json',
      );
      final response = await request.close().timeout(timeout);

      if (response.statusCode == 404 || response.statusCode == 403) {
        throw const SubscriptionFailed(
          'the server does not recognise this subscription',
          gone: true,
        );
      }
      if (response.statusCode >= 400) {
        throw SubscriptionFailed('the server answered ${response.statusCode}');
      }

      final body = await _read(response);

      final List<SubscriptionNode> nodes;
      try {
        nodes = readNodes(
          body,
          contentType: response.headers.contentType?.mimeType,
        );
      } on FormatException catch (error) {
        throw SubscriptionFailed(
          'the server sent something unreadable: ${error.message}',
        );
      }

      return _Fetched(
        nodes: nodes,
        usage: SubscriptionUsage.parse(
          response.headers.value('subscription-userinfo'),
        ),
        updateInterval: _interval(
          response.headers.value('profile-update-interval'),
        ),
      );
    } on SubscriptionFailed {
      rethrow;
    } on TimeoutException {
      throw const SubscriptionFailed('the server did not answer in time');
    } on SocketException catch (error) {
      throw SubscriptionFailed('could not reach the server: ${error.message}');
    } on HandshakeException {
      // Named separately because it is the one failure here that may be
      // somebody interfering rather than something broken.
      throw const SubscriptionFailed(
        'the server\'s certificate was not accepted',
      );
    } on HttpException {
      // HttpException often includes the request URI. A subscription URL is a
      // bearer credential and must not reach diagnostics through an error.
      throw const SubscriptionFailed(
        'the server response could not be completed',
      );
    } on Object {
      throw const SubscriptionFailed(
        'could not read the subscription response',
      );
    } finally {
      client.close(force: true);
    }
  }

  /// Reads the body, refusing one that will not stop.
  static Future<String> _read(HttpClientResponse response) async {
    final bytes = <int>[];
    await for (final chunk in response) {
      bytes.addAll(chunk);
      if (bytes.length > maxBytes) {
        throw const SubscriptionFailed('the server sent more than a node list');
      }
    }
    try {
      return utf8.decode(bytes);
    } on FormatException {
      throw const SubscriptionFailed(
        'the server sent something that is not text',
      );
    }
  }

  /// `profile-update-interval` is in hours.
  ///
  /// A server asking to be polled every few minutes is asking for something
  /// that costs its users battery on a connection they are paying for, so the
  /// shortest interval honoured is an hour. Nothing stops a person refreshing
  /// by hand whenever they like.
  static Duration? _interval(String? header) {
    final hours = int.tryParse(header?.trim() ?? '');
    if (hours == null || hours <= 0) return null;
    return Duration(hours: hours < 1 ? 1 : hours);
  }
}

class _Fetched {
  const _Fetched({
    required this.nodes,
    required this.usage,
    required this.updateInterval,
  });

  final List<SubscriptionNode> nodes;
  final SubscriptionUsage usage;
  final Duration? updateInterval;
}
