import 'dart:io';

import 'package:caelo/core/app_storage.dart';
import 'package:caelo/core/config_store.dart';
import 'package:caelo/core/server_catalog.dart';
import 'package:flutter_test/flutter_test.dart';

const _first = '[Interface]\nPrivateKey = first\n[Peer]\nPublicKey = one';
const _second = '[Interface]\nPrivateKey = second\n[Peer]\nPublicKey = two';

void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('caelo-config-test-');
    ConfigStore.directory = () async => directory;
  });

  tearDown(() async {
    ConfigStore.directory = AppStorage.directory;
    await directory.delete(recursive: true);
  });

  test('stores several configs and exposes only the selected one', () async {
    final first = await ConfigStore.create('Work', _first);
    final second = await ConfigStore.create('Personal', _second);

    expect((await ConfigStore.list()).map((config) => config.name), [
      'Work',
      'Personal',
    ]);
    expect(await ConfigStore.read(), _second);

    await ConfigStore.select(first.id);
    expect(await ConfigStore.read(), _first);

    await ConfigStore.delete(first.id);
    expect(await ConfigStore.read(), _second);
    expect((await ConfigStore.list()).single.id, second.id);
  });

  test('migrates the old tunnel.conf without losing its contents', () async {
    await File('${directory.path}/tunnel.conf').writeAsString(_first);

    final configs = await ConfigStore.list();

    expect(configs.single.id, 'legacy');
    expect(configs.single.name, 'Imported configuration');
    expect(await ConfigStore.read(), _first);
    expect(await File('${directory.path}/tunnel.conf').exists(), isFalse);
  });

  test('catalog exposes config names but not their secret contents', () async {
    await ConfigStore.create('My office', _first);

    final configs = await ConfigStore.list();
    expect(configs.single.name, 'My office');
    expect(configs.single.toJson().toString(), isNot(contains('PrivateKey')));
    expect(configs.single.toJson().toString(), isNot(contains('PublicKey')));

    final servers = await const DevelopmentServerCatalog().load();
    final custom = servers.singleWhere((server) => server.configId != null);
    expect(custom.name, 'My office');
    expect(custom.badge, 'Custom');
    expect(custom.latencyMs, isNull);
  });
}
