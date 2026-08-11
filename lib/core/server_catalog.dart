import 'package:flutter/widgets.dart';

import 'settings_store.dart';
import 'config_store.dart';

@immutable
class ServerOption {
  const ServerOption({
    required this.id,
    required this.name,
    required this.location,
    required this.flag,
    required this.badge,
    this.latencyMs,
    this.configId,
  });

  final String id;
  final String name;
  final String location;
  final String flag;
  final String badge;
  final int? latencyMs;
  final String? configId;
}

/// Subscription-owned server source. The backend implementation will replace
/// the mock without changing Home or its selection state.
abstract interface class ServerCatalog {
  Future<List<ServerOption>> load();
}

/// Temporary presentation data only. It contains no routable addresses,
/// credentials or tunnel configurations and never changes core tunnel state.
class MockServerCatalog implements ServerCatalog {
  const MockServerCatalog();

  static const servers = [
    ServerOption(
      id: 'demo-helsinki',
      name: 'Helsinki',
      location: 'Finland',
      flag: '🇫🇮',
      badge: 'Main',
      latencyMs: 28,
    ),
    ServerOption(
      id: 'demo-stockholm',
      name: 'Stockholm',
      location: 'Sweden',
      flag: '🇸🇪',
      badge: 'Stable',
      latencyMs: 41,
    ),
    ServerOption(
      id: 'demo-frankfurt',
      name: 'Frankfurt',
      location: 'Germany',
      flag: '🇩🇪',
      badge: 'Testing',
      latencyMs: 67,
    ),
  ];

  @override
  Future<List<ServerOption>> load() async => servers;
}

class DevelopmentServerCatalog implements ServerCatalog {
  const DevelopmentServerCatalog();

  @override
  Future<List<ServerOption>> load() async {
    final configs = await ConfigStore.list();
    return [
      ...MockServerCatalog.servers,
      for (final config in configs)
        ServerOption(
          id: 'user-${config.id}',
          name: config.name,
          location: 'Local configuration',
          flag: config.emoji,
          badge: 'Custom',
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
  });

  final ServerCatalog catalog;
  final Future<String?> Function() readSelected;
  final Future<void> Function(String) writeSelected;
  final Future<void> Function(String) activateConfiguration;
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
    if (!servers.contains(server)) return;
    selected = server;
    notifyListeners();
    if (server.configId case final id?) await activateConfiguration(id);
    await writeSelected(server.id);
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
