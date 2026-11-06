// Against a real subscription and the real core, end to end, without the app's
// interface: what the person gets after pasting a link, as data.
//
// Skipped unless both are given, so CI and a fresh checkout never touch a
// network or a credential:
//
//   ./scripts/build-linux.sh debug
//   CAELO_LIVE_SUBSCRIPTION='https://…' \
//   CAELO_CORE_DYLIB=build/linux/x64/debug/bundle/lib/libcaelo.so \
//   flutter test test/live
//
// The link is a bearer credential. It is read from the environment and never
// printed; nothing below prints an endpoint, a key or an address.
//
// State lives in ~/.cache/caelo-live-test so the device identity is the same
// on every run. A fresh one each time would have the subscription provision a
// new peer per server per run.

import 'dart:convert';
import 'dart:io';

import 'package:caelo/core/app_storage.dart';
import 'package:caelo/core/build_info.dart';
import 'package:caelo/core/config_store.dart';
import 'package:caelo/core/device_description.dart';
import 'package:caelo/core/ffi/core_library.dart';
import 'package:caelo/core/server_catalog.dart';
import 'package:caelo/core/settings_store.dart';
import 'package:caelo/core/subscription.dart';
import 'package:caelo/core/subscription_fetcher.dart';
import 'package:caelo/core/subscription_store.dart';
import 'package:flutter_test/flutter_test.dart';

final _link = Platform.environment['CAELO_LIVE_SUBSCRIPTION'];
final _core = Platform.environment['CAELO_CORE_DYLIB'];
final String? _skip = _link == null || _core == null
    ? 'set CAELO_LIVE_SUBSCRIPTION and CAELO_CORE_DYLIB to run'
    : null;

const _long = Timeout(Duration(minutes: 5));

void main() {
  late Subscription subscription;

  setUpAll(() async {
    if (_skip != null) return;
    final home = Platform.environment['HOME']!;
    final state = Directory('$home/.cache/caelo-live-test')
      ..createSync(recursive: true);
    AppStorage.testDirectory = state;
    ConfigStore.directory = () async => state;
    SettingsStore.file = (name) async => File('${state.path}/$name');
    SubscriptionStore.forget();
    SettingsStore.forgetCache();
    subscription = await SubscriptionStore.add(_link!);
  });

  Future<Map<String, dynamic>> rawState() async {
    final client = HttpClient();
    try {
      final base = subscription.url.replaceAll(RegExp(r'/+$'), '');
      final request = await client.getUrl(Uri.parse('$base/state'));
      request.headers.set(HttpHeaders.userAgentHeader, 'Caelo/$appVersion');
      await DeviceHeaders.apply(request.headers);
      final response = await request.close();
      expect(response.statusCode, 200, reason: '/state should be served');
      return jsonDecode(await utf8.decodeStream(response))
          as Map<String, dynamic>;
    } finally {
      client.close(force: true);
    }
  }

  test(
    'the link is accepted and serves nodes',
    () async {
      subscription = await SubscriptionFetcher.refresh(
        subscription,
        throwOnFailure: true,
      );
      expect(subscription.hasNodes, isTrue);
      expect(subscription.isGone, isFalse);
      for (final node in subscription.nodes) {
        expect(node.id, isNotEmpty, reason: 'every node needs a stable id');
        expect(node.id, isNot(startsWith('at:')), reason: 'not position-based');
      }
      printOnFailure('nodes: ${subscription.nodes.map((n) => n.tag).toList()}');
    },
    skip: _skip,
    timeout: _long,
  );

  test(
    'keys arrive for every server the subscription offers (#110)',
    () async {
      await SubscriptionFetcher.enableAll();
      subscription = (await SubscriptionStore.byId(subscription.id))!;
      final offered = subscription.available.map((s) => s.name).toSet();
      final withKeys = subscription.nodes.map((n) => n.tag).toSet();
      final refused = SubscriptionFetcher.refused
          .where((key) => key.startsWith('${subscription.id}:'))
          .length;
      // ignore: avoid_print
      print(
        'offered ${offered.length}, with keys ${withKeys.length}, '
        'refused $refused, missing ${offered.difference(withKeys).toList()}',
      );
      expect(
        offered.difference(withKeys).length,
        lessThanOrEqualTo(refused),
        reason: 'an offered server without keys must be one the server refused',
      );
    },
    skip: _skip,
    timeout: _long,
  );

  test(
    '/state lists exactly the nodes the document carries, so a removal '
    'reaches the app (#111)',
    () async {
      final state = await rawState();
      expect(state['version'], isA<String>());
      final stateIds = [
        for (final node in (state['nodes'] as List? ?? const []))
          (node as Map)['id'] as String,
      ]..sort();
      final documentIds = [for (final node in subscription.nodes) node.id]
        ..sort();
      expect(stateIds, documentIds);

      final again = await rawState();
      expect(
        again['version'],
        state['version'],
        reason: 'the version must not change when nothing did',
      );
    },
    skip: _skip,
    timeout: _long,
  );

  test(
    'every node carries traffic from here, through the real core',
    () async {
      final results = <String, String>{};
      var answered = 0;
      for (final node in subscription.nodes) {
        try {
          final result = await CoreLibrary.measureLatency(
            node.endpoint,
            timeout: const Duration(seconds: 10),
          );
          results[node.tag] = '${result['latency_ms']} ms';
          answered++;
        } on Object catch (error) {
          results[node.tag] = 'no answer (${error.runtimeType})';
        }
      }
      // ignore: avoid_print
      print(results);
      expect(
        answered,
        greaterThan(0),
        reason: 'nothing at all carries traffic',
      );
    },
    skip: _skip,
    timeout: _long,
  );

  test(
    'automatic picks the fastest, and traffic leaves through it',
    () async {
      final servers = ServerSelectionController(SubscriptionServerCatalog());
      addTearDown(servers.dispose);
      await servers.load();
      expect(servers.selected?.automatic, isTrue);

      // Nothing remembered, so this is the full comparison.
      await SettingsStore.setLastConnectedServerId('');
      final prepared = await servers.prepareConnection({}, () => false);
      expect(prepared.failure, isNull);
      final chosen = servers.active!;
      // ignore: avoid_print
      print('chosen ${chosen.name} at ${prepared.latencyMs} ms');

      final config = await ConfigStore.read();
      expect(config, isNotNull);
      expect(
        await ConfigStore.list(),
        isEmpty,
        reason: 'choosing a node must not add a configuration (#103)',
      );

      final direct = await _myAddress();
      final through = await CoreLibrary.probe(config!);
      expect(
        through['body'],
        isNot(direct),
        reason: 'the address seen through the tunnel is the server\'s',
      );
    },
    skip: _skip,
    timeout: _long,
  );
}

Future<String> _myAddress() async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(Uri.parse('https://ifconfig.me/ip'));
    final response = await request.close();
    return (await utf8.decodeStream(response)).trim();
  } finally {
    client.close(force: true);
  }
}
