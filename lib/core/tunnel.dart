import 'package:flutter/foundation.dart';

/// Where the tunnel is in its lifecycle.
enum TunnelPhase {
  disconnected,
  connecting,
  connected,
  disconnecting,

  /// The attempt was abandoned. Distinct from [disconnected] because the user
  /// asked for a connection and did not get one, and the interface should say
  /// so rather than quietly returning to rest.
  failed;

  bool get isBusy =>
      this == TunnelPhase.connecting || this == TunnelPhase.disconnecting;
}

/// Why an attempt was abandoned, when the reason is something a person can act
/// on rather than a network to retry against.
///
/// An enum rather than a message because the clients that raise these have no
/// locale — they run below the interface — and a English sentence handed upwards
/// would appear untranslated in a Russian window.
enum TunnelFailure {
  /// The privileged service is older than this application. It is replaced by
  /// installing, so the remedy is to reinstall Caelo.
  serviceOlderThanApp,

  /// This application is older than the privileged service, which happens when
  /// the service was updated by a package manager and the application was not.
  appOlderThanService,

  /// There is nothing to connect through: no subscription node and no
  /// configuration of the person's own.
  noServers,

  /// Every server was tried, the subscription was refreshed and they were
  /// tried again, and none of them carried traffic. Most often the network
  /// itself, which is the thing worth suggesting.
  noServerReachable,

  /// The server the person picked by hand did not answer. Said separately
  /// because the remedy is different: pick another, or go back to automatic.
  chosenServerUnreachable,

  /// Nothing answered, and the subscription's server, asked again, said the
  /// link is no longer a subscription. A new invitation is the remedy, not the
  /// network (#106).
  subscriptionGone,

  /// The tunnel was up and its server stopped answering (#118). The
  /// controller reconnects elsewhere when it can.
  connectionLost,

  /// The server picked by hand was removed from the subscription (#128). The
  /// choice is back on automatic; the next press connects.
  chosenServerRemoved,

  /// Linux: this user is in the caelo group, and this login predates it. A new
  /// login is the remedy (#116).
  serviceNeedsRelogin,

  /// Linux: this user is not in the caelo group, so the service's socket
  /// refuses them (#116).
  serviceNeedsGroup,
}

/// Which protocol carried the connection.
///
/// This exists to be shown in small text, not to be chosen from. Picking a
/// protocol is the core's job.
enum TunnelProtocol {
  amneziaWg('AmneziaWG'),
  wireGuard('WireGuard'),
  vless('VLESS');

  const TunnelProtocol(this.label);
  final String label;

  /// Which protocol a reply from the core, the extension or the service
  /// names.
  ///
  /// The core says it in `protocol`, as a label (`AmneziaWG`) or a name
  /// (`vless`). A reply from before it did carries only `obfuscated`, which
  /// tells AmneziaWG from plain WireGuard and nothing else — reading its
  /// absence as VLESS was a guess that became wrong the day VLESS existed.
  static TunnelProtocol? fromCore(Map<String, dynamic>? reply) {
    if (reply == null) return null;
    final named = (reply['protocol'] as String?)?.toLowerCase();
    if (named != null && named.isNotEmpty) {
      for (final protocol in values) {
        if (protocol.label.toLowerCase() == named) return protocol;
      }
      return null;
    }
    return reply['obfuscated'] == true
        ? TunnelProtocol.amneziaWg
        : TunnelProtocol.wireGuard;
  }
}

/// A snapshot of what the core is doing.
@immutable
class TunnelStatus {
  const TunnelStatus({
    required this.phase,
    this.node,
    this.protocol,
    this.pingMs,
    this.failure,
  });

  const TunnelStatus.disconnected() : this(phase: TunnelPhase.disconnected);

  final TunnelPhase phase;

  /// Human-readable name of the node in use, once one has been chosen.
  final String? node;

  final TunnelProtocol? protocol;

  /// Round-trip time to [node], if it has been measured.
  final int? pingMs;

  /// Set only alongside [TunnelPhase.failed], and only when the cause is worth
  /// naming. Most failures are not: "the handshake did not complete" tells
  /// somebody nothing they can use, and the honest thing is to say the attempt
  /// failed and let them retry.
  final TunnelFailure? failure;

  bool get hasNode => node != null;
}

/// The boundary between the interface and the Go core.
///
/// Everything below this line — subscriptions, probing, node selection,
/// reconnection on network change — happens in the core. The app subscribes to
/// [status] and does not poll: the core tells us when something changed,
/// including changes we did not ask for, such as a switch to a different node
/// after the Wi-Fi network changed.
///
/// The real implementation will speak gRPC to `caelo-core`. Until that exists,
/// see `StubTunnelClient`.
/// The live round trip in a tunnel status reply, as the core, the extension
/// and the service all report it (#156), or null when there is none.
///
/// A reply from before the figure existed has no `latency_ms`; a tunnel that is
/// not up has nothing to say whatever the reply carries; and anything that is
/// not a positive whole number of milliseconds is not a figure.
int? liveLatencyIn(Object? status) {
  if (status is! Map || status['up'] != true) return null;
  final latency = status['latency_ms'];
  if (latency is! num || !latency.isFinite) return null;
  final ms = latency.round();
  return ms > 0 ? ms : null;
}

abstract interface class TunnelClient {
  /// What the core is doing right now.
  ///
  /// Kept separate from [changes] on purpose. A stream that replays its last
  /// value to each new subscriber has to do so asynchronously, which opens a
  /// window where a listener has attached but does not yet know the state, and
  /// where anything emitted in that window is lost. Reading the current value
  /// directly and subscribing to changes only closes that window.
  TunnelStatus get current;

  /// Subsequent state changes, including ones nobody asked for — a node
  /// switched after the Wi-Fi network changed, a tunnel dropped on its own.
  Stream<TunnelStatus> get changes;

  /// Whether "connected" means the whole machine or only this process.
  ///
  /// The interface has to say which, and it can only know by asking. A tunnel
  /// that carries one process while the screen implies it carries everything is
  /// the most harmful thing this product could get wrong.
  bool get coversWholeMachine;

  /// Bring the tunnel up. Which node and protocol get used is not our decision.
  Future<void> connect();

  Future<void> disconnect();

  /// Abandon the current node and pick a different one. This is the escape
  /// hatch for "it says connected but nothing loads".
  Future<void> reconnectDifferently();

  /// The round trip to the server right now, as the tunnel measures it from
  /// the traffic it carries (#156).
  ///
  /// Null when there is no figure: nothing is up, no connection has crossed
  /// the tunnel yet, or the core or service is from before this was reported.
  /// Asked for every couple of seconds while the app is in front, so it must
  /// be cheap and must not log.
  Future<int?> latency();

  Future<void> dispose();
}
