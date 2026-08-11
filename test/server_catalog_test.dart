import 'package:caelo/core/server_catalog.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'restores and persists selection without coupling to the catalog',
    () async {
      String? saved = 'demo-stockholm';
      final controller = ServerSelectionController(
        const MockServerCatalog(),
        readSelected: () async => saved,
        writeSelected: (id) async => saved = id,
      );
      addTearDown(controller.dispose);

      await controller.load();
      expect(controller.selected?.name, 'Stockholm');

      await controller.select(MockServerCatalog.servers.last);
      expect(controller.selected?.name, 'Frankfurt');
      expect(saved, 'demo-frankfurt');
    },
  );

  test('mock catalog contains no endpoint or configuration material', () async {
    final servers = await const MockServerCatalog().load();

    expect(servers, isNotEmpty);
    for (final server in servers) {
      expect(server.id, startsWith('demo-'));
      expect(server.name, isNot(contains('://')));
      expect(server.location, isNot(contains('=')));
    }
  });
}
