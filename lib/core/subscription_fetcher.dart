import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'build_info.dart';
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
  static Future<Subscription> refresh(Subscription subscription) async {
    try {
      final fetched = await _fetch(subscription.url);

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
      return kept;
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
      if (!force && !subscription.isDue) {
        results.add(subscription);
        continue;
      }
      results.add(await refresh(subscription));
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
    } on Object catch (error) {
      throw SubscriptionFailed('$error');
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
