import 'dart:convert';
import 'dart:io';

import 'package:caelo/core/app_storage.dart';
import 'package:caelo/core/device_description.dart';
import 'package:caelo/core/subscription.dart';
import 'package:caelo/core/subscription_fetcher.dart';
import 'package:caelo/core/subscription_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory directory;
  late HttpServer server;
  late List<Map<String, dynamic>> offered;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('caelo-catalogue-');
    AppStorage.testDirectory = directory;
    SubscriptionStore.forget();
    DeviceDescriptions.read = () async => DeviceDescription.nothing;
    DeviceDescriptions.forget();
    offered = [
      {'id': 'buran', 'name': 'Buran', 'ready': true},
    ];
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) {
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({'version': 'same', 'nodes': [], 'servers': offered}),
      );
      request.response.close();
    });
  });

  tearDown(() async {
    AppStorage.testDirectory = null;
    SubscriptionStore.forget();
    DeviceDescriptions.forget();
    await server.close(force: true);
    await directory.delete(recursive: true);
  });

  Future<Subscription> stored() async {
    final added = await SubscriptionStore.add(
      'http://127.0.0.1:${server.port}/sub/x',
    );
    final subscription = added.copyWith(
      stateVersion: 'same',
      lastFetched: DateTime.now(),
      updateInterval: const Duration(hours: 12),
      available: const [
        AvailableServer(id: 'buran', name: 'Buran', ready: true),
      ],
    );
    await SubscriptionStore.save(subscription);
    return subscription;
  }

  test('a server added in the panel arrives although the version did not '
      'change (#145)', () async {
    await stored();
    offered.add({'id': 'fi-pine', 'name': 'fi-pine', 'ready': false});

    final after = (await SubscriptionFetcher.refreshDue()).single;

    expect(after.available.map((s) => s.id), ['buran', 'fi-pine']);
    SubscriptionStore.forget();
    expect(
      (await SubscriptionStore.all()).single.available.map((s) => s.id),
      contains('fi-pine'),
      reason: 'and it is kept',
    );
  });

  test('nothing new means the stored subscription, untouched', () async {
    final before = await stored();
    final after = (await SubscriptionFetcher.refreshDue()).single;
    expect(after.available.length, before.available.length);
    expect(after.lastFetched, before.lastFetched);
  });

  test('a catalogue is the same whatever the order', () {
    const a = AvailableServer(id: 'a', name: 'A');
    const b = AvailableServer(id: 'b', name: 'B', ready: true);
    expect(SubscriptionFetcher.sameCatalogue([a, b], [b, a]), isTrue);
    expect(
      SubscriptionFetcher.sameCatalogue(
        [a, b],
        [a, const AvailableServer(id: 'b', name: 'B')],
      ),
      isFalse,
      reason: 'ready changed',
    );
    expect(SubscriptionFetcher.sameCatalogue([a], [a, b]), isFalse);
  });
}
