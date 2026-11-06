import 'dart:async';

import 'package:flutter/widgets.dart';

import 'config_store.dart';
import 'diagnostics.dart';
import 'tunnel.dart';
import 'tunnel_controller.dart';
import 'ffi/core_library.dart';
import 'node_chooser.dart';
import 'settings_store.dart';
import 'subscription.dart';
import 'subscription_fetcher.dart';
import 'subscription_store.dart';

@immutable
class ServerOption {
  const ServerOption({
    required this.id,
    required this.name,
    required this.description,
    required this.flag,
    this.latencyMs,
    this.configId,
    this.subscriptionId,
    this.nodeId,
    this.serverId,
    this.available = true,
    this.automatic = false,
    this.unreachable = false,
  });

  /// The entry that stands for "pick one that works". Not a server: it has no
  /// configuration, and its name and description are the interface's to say.
  const ServerOption.automatic()
    : id = automaticId,
      name = '',
      description = '',
      flag = '⚡️',
      latencyMs = null,
      configId = null,
      subscriptionId = null,
      nodeId = null,
      serverId = null,
      available = true,
      automatic = true,
      unreachable = false;

  static const automaticId = 'auto';

  final String id;
  final String name;
  final String description;
  final String flag;
  final int? latencyMs;
  final String? configId;
  final String? subscriptionId;
  final String? nodeId;

  /// Set when the subscription offers this server but has no keys for it yet.
  /// Choosing it asks for them; until then there is nothing to connect with and
  /// nothing to measure.
  final String? serverId;

  final bool available;

  /// Whether this is the automatic entry rather than a server.
  final bool automatic;

  /// Measured, and nothing came back. A result, as much as a latency is.
  final bool unreachable;

  /// Whether the last measurement reached a verdict either way.
  bool get measured => latencyMs != null || unreachable;

  /// Whether this can be dialled as it stands.
  bool get connectable =>
      !automatic &&
      available &&
      !needsKeys &&
      (configId != null || nodeId != null);

  /// Whether picking this costs a round trip to the subscription.
  bool get needsKeys => nodeId == null && serverId != null;

  ServerOption withLatency(int latencyMs) => _measured(latencyMs, false);

  ServerOption withUnreachable() => _measured(null, true);

  ServerOption _measured(int? latencyMs, bool unreachable) => ServerOption(
    id: id,
    name: name,
    description: description,
    flag: flag,
    latencyMs: latencyMs,
    configId: configId,
    subscriptionId: subscriptionId,
    nodeId: nodeId,
    serverId: serverId,
    available: available,
    automatic: automatic,
    unreachable: unreachable,
  );
}

/// The server list Home consumes, independent of where its nodes are stored.
abstract interface class ServerCatalog {
  Future<List<ServerOption>> load();

  /// A latency through the server, or null if it carried nothing.
  Future<int?> measureLatency(ServerOption server);

  /// Makes [server] the configuration the tunnel will dial, without pinning
  /// it and without adding anything to the person's own configurations.
  Future<void> activate(ServerOption server);
}

class SubscriptionServerCatalog implements ServerCatalog {
  SubscriptionServerCatalog({
    Future<List<Subscription>> Function()? loadSubscriptions,
    Future<List<StoredConfig>> Function()? loadConfigurations,
    Future<Map<String, dynamic>> Function(String)? probeConfiguration,
  }) : _loadSubscriptions = loadSubscriptions ?? SubscriptionStore.all,
       _loadConfigurations = loadConfigurations ?? ConfigStore.list,
       _probeConfiguration = probeConfiguration ?? _probe;

  final Future<List<Subscription>> Function() _loadSubscriptions;
  final Future<List<StoredConfig>> Function() _loadConfigurations;
  final Future<Map<String, dynamic>> Function(String) _probeConfiguration;
  final Map<String, String> _subscriptionEndpoints = {};

