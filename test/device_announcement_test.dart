import 'dart:convert';
import 'dart:io';

import 'package:caelo/core/app_storage.dart';
import 'package:caelo/core/device_description.dart';
import 'package:caelo/core/subscription.dart';
import 'package:caelo/core/subscription_fetcher.dart';
import 'package:caelo/core/subscription_store.dart';
import 'package:flutter_test/flutter_test.dart';

/// A subscription saved by a client older than the device headers must reach
/// the server once after the update, not half a day later (#159).
void main() {
  late Directory directory;
  late HttpServer server;
  late bool offersState;
  late List<({String path, String? device})> seen;

  const document =
      '{"endpoints":[{"type":"amneziawg","tag":"Amber",'
      '"address":["10.0.0.2/32"],'
      '"private_key":"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=",'
      '"peers":[{"address":"198.51.100.4","port":51820,'
      '"public_key":"AQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQE="}]}]}';

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('caelo-announce-');
    AppStorage.testDirectory = directory;
    SubscriptionStore.forget();
    DeviceDescriptions.read = () async => DeviceDescription.nothing;
    DeviceDescriptions.forget();
    offersState = false;
    seen = [];
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) {
      seen.add((
        path: request.uri.path,
        device: request.headers.value('X-Caelo-Device'),
      ));
      if (request.uri.path.endsWith('/state')) {
        if (!offersState) {
          request.response.statusCode = 404;
        } else {
          request.response.headers.contentType = ContentType.json;
          request.response.write(jsonEncode({'version': 'v1'}));
        }
      } else {
        request.response.headers.contentType = ContentType.json;
        request.response.headers.set('profile-update-interval', '12');
        request.response.write(document);
      }
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

  String url() => 'http://127.0.0.1:${server.port}/sub/x';

  /// What a client before v0.2.0 left on disk: fetched an hour ago, asked to
  /// come back in twelve, no version and no mark.
  Future<void> storeFromOldClient() async {
    final added = await SubscriptionStore.add(url());
    final old = Subscription.fromJson({
      ...added.toJson(),
      'updateIntervalMinutes': 12 * 60,
      'lastFetched': DateTime.now()
          .subtract(const Duration(hours: 1))
          .toIso8601String(),
    });
    expect(old.isDue, isFalse);
    expect(old.isUnannounced, isTrue);
    await SubscriptionStore.save(old);
  }

  List<String> fetches() =>
      seen.where((r) => !r.path.endsWith('/state')).map((r) => r.path).toList();

  test('an old subscription is fetched once, with the device', () async {
    offersState = true;
    await storeFromOldClient();

    final after = (await SubscriptionFetcher.refreshDue()).single;

    expect(fetches(), ['/sub/x']);
    expect(seen.first.device, isNotEmpty);
    expect(after.fetchedAsDevice, isTrue);
    expect(after.stateVersion, 'v1');

    SubscriptionStore.forget();
    final stored = (await SubscriptionStore.all()).single;
    expect(stored.fetchedAsDevice, isTrue, reason: 'and the mark is kept');
    expect(stored.isUnannounced, isFalse);
  });

  test(
    'a server without /state is not fetched again on every launch',
    () async {
      await storeFromOldClient();

      await SubscriptionFetcher.refreshDue();
      await SubscriptionFetcher.refreshDue();
      await SubscriptionFetcher.refreshDue();

      expect(fetches(), ['/sub/x'], reason: 'one fetch, then the schedule');
    },
  );

  test('a subscription with a version only asks /state', () async {
    offersState = true;
    final added = await SubscriptionStore.add(url());
    await SubscriptionStore.save(
      added.copyWith(
        stateVersion: 'v1',
        lastFetched: DateTime.now(),
        updateInterval: const Duration(hours: 12),
      ),
    );

    await SubscriptionFetcher.refreshDue();

    expect(fetches(), isEmpty);
    expect(seen.single.path, '/sub/x/state');
  });

  test('a failed fetch leaves it unannounced, to be tried again', () async {
    await storeFromOldClient();
    await server.close(force: true);

    final after = (await SubscriptionFetcher.refreshDue()).single;

    expect(after.lastError, isNotNull);
    expect(after.isUnannounced, isTrue);
  });
}
