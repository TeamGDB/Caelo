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

/// Which protocol carried the connection.
///
/// This exists to be shown in small text, not to be chosen from. Picking a
/// protocol is the core's job.
enum TunnelProtocol {
  amneziaWg('AmneziaWG'),
  vless('VLESS');

  const TunnelProtocol(this.label);
  final String label;
}

/// A snapshot of what the core is doing.
@immutable
class TunnelStatus {
  const TunnelStatus({
    required this.phase,
    this.node,
    this.protocol,
    this.pingMs,
  });

  const TunnelStatus.disconnected() : this(phase: TunnelPhase.disconnected);

  final TunnelPhase phase;

  /// Human-readable name of the node in use, once one has been chosen.
  final String? node;

  final TunnelProtocol? protocol;

  /// Round-trip time to [node], if it has been measured.
  final int? pingMs;

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

  Future<void> dispose();
}
