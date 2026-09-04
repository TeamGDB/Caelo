import 'dart:async';

import 'package:caelo/core/server_catalog.dart';
import 'package:caelo/core/subscription.dart';
import 'package:flutter_test/flutter_test.dart';

Subscription withOffer({required bool ready}) => Subscription(
  id: 'sub',
  url: 'https://example.com/sub/token',
  available: [
    AvailableServer(
      id: 'srv-amber',
      name: 'Amber',
      country: 'LV',
      ready: ready,
    ),
  ],
);

void main() {
  // Подписка больше не выдаёт ключи на все серверы вперёд — иначе на одной
  // ссылке копятся десятки конфигов, которыми никто не пользуется. Значит,
  // список должен показывать и то, чего ещё нет.
  test('сервер без ключей всё равно виден в списке', () async {
    final catalog = SubscriptionServerCatalog(
      loadSubscriptions: () async => [withOffer(ready: false)],
      loadConfigurations: () async => const [],
    );

    final servers = await catalog.load();
    final amber = servers.firstWhere((server) => server.name == 'Amber');

    expect(amber.needsKeys, isTrue, reason: 'на него ещё нет конфига');
    expect(amber.nodeId, isNull);
    expect(amber.flag, '🇱🇻');
  });

  _preparingTests();

  test('выданный сервер ключей не просит', () async {
    final catalog = SubscriptionServerCatalog(
      loadSubscriptions: () async => [withOffer(ready: true)],
      loadConfigurations: () async => const [],
    );

    // ready означает, что конфиг уже есть и придёт узлом; предлагать его
    // второй раз значило бы попросить сервер выдать то, что уже выдано.
    expect(await catalog.load(), isEmpty);
  });
}

// Пока идёт выдача ключей, список обязан показывать выбранным именно тот
// сервер, который нажали. Иначе он секунды подряд показывает прежний, это
// читается как «не нажалось», и человек жмёт другой — подключаясь к тому, что
// нажал позже.
void _preparingTests() {
  test('нажатый сервер отмечается сразу, а не после выдачи', () async {
    final released = Completer<Subscription?>();
    ServerOption? seenWhileWaiting;

    late final ServerSelectionController controller;
    controller = ServerSelectionController(
      SubscriptionServerCatalog(
        loadSubscriptions: () async => [withOffer(ready: false)],
        loadConfigurations: () async => const [],
      ),
      readSelected: () async => null,
      writeSelected: (_) async {},
      activateConfiguration: (_) async {},
      activateNode: (_, _) async {},
      readSubscription: (_) async => withOffer(ready: false),
      grantServer: (subscription, serverId) {
        seenWhileWaiting = controller.preparing;
        return released.future;
      },
    );

    await controller.load();
    final amber = controller.servers.firstWhere((s) => s.name == 'Amber');

    final selecting = controller.select(amber);
    await Future<void>.delayed(Duration.zero);

    expect(seenWhileWaiting?.name, 'Amber', reason: 'отмечен, пока ещё ждём');
    expect(controller.isPreparing, isTrue);

    released.complete(null);
    await selecting;
    expect(controller.isPreparing, isFalse, reason: 'ожидание закончилось');
  });
}
