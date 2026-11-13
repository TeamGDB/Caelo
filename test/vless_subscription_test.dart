import 'dart:convert';
import 'dart:io';

import 'package:caelo/core/app_storage.dart';
import 'package:caelo/core/capabilities.dart';
import 'package:caelo/core/config_store.dart';
import 'package:caelo/core/device_description.dart';
import 'package:caelo/core/ffi/core_library.dart';
import 'package:caelo/core/server_catalog.dart';
import 'package:caelo/core/subscription.dart';
import 'package:caelo/core/subscription_fetcher.dart';
import 'package:caelo/core/subscription_store.dart';
import 'package:caelo/core/tunnel.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_server_catalog.dart';

// VLESS in subscriptions (#172): what is asked, what is read, what is kept.
// Test values and documentation addresses only.

const _vision =
    'vless://00000000-0000-4000-8000-000000000001@192.0.2.10:443?encryption=none&type=tcp&flow=xtls-rprx-vision&security=reality&sni=edge.example.com&pbk=AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8&sid=0123456789abcdef&fp=safari#Example%20Vision';
const _cdn =
    'vless://00000000-0000-4000-8000-000000000001@cdn.example.com:443?encryption=none&type=xhttp&mode=packet-up&path=%2Fxhttp&security=tls&sni=cdn.example.com&host=cdn.example.com&fp=safari&alpn=h2%2Chttp%2F1.1#Example%20CDN';
const _websocket =
    'vless://00000000-0000-4000-8000-000000000001@192.0.2.11:443?type=ws&security=tls#Example%20WS';

const _withVless = CoreCapabilities(
  protocols: {'amneziawg', 'vless'},
  variants: {'vless-reality-vision', 'vless-tls-xhttp'},
);

/// What the core says about a node, without a core: links over WebSocket are
/// refused with a reason, the way the real one refuses them.
Map<String, dynamic> _fakeCore(String text) {
  if (text.contains('type=ws')) {
    throw CoreFailure('transport "ws": not supported');
  }
  return {'ok': true, 'protocol': 'vless'};
}

class _Server {
  _Server(this.respond);

  final void Function(HttpRequest) respond;
  late final HttpServer _server;
  final requests = <({String path, HttpHeaders headers})>[];

  Future<String> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server.listen((request) {
      requests.add((path: request.uri.path, headers: request.headers));
      respond(request);
    });
    return 'http://127.0.0.1:${_server.port}/sub/token';
  }

  Future<void> stop() => _server.close(force: true);
}

void _answer(HttpRequest request, String body, {String type = 'text/plain'}) {
  if (request.uri.path.endsWith('/state')) {
    request.response
      ..statusCode = 404
      ..close();
    return;
  }
  request.response
    ..headers.contentType = ContentType.parse('$type; charset=utf-8')
    ..headers.set('profile-update-interval', '12')
    ..write(body)
    ..close();
}

