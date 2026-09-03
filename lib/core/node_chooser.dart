import 'dart:async';

import 'config_store.dart';
import 'diagnostics.dart';
import 'ffi/core_library.dart';
import 'subscription.dart';
import 'subscription_fetcher.dart';

/// Why a node was not chosen.
class NoNodeWorked implements Exception {
  const NoNodeWorked(this.tried);

  /// How many candidates were tried. Zero means there were none — a different
  /// thing to say than "none of them answered", and the interface should be
  /// able to tell them apart.
  final int tried;

  @override
  String toString() => tried == 0
      ? 'there are no nodes to connect through'
      : 'none of the $tried nodes carried traffic';
}

/// A node that answered, and how long it took to say so.
///
/// The measurement is kept rather than only logged. It was taken to decide
/// whether the node works at all, but it is also the only latency figure that
/// means anything: measured from this device, on this network, through this
/// node. A number a server sends is a number measured from somewhere else.
class ChosenNode {
  const ChosenNode({required this.node, required this.latency});

  final SubscriptionNode node;

  /// How long the probe's request took, end to end through the tunnel. Not a
  /// ping: it includes the handshake and a real HTTPS exchange, which is what
  /// somebody actually waits for.
  final Duration latency;
}

/// Picks which node to connect through.
///
/// Works down the list a subscription served, in the order it served it, and
/// stops at the first node that actually carries traffic. The order is the
/// server's decision; the only decision made here is when to stop.
abstract final class NodeChooser {
  /// How long to give one node before moving on.
  ///
  /// Short, because this runs several times in a row and somebody is waiting.
  /// A node that needs longer than this on a good day is a node that will be
  /// unusable on a bad one.
  static const perNode = Duration(seconds: 8);

  /// What a probe fetches. Small, plain, and returns the address it saw, which
  /// is also the evidence the traffic left through the tunnel rather than
  /// around it.
  static const probeUrl = 'https://ifconfig.me/ip';

  /// Tries each candidate until one works.
  ///
  /// Each attempt runs on a userspace network stack inside this process: no
  /// interface is created, no route is changed, and nothing outside this
  /// process goes through it. That is what makes working down a list possible
  /// at all — connecting each candidate for real would raise and drop a system
  /// tunnel per candidate, and on iOS and Android that restarts the tunnel
  /// extension and drops every connection on the device, once per candidate.
  /// [probe] and [reissue] exist so the rule below can be tested without a
  /// network and without the core. They are written out rather than passed as
  /// tear-offs of differing shapes: `a ?? b` over two functions with no common
  /// type infers plain `Function`, the call becomes dynamic, and it compiles
  /// perfectly and throws on a device (#71).
  static Future<ChosenNode> choose({
    List<SubscriptionNode>? among,
    Duration perNode = perNode,
    Future<Map<String, dynamic>> Function(
      String endpoint, {
      String url,
      Duration timeout,
    })?
    probe,
    Future<bool> Function(SubscriptionNode node)? reissue,
  }) async {
    final askCore =
        probe ??
        (
          String endpoint, {
          String url = probeUrl,
          Duration timeout = const Duration(seconds: 8),
        }) => CoreLibrary.probe(endpoint, url: url, timeout: timeout);
    final askForReissue =
        reissue ?? (SubscriptionNode node) => SubscriptionFetcher.rotate(node);

    final candidates = among ?? await SubscriptionFetcher.candidates();
    if (candidates.isEmpty) throw const NoNodeWorked(0);

    final failed = <SubscriptionNode>[];

    for (final node in candidates) {
      final name = node.tag.isEmpty ? 'node ${node.position}' : node.tag;
      try {
        final result = await askCore(
          node.endpoint,
          url: probeUrl,
          timeout: perNode,
        );
        final elapsed = Duration(
          milliseconds: (result['elapsed_ms'] as num?)?.round() ?? 0,
        );
        Diagnostics.record(
          'probe: $name answered in ${elapsed.inMilliseconds}ms',
        );
        // Something worked, so the ones that did not are the nodes rather than
        // the network — which is the only evidence that justifies asking the
        // server to issue one again. A node can be listed and unusable: its
        // keys rotated underneath, its peer removed by hand, its server's
        // protocol upgraded past what this configuration says.
        //
        // One per pass, and never awaited: this is repair, and the person is
        // waiting to be connected. The server rate-limits it and answers 429,
        // which SubscriptionFetcher.rotate obeys rather than retries.
        if (failed.isNotEmpty) {
          unawaited(askForReissue(failed.first));
        }
        return ChosenNode(node: node, latency: elapsed);
      } on Object catch (error) {
        // Recorded and moved past. A node that does not answer is the ordinary
        // case this exists to handle, not a failure worth stopping for.
        Diagnostics.record('probe: $name did not answer', error: error);
        failed.add(node);
      }
    }

    // Every one of them failed, so nothing here is evidence about any node. A
    // device with no network cannot connect to anything, and a client that
    // answered by reissuing the whole list would burn through a subnet the
    // first time somebody walked into a lift.
    throw NoNodeWorked(candidates.length);
  }

  /// Chooses a node and makes it the one a connection will use.
  ///
  /// The chosen endpoint becomes the stored configuration, which is what every
  /// platform's tunnel already reads: the app has one connection at a time, so
  /// it has one configuration at a time, and the paths that carry it to a
  /// packet tunnel extension or to a privileged service carry text either way.
  ///
  /// Nothing is written unless a node worked. Replacing a configuration that
  /// connects with one that has just been shown not to would be the worst
  /// possible moment to lose it.
  static Future<ChosenNode> prepare({
    List<SubscriptionNode>? among,
    Duration perNode = perNode,
  }) async {
    final chosen = await choose(among: among, perNode: perNode);
    await ConfigStore.write(chosen.node.endpoint);
    return chosen;
  }
}
