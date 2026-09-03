import 'dart:convert';
import 'dart:io';

import 'package:caelo/core/subscription.dart';
import 'package:caelo/core/subscription_fetcher.dart';
import 'package:flutter_test/flutter_test.dart';

/// A server that records what the client asked for and answers what it is told
/// to. The point of these tests is the request as much as the reply: the device
/// header is what keeps two devices off one set of keys, and a client that
/// quietly stopped sending it would break that with everything still green.
class _Server {
  _Server(this._handle);

  final void Function(HttpRequest) _handle;
  late final HttpServer _server;
  final headers = <String, List<String>>{};
  final paths = <String>[];

  Future<String> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server.listen((request) {
      paths.add(request.uri.path);
      request.headers.forEach((name, values) => headers[name] = values);
      _handle(request);
    });
    return 'http://127.0.0.1:${_server.port}/sub/token';
  }

  Future<void> stop() => _server.close(force: true);
}

void main() {
  // Узел, пропавший из ответа сервера, отозван: держать его — значит пробовать
  // конфигурацию, о которой сервер уже не знает. Список заменяется целиком,
  // поэтому проверять надо именно то, что старый узел исчез, а не то, что
  // новый добавился.
  test('узел, которого сервер больше не отдаёт, исчезает', () {
    const document =
        '{"endpoints":[{"type":"amneziawg","tag":"Amber",'
        '"address":["10.0.0.2/32"],'
        '"private_key":"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=",'
        '"peers":[{"address":"198.51.100.4","port":51820,'
        '"public_key":"AQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQE="}]}]}';

    final before = const Subscription(id: 's', url: 'https://example.com/sub/x')
        .copyWith(
          nodes: readNodes(document) + readNodes(document.replaceAll('Amber', 'Mett')),
        );
    expect(before.nodes.length, 2);

    // Сервер отдаёт только один узел — второй он отозвал.
    final after = before.copyWith(nodes: readNodes(document));

    expect(after.nodes.map((node) => node.tag), ['Amber']);
    expect(after.nodes.any((node) => node.tag == 'Mett'), isFalse);
  });

  test('the state check sends the device and reads the version', () async {
    final server = _Server((request) {
      request.response
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({'version': 'abc123', 'nodes': []}))
        ..close();
    });
    final url = await server.start();

    final version = await SubscriptionFetcher.peek(
      const Subscription(id: 's', url: '').copyWith().rebuiltWith(url),
    );

    expect(version, 'abc123');
    expect(server.paths.single, '/sub/token/state');
    expect(server.headers['x-caelo-device']?.single, isNotEmpty);
    await server.stop();
  });

  test('a server without the state endpoint is not an error', () async {
    final server = _Server((request) {
      request.response.statusCode = HttpStatus.notFound;
      request.response.close();
    });
    final url = await server.start();

    // null means "we do not know", and not knowing sends the caller to the
    // full fetch — which is what it did before any of this existed.
    expect(
      await SubscriptionFetcher.peek(
        const Subscription(id: 's', url: '').rebuiltWith(url),
      ),
      isNull,
    );
    await server.stop();
  });

  test('the version is remembered so the next check has something to compare', () {
    const before = Subscription(id: 's', url: 'https://example.com/sub/x');
    expect(before.stateVersion, isNull);

    final after = before.copyWith(stateVersion: 'v1');
    expect(after.stateVersion, 'v1');

    // Through storage as well: a version kept only in memory would send the
    // client for the whole document on every launch.
    expect(Subscription.fromJson(after.toJson()).stateVersion, 'v1');
  });
}

extension on Subscription {
  Subscription rebuiltWith(String url) => Subscription(
    id: id,
    url: url,
    name: name,
    nodes: nodes,
    usage: usage,
    updateInterval: updateInterval,
    lastFetched: lastFetched,
    lastError: lastError,
    pinnedId: pinnedId,
    stateVersion: stateVersion,
  );
}