  @override
  Future<List<ServerOption>> load() async {
    final configs = await _loadConfigurations();
    final subscriptions = await _loadSubscriptions();
    _subscriptionEndpoints
      ..clear()
      ..addEntries(
        subscriptions.expand(
          (subscription) => subscription.nodes.map(
            (node) =>
                MapEntry('node:${subscription.id}:${node.id}', node.endpoint),
          ),
        ),
      );
    return [
      for (final subscription in subscriptions)
        for (final node in subscription.nodes)
          ServerOption(
            id: 'node:${subscription.id}:${node.id}',
            name: node.tag.trim().isEmpty
                ? 'Server ${node.position + 1}'
                : node.tag.trim(),
            description: node.description,
            flag: node.flag.isEmpty ? '🌐' : node.flag,
            subscriptionId: subscription.id,
            nodeId: node.id,
            available: !node.maintenance,
          ),
      // Серверы, которые подписка может выдать, но ещё не выдала. Ключей у них
      // нет, поэтому и узла нет: он появится, когда его выберут.
      for (final subscription in subscriptions)
        for (final server in subscription.available)
          if (!server.ready &&
              !SubscriptionFetcher.refused.contains(
                '${subscription.id}:${server.id}',
              ))
            ServerOption(
              id: 'offer:${subscription.id}:${server.id}',
              name: server.name,
              description: server.description,
              flag: server.flag.isEmpty ? '🌐' : server.flag,
              subscriptionId: subscription.id,
              serverId: server.id,
            ),
      for (final config in configs)
        ServerOption(
          id: 'user-${config.id}',
          name: config.name,
          description: config.description,
          flag: config.emoji,
          configId: config.id,
        ),
    ];
  }

  @override
  Future<int?> measureLatency(ServerOption server) async {
    final configId = server.configId;
    final endpoint = configId != null
        ? await ConfigStore.readById(configId)
        : _subscriptionEndpoints[server.id];
    if (endpoint == null || endpoint.trim().isEmpty || !server.available) {
      return null;
    }
    try {
      final result = await _probeConfiguration(endpoint);
      return (result['latency_ms'] as num?)?.round();
    } on Object {
      return null;
    }
  }

  @override
  Future<void> activate(ServerOption server) async {
    if (server.configId case final id?) {
      await ConfigStore.select(id);
      return;
    }
    final endpoint = _subscriptionEndpoints[server.id];
    if (endpoint == null) {
      throw StateError('the server has no configuration to activate');
    }
    await ConfigStore.activateSubscriptionNode(endpoint);
  }

  static Future<Map<String, dynamic>> _probe(String configuration) =>
      CoreLibrary.measureLatency(
        configuration,
        url: NodeChooser.probeUrl,
        timeout: NodeChooser.perNode,
      );
}

class ServerSelectionController extends ChangeNotifier {
  ServerSelectionController(
    this.catalog, {
    this.readSelected = SettingsStore.selectedServerId,
    this.writeSelected = SettingsStore.setSelectedServerId,
    this.activateConfiguration = ConfigStore.select,
    this.grantServer = SubscriptionFetcher.enable,
    this.readSubscription = SubscriptionStore.byId,
    this.activateNode = _activateNode,
    this.refreshSubscriptions = _refreshSubscriptions,
    this.latencyRefreshInterval = const Duration(minutes: 5),
    this.probeConcurrency = 4,
  });

  final ServerCatalog catalog;
  final Future<String?> Function() readSelected;
  final Future<void> Function(String) writeSelected;
  final Future<void> Function(String) activateConfiguration;

  /// Asks a subscription for keys on one of the servers it offers.
  final Future<Subscription?> Function(Subscription, String) grantServer;

  /// Reads a stored subscription. A seam so the picker can be driven without
  /// storage, which is what a test has instead of a filesystem.
  final Future<Subscription?> Function(String) readSubscription;
  final Future<void> Function(String, String) activateNode;

  /// Fetches every subscription again, regardless of schedule. Used once per
  /// connection, when nothing answered: the likeliest cause after "no
  /// network" is keys that were rotated on the server since the last fetch.
  ///
  /// Answers whether every subscription was refused by its server as unknown.
  final Future<bool> Function() refreshSubscriptions;

  /// How long to wait between re-measuring the list. Long: each measurement is
  /// a real handshake with every server, which costs battery and tells each of
  /// them the app is open.
  final Duration? latencyRefreshInterval;

  /// How many servers are probed at once when choosing automatically.
  final int probeConcurrency;

  /// The automatic entry first, then every server.
  List<ServerOption> servers = const [];

  /// What the person chose: a server, or the automatic entry.
  ServerOption? selected;

  /// The server the last connection was actually made through. Differs from
  /// [selected] when that is the automatic entry.
  ServerOption? active;

  /// The server being prepared, if one is.
  ///
  /// Asking a subscription for keys takes seconds -- it provisions on a real
  /// server over SSH. Without somewhere to say so, the list went on showing the
  /// previous choice for all of it, and the obvious thing to do with a list
  /// that has not reacted is to tap something else, which connected through
  /// whatever was tapped second.
  ServerOption? preparing;

  /// Whether a choice is waiting on the subscription.
  bool get isPreparing => preparing != null;

