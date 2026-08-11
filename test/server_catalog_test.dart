import 'package:caelo/core/server_catalog.dart';
import 'package:caelo/core/subscription.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_server_catalog.dart';

class _MeasuringCatalog implements ServerCatalog {
  static const server = ServerOption(
    id: 'user-office',
    name: 'Office',
    description: 'Work network',
    flag: '🏢',
    configId: 'office',
  );

  @override
  Future<List<ServerOption>> load() async => const [server];

  @override
  Future<int?> measureLatency(ServerOption server) async => 73;
}

void main() {
  test(
    'restores and persists selection without coupling to the catalog',
    () async {
      String? saved = 'test-stockholm';
      final controller = ServerSelectionController(
        const FakeServerCatalog(),
        readSelected: () async => saved,
        writeSelected: (id) async => saved = id,
      );
      addTearDown(controller.dispose);

      await controller.load();
      expect(controller.selected?.name, 'Stockholm');

      await controller.select(FakeServerCatalog.servers.last);
      expect(controller.selected?.name, 'Frankfurt');
      expect(saved, 'test-frankfurt');
    },
  );

  test('fills a missing latency after the list is already available', () async {
    final controller = ServerSelectionController(
      _MeasuringCatalog(),
      readSelected: () async => null,
      writeSelected: (_) async {},
      activateConfiguration: (_) async {},
      activateNode: (_, _) async {},
    );
    addTearDown(controller.dispose);

    await controller.load();
    expect(controller.servers.single.name, 'Office');
    await Future<void>.delayed(Duration.zero);

    expect(controller.servers.single.latencyMs, 73);
    expect(controller.selected?.latencyMs, 73);
  });

  test('test catalog contains no endpoint or configuration material', () async {
    final servers = await const FakeServerCatalog().load();

    expect(servers, isNotEmpty);
    for (final server in servers) {
      expect(server.id, startsWith('test-'));
      expect(server.name, isNot(contains('://')));
      expect(server.description, isNot(contains('=')));
    }
  });

  test(
    'subscription catalog projects the server-owned node metadata',
    () async {
      const subscription = Subscription(
        id: 'account',
        url: 'https://example.invalid/subscription',
        nodes: [
          SubscriptionNode(
            id: 'north',
            tag: 'Aurora',
            endpoint: '<redacted>',
            position: 0,
            country: 'fi',
            description: 'Fastest available server',
          ),
        ],
      );
      final catalog = SubscriptionServerCatalog(
        loadSubscriptions: () async => const [subscription],
        loadConfigurations: () async => const [],
        probeConfiguration: (configuration) async {
          expect(configuration, '<redacted>');
          return {'elapsed_ms': 51};
        },
      );

      final server = (await catalog.load()).single;

      expect(server.id, 'node:account:north');
      expect(server.name, 'Aurora');
      expect(server.description, 'Fastest available server');
      expect(server.flag, '🇫🇮');
      expect(server.subscriptionId, 'account');
      expect(server.nodeId, 'north');
      expect(await catalog.measureLatency(server), 51);
    },
  );

  test(
    'selecting a subscription node activates its backend identity',
    () async {
      const node = ServerOption(
        id: 'node:account:north',
        name: 'Aurora',
        description: 'Fastest available server',
        flag: '🇫🇮',
        subscriptionId: 'account',
        nodeId: 'north',
      );
      String? activatedSubscription;
      String? activatedNode;
      final controller = ServerSelectionController(
        const FakeServerCatalog(),
        readSelected: () async => null,
        writeSelected: (_) async {},
        activateConfiguration: (_) async {},
        activateNode: (subscriptionId, nodeId) async {
          activatedSubscription = subscriptionId;
          activatedNode = nodeId;
        },
      );
      addTearDown(controller.dispose);
      controller.servers = const [node];

      await controller.select(node);

      expect(activatedSubscription, 'account');
      expect(activatedNode, 'north');
    },
  );
}
