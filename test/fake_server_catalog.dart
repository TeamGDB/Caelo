import 'package:caelo/core/server_catalog.dart';

class FakeServerCatalog implements ServerCatalog {
  const FakeServerCatalog();

  static const servers = [
    ServerOption(
      id: 'test-helsinki',
      name: 'Helsinki',
      description: 'Primary test server',
      flag: '🇫🇮',
      latencyMs: 28,
    ),
    ServerOption(
      id: 'test-stockholm',
      name: 'Stockholm',
      description: 'Stable test server',
      flag: '🇸🇪',
      latencyMs: 41,
    ),
    ServerOption(
      id: 'test-frankfurt',
      name: 'Frankfurt',
      description: 'Testing server',
      flag: '🇩🇪',
      latencyMs: 67,
    ),
  ];

  @override
  Future<List<ServerOption>> load() async => servers;
}