  /// Called when a reload no longer has the server the last connection went
  /// through: the subscription removed it (#111). The tunnel is still on it,
  /// and the peer is about to disappear from under it.
  void Function(ServerOption removed)? onActiveRemoved;

  /// Whether the automatic entry is the choice.
  bool get isAutomatic => selected?.automatic ?? true;

  int _loadGeneration = 0;
  int _measureGeneration = 0;
  Timer? _latencyRefreshTimer;
  bool _tunnelActive = false;

  /// Told by the app whenever the tunnel goes up or down.
  ///
  /// Measuring while connected is not only wasted: probing the connected
  /// node is a second device with the same key, and the server hands the
  /// session to whichever handshook last — the live tunnel goes deaf until it
  /// handshakes again (#102).
  set tunnelActive(bool active) {
    if (active == _tunnelActive) return;
    _tunnelActive = active;
    _measureGeneration++;
    _latencyRefreshTimer?.cancel();
    if (!active) _scheduleMeasurement(const Duration(seconds: 2));
  }

  bool get tunnelActive => _tunnelActive;

  Future<void> load() async {
    final generation = ++_loadGeneration;
    final loaded = await catalog.load();
    final savedId = await readSelected();
    if (generation != _loadGeneration) return;
    // What was measured survives a reload: the list is rebuilt from storage
    // every time keys arrive, and wiping the column each time would flicker.
    final previous = {for (final server in servers) server.id: server};
    ServerOption carry(ServerOption server) {
      final before = previous[server.id];
      if (before == null || server.latencyMs != null) return server;
      if (before.latencyMs case final latency?) {
        return server.withLatency(latency);
      }
      return before.unreachable ? server.withUnreachable() : server;
    }

    servers = [
      if (loaded.isNotEmpty) const ServerOption.automatic(),
      ...loaded.map(carry),
    ];
    selected =
        servers.where((server) => server.id == savedId).firstOrNull ??
        servers.firstOrNull;
    final wasActive = active;
    active = wasActive == null
        ? null
        : servers.where((server) => server.id == wasActive.id).firstOrNull;
    notifyListeners();
    if (wasActive != null && active == null) {
      Diagnostics.record('the server in use was removed: ${wasActive.name}');
      onActiveRemoved?.call(wasActive);
    }
    _measureGeneration++;
    _latencyRefreshTimer?.cancel();
    if (!_tunnelActive) unawaited(_measureLatencies(_measureGeneration));
  }

  void _scheduleMeasurement(Duration after) {
    _latencyRefreshTimer?.cancel();
    final generation = _measureGeneration;
    _latencyRefreshTimer = Timer(after, () {
      if (generation == _measureGeneration && !_tunnelActive) {
        unawaited(_measureLatencies(generation));
      }
    });
  }

  Future<void> _measureLatencies(int generation) async {
    for (final server in [...servers]) {
      if (generation != _measureGeneration || _tunnelActive) return;
      if (!server.connectable) continue;
      final latency = await catalog.measureLatency(server);
      if (generation != _measureGeneration) continue;
      Diagnostics.record(
        latency == null
            ? 'measure: ${server.name} did not answer'
            : 'measure: ${server.name} ${latency}ms',
      );
      if (latency == null) {
        _recordUnreachable(server.id);
      } else {
        _recordLatency(server.id, latency);
      }
    }
    if (generation != _measureGeneration) return;
    final interval = latencyRefreshInterval;
    if (interval != null) _scheduleMeasurement(interval);
  }

  void _recordUnreachable(String id) {
    servers = [
      for (final current in servers)
        if (current.id == id) current.withUnreachable() else current,
    ];
    if (selected?.id == id) selected = selected!.withUnreachable();
    notifyListeners();
  }

  void _recordLatency(String id, int latency) {
    ServerOption? measured;
    servers = [
      for (final current in servers)
        if (current.id == id)
          measured = current.withLatency(latency)
        else
          current,
    ];
    if (measured == null) return;
    if (selected?.id == id) selected = measured;
    if (active?.id == id) active = measured;
    notifyListeners();
  }