void main() {
  group('what is asked', () {
    test('a build that runs only AmneziaWG asks what it always asked', () {
      expect(
        Capabilities.accept(CoreCapabilities.baseline),
        'application/vnd.caelo.subscription+json, application/json',
      );
      expect(Capabilities.header(CoreCapabilities.baseline), isNull);
    });

    test(
      'a build that runs VLESS asks for version 2 and lists what it runs',
      () {
        expect(
          Capabilities.accept(_withVless),
          'application/vnd.caelo.subscription+json;version=2, '
          'application/vnd.caelo.subscription+json;q=0.9, '
          'application/json;q=0.8, text/plain;q=0.7',
        );
        expect(
          Capabilities.header(_withVless),
          'subscription-v2, vless-reality-vision, vless-tls-xhttp',
        );
      },
    );

    test('a service that runs less narrows what is announced', () {
      final both = _withVless.intersect(CoreCapabilities.baseline);
      expect(both.protocols, {'amneziawg'});
      expect(Capabilities.header(both), isNull);
    });

    test('a core or service from before the question reads as AmneziaWG', () {
      final old = CoreCapabilities.fromJson({'ok': true});
      expect(old.protocols, {'amneziawg'});
      expect(old.variants, isEmpty);
    });
  });

  group('what the tunnel reports', () {
    test('the protocol is read from what the core names', () {
      expect(
        TunnelProtocol.fromCore({'protocol': 'VLESS'}),
        TunnelProtocol.vless,
      );
      expect(
        TunnelProtocol.fromCore({'protocol': 'vless'}),
        TunnelProtocol.vless,
      );
      expect(
        TunnelProtocol.fromCore({'protocol': 'AmneziaWG'}),
        TunnelProtocol.amneziaWg,
      );
      expect(
        TunnelProtocol.fromCore({'protocol': 'amneziawg'}),
        TunnelProtocol.amneziaWg,
      );
      expect(TunnelProtocol.fromCore({'protocol': 'something new'}), isNull);
    });

    test('a reply from before the name existed is not taken for VLESS', () {
      // Its absence used to be read as VLESS, which made every plain
      // WireGuard tunnel a VLESS one.
      expect(
        TunnelProtocol.fromCore({'obfuscated': true}),
        TunnelProtocol.amneziaWg,
      );
      expect(
        TunnelProtocol.fromCore({'obfuscated': false}),
        TunnelProtocol.wireGuard,
      );
    });
  });

  group('refreshing', () {
    late Directory directory;
    late Map<String, dynamic> Function(String) originalValidate;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('caelo-vless-test-');
      AppStorage.testDirectory = directory;
      ConfigStore.directory = () async => directory;
      SubscriptionStore.forget();
      DeviceDescriptions.read = () async => DeviceDescription.nothing;
      Capabilities.override = _withVless;
      originalValidate = SubscriptionFetcher.validate;
      SubscriptionFetcher.validate = _fakeCore;
    });

    tearDown(() async {
      Capabilities.override = null;
      SubscriptionFetcher.validate = originalValidate;
      AppStorage.testDirectory = null;
      ConfigStore.directory = AppStorage.directory;
      SubscriptionStore.forget();
      await directory.delete(recursive: true);
    });

    test(
      'a base64 list of links is read, and the request says what we run',
      () async {
        final server = _Server(
          (request) => _answer(
            request,
            base64.encode(
              utf8.encode('$_vision\n$_cdn\n$_websocket\nvmess://x'),
            ),
          ),
        );
        final url = await server.start();
        addTearDown(server.stop);

        final subscription = await SubscriptionStore.add(url);
        final refreshed = await SubscriptionFetcher.refresh(subscription);

        expect(refreshed.lastError, isNull);
        expect(refreshed.nodes.map((node) => node.tag), [
          'Example Vision',
          'Example CDN',
        ]);
        expect(
          refreshed.nodes.every((node) => node.protocol == 'vless'),
          isTrue,
        );
        // What the core refused and what this build does not run are both
        // said, not silently dropped.
        expect(refreshed.skipped, [
          'vmess',
          'vless: transport "ws": not supported',
        ]);
        expect(refreshed.updateInterval, const Duration(hours: 12));

        final document = server.requests.firstWhere(
          (request) => request.path == '/sub/token',
        );
        expect(document.headers.value('accept'), contains('version=2'));
        expect(document.headers.value('accept'), contains('text/plain'));
        expect(
          document.headers.value('x-caelo-capabilities'),
          'subscription-v2, vless-reality-vision, vless-tls-xhttp',
        );
        // The same is said to the state endpoint.
        final state = server.requests.firstWhere(
          (request) => request.path.endsWith('/state'),
        );
        expect(state.headers.value('x-caelo-capabilities'), isNotNull);
      },
    );

    test(
      'a subscription none of whose nodes can run keeps the list that worked',
      () async {
        var body = _vision;
        final server = _Server((request) => _answer(request, body));
        final url = await server.start();
        addTearDown(server.stop);

        final subscription = await SubscriptionStore.add(url);
        final working = await SubscriptionFetcher.refresh(subscription);
        expect(working.nodes, hasLength(1));

        body = _websocket;
        final after = await SubscriptionFetcher.refresh(working);
        expect(after.nodes.single.tag, 'Example Vision');
        expect(after.lastError, contains('transport'));
      },
    );

    test('an empty answer is an empty subscription, not a failure', () async {
      final server = _Server((request) => _answer(request, ''));
      final url = await server.start();
      addTearDown(server.stop);

      final subscription = await SubscriptionStore.add(url);
      final refreshed = await SubscriptionFetcher.refresh(subscription);
      expect(refreshed.lastError, isNull);
      expect(refreshed.isEmpty, isTrue);
    });

    test('a failed refresh does not wipe the cache', () async {
      var status = 200;
      final server = _Server((request) {
        if (status != 200 && !request.uri.path.endsWith('/state')) {
          request.response
            ..statusCode = status
            ..close();
          return;
        }
        _answer(request, _vision);
      });
      final url = await server.start();
      addTearDown(server.stop);

      final working = await SubscriptionFetcher.refresh(
        await SubscriptionStore.add(url),
      );
      status = 502;
      final after = await SubscriptionFetcher.refresh(working);
      expect(after.nodes.single.tag, 'Example Vision');
      expect(after.lastError, contains('502'));
      expect(after.isEmpty, isFalse);
    });

    test(
      'a build without VLESS refuses a list of only VLESS, keeping its cache',
      () async {
        Capabilities.override = CoreCapabilities.baseline;
        final server = _Server(
          (request) => _answer(request, '$_vision\n$_cdn'),
        );
        final url = await server.start();
        addTearDown(server.stop);

        final refreshed = await SubscriptionFetcher.refresh(
          await SubscriptionStore.add(url),
        );
        expect(refreshed.nodes, isEmpty);
        expect(refreshed.lastError, contains('vless'));
        expect(
          refreshed.isEmpty,
          isFalse,
          reason: 'a failure, not an empty list',
        );
        final document = server.requests.firstWhere(
          (request) => request.path == '/sub/token',
        );
        expect(
          document.headers.value('accept'),
          'application/vnd.caelo.subscription+json, application/json',
        );
        expect(document.headers.value('x-caelo-capabilities'), isNull);
      },
    );
  });

  group('what the list says about a subscription', () {
    test('an empty subscription and left-out nodes become notes', () async {
      final controller = ServerSelectionController(
        FakeServerCatalog(),
        readSelected: () async => null,
        writeSelected: (_) async {},
        loadSubscriptions: () async => [
          Subscription(
            id: 'a',
            url: 'https://example.com/a',
            lastFetched: DateTime.utc(2026, 11, 13),
          ),
          Subscription(
            id: 'b',
            url: 'https://example.com/b',
            lastFetched: DateTime.utc(2026, 11, 13),
            nodes: readNodes(_vision, protocols: {'vless'}),
            skipped: const ['vmess', 'vmess', 'vless: transport "ws"'],
          ),
          // A subscription the server disowned says nothing here: the list
          // already says it is gone.
          Subscription(
            id: 'c',
            url: 'https://example.com/c',
            lastFetched: DateTime.utc(2026, 11, 13),
            lastError: subscriptionGoneMessage,
          ),
        ],
        backgroundMeasurement: false,
      );
      await controller.load();

      expect(controller.notes, hasLength(2));
      expect(controller.notes.first.empty, isTrue);
      expect(controller.notes.last.skipped, hasLength(3));
      expect(controller.notes.last.reasons, 'vmess; vless: transport "ws"');
      controller.dispose();
    });
  });
}
