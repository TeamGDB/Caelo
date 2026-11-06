import 'dart:io';

import 'package:caelo/core/account_data.dart';
import 'package:caelo/core/app_storage.dart';
import 'package:caelo/core/config_store.dart';
import 'package:caelo/core/settings_store.dart';
import 'package:caelo/core/subscription.dart';
import 'package:caelo/core/subscription_store.dart';
import 'package:caelo/theme/palette.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('caelo-account-test-');
    AppStorage.testDirectory = directory;
    ConfigStore.directory = () async => directory;
    SubscriptionStore.forget();
  });

  tearDown(() async {
    AppStorage.testDirectory = null;
    ConfigStore.directory = AppStorage.directory;
    SubscriptionStore.forget();
    await directory.delete(recursive: true);
  });

  test('forgetting the account removes what came with it (#103)', () async {
    final subscription = await SubscriptionStore.add(
      'https://example.invalid/sub/one',
    );
    await SubscriptionStore.save(
      subscription.copyWith(
        nodes: const [
          SubscriptionNode(id: 'a', tag: 'A', endpoint: '{}', position: 0),
        ],
      ),
    );
    await ConfigStore.create('Mine', '[Interface]\nx\n[Peer]\ny');
    await ConfigStore.activateSubscriptionNode('{}');
    await SettingsStore.setSelectedServerId('node:x:a');
    await SettingsStore.setThemeMode(CaeloThemeMode.dark);

    await AccountData.forget();
    SubscriptionStore.forget();

    expect(await SubscriptionStore.all(), isEmpty);
    expect(await ConfigStore.list(), isEmpty);
    expect(await ConfigStore.read(), isNull);
    expect(await SettingsStore.selectedServerId(), isEmpty);
    // A preference, not part of the account.
    expect(await SettingsStore.themeMode(), CaeloThemeMode.dark);
  });

  test('a second onboarding after forgetting has one set of servers', () async {
    await SubscriptionStore.add('https://example.invalid/sub/one');
    await AccountData.forget();
    await SubscriptionStore.add('https://example.invalid/sub/two');

    SubscriptionStore.forget();
    final all = await SubscriptionStore.all();
    expect(all.single.url, 'https://example.invalid/sub/two');
  });
}
