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
  static Future<SubscriptionNode> choose({
    List<SubscriptionNode>? among,
    Duration perNode = perNode,
  }) async {
    final candidates = among ?? await SubscriptionFetcher.candidates();
    if (candidates.isEmpty) throw const NoNodeWorked(0);

    for (final node in candidates) {
      final name = node.tag.isEmpty ? 'node ${node.position}' : node.tag;
      try {
        final result = await CoreLibrary.probe(
          node.endpoint,
          url: probeUrl,
          timeout: perNode,
        );
        Diagnostics.record(
          'probe: $name answered in ${result['elapsed_ms']}ms',
        );
        return node;
      } on Object catch (error) {
        // Recorded and moved past. A node that does not answer is the ordinary
        // case this exists to handle, not a failure worth stopping for.
        Diagnostics.record('probe: $name did not answer', error: error);
      }
    }

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
  static Future<SubscriptionNode> prepare({
    List<SubscriptionNode>? among,
    Duration perNode = perNode,
  }) async {
    final chosen = await choose(among: among, perNode: perNode);
    await ConfigStore.write(chosen.endpoint);
    return chosen;
  }
}
