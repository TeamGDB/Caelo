import 'dart:async';

import 'package:flutter/widgets.dart';

import 'config_store.dart';
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
  });

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

  /// Whether picking this costs a round trip to the subscription.
  bool get needsKeys => nodeId == null && serverId != null;

  ServerOption withLatency(int latencyMs) => ServerOption(
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
  );
}

/// The server list Home consumes, independent of where its nodes are stored.
abstract interface class ServerCatalog {
  Future<List<ServerOption>> load();

  Future<int?> measureLatency(ServerOption server);
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
          if (!server.ready)
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
    this.activateNode = _activateNode,
    this.latencyRefreshInterval = const Duration(seconds: 5),
  });

  final ServerCatalog catalog;
  final Future<String?> Function() readSelected;
  final Future<void> Function(String) writeSelected;
  final Future<void> Function(String) activateConfiguration;

  /// Asks a subscription for keys on one of the servers it offers.
  final Future<Subscription?> Function(Subscription, String) grantServer;
  final Future<void> Function(String, String) activateNode;
  final Duration? latencyRefreshInterval;
  List<ServerOption> servers = const [];
  ServerOption? selected;
  int _loadGeneration = 0;
  Timer? _latencyRefreshTimer;

  Future<void> load() async {
    _latencyRefreshTimer?.cancel();
    final generation = ++_loadGeneration;
    final loaded = await catalog.load();
    final savedId = await readSelected();
    servers = loaded;
    selected = loaded.where((server) => server.id == savedId).firstOrNull;
    selected ??= loaded.firstOrNull;
    notifyListeners();
    unawaited(_measureLatencies(generation));
  }

  Future<void> _measureLatencies(int generation) async {
    for (final server in [...servers]) {
      if (generation != _loadGeneration) return;
      final latency = await catalog.measureLatency(server);
      if (generation != _loadGeneration || latency == null) continue;
      final measured = server.withLatency(latency);
      servers = [
        for (final current in servers)
          if (current.id == server.id) measured else current,
      ];
      if (selected?.id == server.id) selected = measured;
      notifyListeners();
    }
    if (generation != _loadGeneration) return;
    final interval = latencyRefreshInterval;
    if (interval != null) {
      _latencyRefreshTimer = Timer(
        interval,
        () => unawaited(_measureLatencies(generation)),
      );
    }
  }

  Future<void> select(ServerOption server) async {
    if (!servers.contains(server) || !server.available) return;

    // Ключей ещё нет — просим их и перечитываем список: узел появляется только
    // после того, как сервер его выдал.
    if (server.needsKeys) {
      final granted = await requestKeys(server);
      if (!granted) return;
      await load();
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

    final subscription = await SubscriptionStore.byId(subscriptionId);
    if (subscription == null) return false;

    return await grantServer(subscription, serverId) != null;
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

  @override
  void dispose() {
    _loadGeneration++;
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
