import 'package:flutter/widgets.dart';

import 'config_store.dart';
import 'settings_store.dart';
import 'subscription.dart';
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
  final bool available;
}

/// The server list Home consumes, independent of where its nodes are stored.
abstract interface class ServerCatalog {
  Future<List<ServerOption>> load();
}

class SubscriptionServerCatalog implements ServerCatalog {
  SubscriptionServerCatalog({
    Future<List<Subscription>> Function()? loadSubscriptions,
    Future<List<StoredConfig>> Function()? loadConfigurations,
  }) : _loadSubscriptions = loadSubscriptions ?? SubscriptionStore.all,
       _loadConfigurations = loadConfigurations ?? ConfigStore.list;

  final Future<List<Subscription>> Function() _loadSubscriptions;
  final Future<List<StoredConfig>> Function() _loadConfigurations;

  @override
  Future<List<ServerOption>> load() async {
    final configs = await _loadConfigurations();
    final subscriptions = await _loadSubscriptions();
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
}

class ServerSelectionController extends ChangeNotifier {
  ServerSelectionController(
    this.catalog, {
    this.readSelected = SettingsStore.selectedServerId,
    this.writeSelected = SettingsStore.setSelectedServerId,
    this.activateConfiguration = ConfigStore.select,
    this.activateNode = _activateNode,
  });

  final ServerCatalog catalog;
  final Future<String?> Function() readSelected;
  final Future<void> Function(String) writeSelected;
  final Future<void> Function(String) activateConfiguration;
  final Future<void> Function(String, String) activateNode;
  List<ServerOption> servers = const [];
  ServerOption? selected;

  Future<void> load() async {
    final loaded = await catalog.load();
    final savedId = await readSelected();
    servers = loaded;
    selected = loaded.where((server) => server.id == savedId).firstOrNull;
    selected ??= loaded.firstOrNull;
    notifyListeners();
  }

  Future<void> select(ServerOption server) async {
    if (!servers.contains(server) || !server.available) return;
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