  Future<void> select(ServerOption server) async {
    if (!servers.contains(server) || !server.available) return;

    // Ключей ещё нет — просим их и перечитываем список: узел появляется только
    // после того, как сервер его выдал.
    if (server.needsKeys) {
      // Один запрос за раз. Пока идёт выдача, второе нажатие означало бы второй
      // peer на другом сервере — и подключение к тому, что нажали позже, а не к
      // тому, что выбрали.
      if (isPreparing) return;

      // Отмечаем выбранным сразу: человек нажал, и список обязан это показать,
      // не дожидаясь чужого сервера.
      preparing = server;
      notifyListeners();
      try {
        final granted = await requestKeys(server);
        if (!granted) return;
        await load();
      } finally {
        preparing = null;
        notifyListeners();
      }
      final now = servers.firstWhere(
        (candidate) =>
            candidate.subscriptionId == server.subscriptionId &&
            candidate.name == server.name &&
            candidate.nodeId != null,
        orElse: () => server,
      );
      if (now.nodeId == null) return;
      return select(now);
    }

    if (server.configId case final id?) {
      await activateConfiguration(id);
    } else if ((server.subscriptionId, server.nodeId) case (
      final subscriptionId?,
      final nodeId?,
    )) {
      await activateNode(subscriptionId, nodeId);
    }
    await writeSelected(server.id);
    selected = server;
    notifyListeners();
  }

  /// Decides what the next connection goes through and makes it the active
  /// configuration. The [TunnelController] calls this before every attempt.
  ///
  /// A server picked by hand is used as it is: the person chose it, and
  /// quietly connecting somewhere else would make the list a lie. The tunnel
  /// itself proves whether it answers.
  ///
  /// Automatic works down the list in the order it is shown — the
  /// subscription's order, then the person's own configurations — probing
  /// several at once on a userspace stack, and takes the first in that order
  /// that carried a real request. If none did, subscriptions are fetched again
  /// and the list is tried once more before giving up.
  Future<PreparedConnection> prepareConnection(
    Set<String> tried,
    bool Function() cancelled,
  ) async {
    final choice = selected;
    if (choice != null && !choice.automatic) {
      if (tried.contains(choice.id)) {
        return const PreparedConnection.failed(
          TunnelFailure.chosenServerUnreachable,
        );
      }
      if (!choice.connectable) {
        return const PreparedConnection.failed(
          TunnelFailure.chosenServerUnreachable,
        );
      }
      await catalog.activate(choice);
      active = choice;
      notifyListeners();
      return PreparedConnection.ready(choice.id, latencyMs: choice.latencyMs);
    }

    var found = await _firstWorking(tried, cancelled);
    if (cancelled()) return const PreparedConnection.cancelled();
    var gone = false;

    if (found == null && tried.isEmpty) {
      // Keys may have been rotated since the last fetch, or a subscription
      // whose cache was empty may have servers now.
      gone = await _refreshAndReload();
      if (cancelled()) return const PreparedConnection.cancelled();
      found = await _firstWorking(tried, cancelled);
      if (cancelled()) return const PreparedConnection.cancelled();
    }

    // Nothing with keys answered. A subscription that hands out keys on demand
    // may still have servers that work; ask for a few (#107).
    if (found == null && !gone) {
      found = await _provisionUntilWorking(cancelled);
      if (cancelled()) return const PreparedConnection.cancelled();
    }

    if (found == null) {
      final anything = servers.any(
        (server) => server.connectable || server.needsKeys,
      );
      return PreparedConnection.failed(
        gone
            ? TunnelFailure.subscriptionGone
            : anything
            ? TunnelFailure.noServerReachable
            : TunnelFailure.noServers,
      );
    }

    final (server, latency) = found;
    await catalog.activate(server);
    _recordLatency(server.id, latency);
    active =
        servers.where((each) => each.id == server.id).firstOrNull ?? server;
    notifyListeners();
    return PreparedConnection.ready(
      server.id,
      retryable: true,
      latencyMs: latency,
    );
  }

  /// True when every subscription was just refused as unknown.
  Future<bool> _refreshAndReload() async {
    var gone = false;
    try {
      gone = await refreshSubscriptions();
    } on Object catch (error) {
      Diagnostics.record(
        'subscription refresh before retry failed',
        error: error,
      );
    }
    await load();
    return gone;
  }

  /// How many offered servers one connection may ask keys for.
  static const maxProvisionPerConnection = 3;

  /// Asks for keys on offered servers, in list order, one at a time, and
  /// returns the first new node that carries traffic.
  ///
  /// One at a time and few: each request provisions a peer on a real server,
  /// and a phone on a network that blocks everything would otherwise ask for
  /// keys on every server the link offers.
  Future<(ServerOption, int)?> _provisionUntilWorking(
    bool Function() cancelled,
  ) async {
    final offers = servers
        .where((server) => server.needsKeys && server.available)
        .take(maxProvisionPerConnection)
        .toList();
    for (final offer in offers) {
      if (cancelled()) return null;
      preparing = offer;
      notifyListeners();
      try {
        Diagnostics.record('asking for keys on ${offer.name}');
        if (!await requestKeys(offer)) continue;
        await load();
        if (cancelled()) return null;
        final node = servers
            .where(
              (candidate) =>
                  candidate.subscriptionId == offer.subscriptionId &&
                  candidate.name == offer.name &&
                  candidate.connectable,
            )
            .firstOrNull;
        if (node == null) continue;
        int? latency;
        try {
          latency = await catalog.measureLatency(node);
        } on Object {
          latency = null;
        }
        if (latency != null) return (node, latency);
      } on Object catch (error) {
        Diagnostics.record('asking for keys failed', error: error);
      } finally {
        preparing = null;
        notifyListeners();
      }
    }
    return null;
  }

  /// The first candidate, in list order, that carried traffic.
  ///
  /// Probes run [probeConcurrency] at a time, but the answer respects order:
  /// a later server answering first does not win over an earlier one that is
  /// still being asked. Order is the subscription's decision.
  Future<(ServerOption, int)?> _firstWorking(
    Set<String> tried,
    bool Function() cancelled,
  ) async {
    final candidates = servers
        .where((server) => server.connectable && !tried.contains(server.id))
        .toList();
    if (candidates.isEmpty) return null;

    var finished = false;
    bool stop() => finished || cancelled();
    final results = [for (final _ in candidates) Completer<int?>()];
    var next = 0;

    Future<void> worker() async {
      while (next < candidates.length) {
        final index = next++;
        if (stop()) {
          results[index].complete(null);
          continue;
        }
        int? latency;
        try {
          latency = await catalog.measureLatency(candidates[index]);
        } on Object {
          latency = null;
        }
        final name = candidates[index].name;
        Diagnostics.record(
          latency == null
              ? 'probe: $name did not answer'
              : 'probe: $name answered in ${latency}ms',
        );
        results[index].complete(latency);
      }
    }

    final workers = probeConcurrency.clamp(1, candidates.length);
    for (var i = 0; i < workers; i++) {
      unawaited(worker());
    }

    try {
      for (var index = 0; index < candidates.length; index++) {
        final latency = await results[index].future;
        if (cancelled()) return null;
        if (latency != null) return (candidates[index], latency);
      }
      return null;
    } finally {
      finished = true;
    }
  }

  /// Asks the subscription for keys on a server it offers.
  ///
  /// Separate and injectable so the picker can be driven in a test without a
  /// network, and written out rather than passed as a tear-off: `a ?? b` over
  /// two functions with no common type infers plain Function and goes dynamic,
  /// which compiles and then throws on a device (#71).
  Future<bool> requestKeys(ServerOption server) async {
    final subscriptionId = server.subscriptionId;
    final serverId = server.serverId;
    if (subscriptionId == null || serverId == null) return false;

    final subscription = await readSubscription(subscriptionId);
    if (subscription == null) return false;

    return await grantServer(subscription, serverId) != null;
  }

  /// Forgets everything held in memory. For when the account is forgotten.
  void clear() {
    _loadGeneration++;
    _measureGeneration++;
    _latencyRefreshTimer?.cancel();
    servers = const [];
    selected = null;
    active = null;
    preparing = null;
    notifyListeners();
  }

  static Future<void> _activateNode(
    String subscriptionId,
    String nodeId,
  ) async {
    final subscription = await SubscriptionStore.byId(subscriptionId);
    if (subscription == null) return;
    final node = subscription.nodes
        .where((candidate) => candidate.id == nodeId)
        .firstOrNull;
    if (node == null || node.maintenance) return;
    await SubscriptionStore.save(subscription.copyWith(pinnedId: node.id));
    await ConfigStore.activateSubscriptionNode(node.endpoint);
  }

  static Future<bool> _refreshSubscriptions() async {
    final refreshed = await SubscriptionFetcher.refreshDue(force: true);
    return refreshed.isNotEmpty &&
        refreshed.every((subscription) => subscription.isGone);
  }

  @override
  void dispose() {
    _loadGeneration++;
    _measureGeneration++;
    _latencyRefreshTimer?.cancel();
    super.dispose();
  }
}

class ServerSelectionScope
    extends InheritedNotifier<ServerSelectionController> {
  const ServerSelectionScope({
    required ServerSelectionController controller,
    required super.child,
    super.key,
  }) : super(notifier: controller);

  static ServerSelectionController of(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<ServerSelectionScope>()!
      .notifier!;
}
