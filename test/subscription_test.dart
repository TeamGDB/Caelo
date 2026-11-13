import 'dart:convert';

import 'package:caelo/core/subscription.dart';
import 'package:flutter_test/flutter_test.dart';

String document(List<Map<String, dynamic>> endpoints) =>
    jsonEncode({'endpoints': endpoints});

Map<String, dynamic> node(String tag, {String type = 'amneziawg'}) => {
  'type': type,
  'tag': tag,
  'address': ['10.0.0.2/32'],
  'private_key': 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=',
  'peers': [
    {
      'address': '198.51.100.4',
      'port': 51820,
      'public_key': 'AQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQE=',
    },
  ],
};

void main() {
  group('reading a document', () {
    test('keeps the order the server served', () {
      final nodes = readNodes(
        document([node('First'), node('Second'), node('Third')]),
      );

      expect(nodes.map((each) => each.tag), ['First', 'Second', 'Third']);
      expect(nodes.map((each) => each.position), [0, 1, 2]);
    });

    test('carries each endpoint as text without reading into it', () {
      final nodes = readNodes(document([node('Only')]));
      final carried = jsonDecode(nodes.single.endpoint) as Map<String, dynamic>;

      // Whatever the server sent, unchanged. The core reads this; nothing here
      // does, and a field the app has never heard of has to survive the trip.
      expect(carried['private_key'], isNotNull);
      expect(carried['peers'], isA<List>());
    });

    test('skips protocols this build cannot run, and keeps the rest', () {
      final nodes = readNodes(
        document([
          node('Vless', type: 'vless'),
          node('Ours'),
          node('Trojan', type: 'trojan'),
        ]),
      );

      // Refusing the whole document would take away the nodes that do work.
      expect(nodes.map((each) => each.tag), ['Ours']);
      // The position is where it came in the document, not where it came in
      // what survived: the server's order is about its own list.
      expect(nodes.single.position, 1);
    });

    test('refuses a document whose every node it cannot run, saying why', () {
      // Refused, so that the list that worked stays in place (#172).
      expect(
        () => readNodes(document([node('Vless', type: 'vless')])),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('vless'),
          ),
        ),
      );
      expect(() => readNodes('{}'), throwsFormatException);
      expect(() => readNodes('[]'), throwsFormatException);
    });

    test('reads a document with no nodes as an empty subscription', () {
      // Not a failure: the server answered, and what it said is that there is
      // nothing to connect to. The interface says so rather than "could not
      // update" (#172).
      expect(readNodes('{"endpoints":[]}'), isEmpty);
    });

    test('says which nodes it left out', () {
      final read = readSubscription(
        document([
          node('Vless', type: 'vless'),
          node('Ours'),
          node('Trojan', type: 'trojan'),
        ]),
      );
      expect(read.nodes.map((each) => each.tag), ['Ours']);
      expect(read.skipped, ['vless', 'trojan']);
    });
  });

  group('a list of links', () {
    // The three links from the issue: test values and documentation
    // addresses only.
    const vision =
        'vless://00000000-0000-4000-8000-000000000001@192.0.2.10:443?encryption=none&type=tcp&headerType=none&flow=xtls-rprx-vision&security=reality&sni=edge.example.com&pbk=AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8&sid=0123456789abcdef&fp=safari#Example%20Vision';
    const xhttp =
        'vless://00000000-0000-4000-8000-000000000001@192.0.2.10:443?encryption=none&type=xhttp&mode=packet-up&path=%2Fxhttp&security=reality&sni=edge.example.com&pbk=AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8&sid=0123456789abcdef&fp=safari#Example%20XHTTP';
    const cdn =
        'vless://00000000-0000-4000-8000-000000000001@cdn.example.com:443?encryption=none&type=xhttp&mode=packet-up&path=%2Fxhttp&security=tls&sni=cdn.example.com&host=cdn.example.com&fp=safari&alpn=h2%2Chttp%2F1.1#Example%20CDN';
    const vless = {'amneziawg', 'vless'};

    test('reads them as text, one per line, keeping each as served', () {
      final nodes = readNodes(
        '$vision\r\n  $xhttp  \n\n$cdn\n',
        contentType: 'text/plain',
        protocols: vless,
      );
      expect(nodes.map((each) => each.tag), [
        'Example Vision',
        'Example XHTTP',
        'Example CDN',
      ]);
      expect(nodes.map((each) => each.protocol).toSet(), {'vless'});
      expect(nodes.first.endpoint, vision, reason: 'carried, not rewritten');
      expect(nodes.map((each) => each.position), [0, 1, 2]);
    });

    test('reads them in base64, padded or not, standard or URL-safe', () {
      final text = [vision, xhttp, cdn].join('\n');
      final encoded = base64.encode(utf8.encode(text));
      for (final body in [
        encoded,
        encoded.replaceAll('=', ''),
        encoded.replaceAll('+', '-').replaceAll('/', '_'),
        // Wrapped at 76, as some servers do.
        RegExp('.{1,76}').allMatches(encoded).map((m) => m[0]).join('\n'),
      ]) {
        expect(readNodes(body, protocols: vless), hasLength(3));
      }
    });

    test('decodes Unicode names and IPv6 servers', () {
      const link =
          'vless://00000000-0000-4000-8000-000000000001@[2001:db8::1]:443?type=tcp&security=reality&pbk=x&sni=a.example.com#%D0%93%D0%B5%D1%80%D0%BC%D0%B0%D0%BD%D0%B8%D1%8F%20%F0%9F%87%A9%F0%9F%87%AA';
      final nodes = readNodes(link, protocols: vless);
      expect(nodes.single.tag, 'Германия 🇩🇪');
      expect(nodes.single.id, 'tag:Германия 🇩🇪');
    });

    test('skips links of protocols this build does not run', () {
      final read = readSubscription(
        'vmess://abc\n$vision\ntrojan://x@192.0.2.1:443#t',
        protocols: vless,
      );
      expect(read.nodes.single.tag, 'Example Vision');
      expect(read.skipped, ['vmess', 'trojan']);
    });

    test('a build without VLESS refuses a list of only VLESS, saying why', () {
      expect(
        () => readNodes('$vision\n$xhttp'),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('vless ×2'),
          ),
        ),
      );
    });

    test('an empty text answer is an empty subscription', () {
      expect(
        readNodes('', contentType: 'text/plain', protocols: vless),
        isEmpty,
      );
      // Anything else that is empty is a server that sent nothing.
      expect(() => readNodes('', protocols: vless), throwsFormatException);
    });

    test('text that is neither JSON nor links is refused', () {
      expect(
        () => readNodes('<html>nope</html>', protocols: vless),
        throwsFormatException,
      );
      expect(
        () => readNodes(
          base64.encode(utf8.encode('hello\nworld')),
          protocols: vless,
        ),
        throwsFormatException,
      );
    });

    test('three ways into one server, sharing a user id, are three nodes', () {
      final nodes = readNodes(
        [vision, xhttp, cdn].map((link) => link.split('#').first).join('\n'),
        protocols: vless,
      );
      // No names: identity is the connection each describes.
      expect(nodes.map((each) => each.id).toSet(), hasLength(3));
      expect(nodes.every((each) => each.id.startsWith('link:')), isTrue);
    });

    test('a new user id or fingerprint keeps the node chosen by hand', () {
      String unnamed(String link) => link.split('#').first;
      final before = readNodes(unnamed(vision), protocols: vless);
      final after = readNodes(
        unnamed(vision)
            .replaceAll(
              '00000000-0000-4000-8000-000000000001',
              '00000000-0000-4000-8000-000000000002',
            )
            .replaceAll('fp=safari', 'fp=chrome'),
        protocols: vless,
      );
      expect(after.single.id, before.single.id);
    });

    test(
      'nodes survive being written down and read back with their protocol',
      () {
        final link = readNodes(vision, protocols: vless).single;
        final restored = SubscriptionNode.fromJson(
          jsonDecode(jsonEncode(link.toJson())) as Map<String, dynamic>,
        );
        expect(restored.protocol, 'vless');
        expect(restored.endpoint, vision);
        // AmneziaWG nodes are stored exactly as before there was a choice.
        final awg = readNodes(document([node('A')])).single.toJson();
        expect(awg.containsKey('protocol'), isFalse);
      },
    );
  });

  group('the usage header', () {
    test('reads what a server sends', () {
      final usage = SubscriptionUsage.parse(
        'upload=100; download=44040192; total=107374182400; expire=1893456000',
      );

      expect(usage.uploadBytes, 100);
      expect(usage.usedBytes, 44040292);
      expect(usage.remainingBytes, 107374182400 - 44040292);
      expect(usage.expires, DateTime.utc(2030, 1, 1));
    });

    test('treats expire=0 as no expiry rather than as 1970', () {
      expect(SubscriptionUsage.parse('total=1; expire=0').expires, isNull);
    });

    test('says nothing rather than zero when the server said nothing', () {
      const nothing = SubscriptionUsage();
      expect(nothing.totalBytes, isNull);
      expect(
        nothing.remainingBytes,
        isNull,
        reason: 'unknown is not "none left"',
      );
      expect(nothing.isEmpty, isTrue);
    });

    test('skips a field it cannot read instead of losing the rest', () {
      final usage = SubscriptionUsage.parse('total=abc; download=7; nonsense');
      expect(usage.totalBytes, isNull);
      expect(usage.downloadBytes, 7);
    });

    test('never reports more used than the allowance', () {
      final usage = SubscriptionUsage.parse('download=20; total=10');
      expect(usage.remainingBytes, 0);
    });
  });

  group('choosing which node to try', () {
    Subscription withNodes(
      List<String> tags, {
      String? pinned,
      Set<String> underMaintenance = const {},
    }) => Subscription(
      id: 'x',
      url: 'https://example.com/sub/token',
      pinnedId: pinned,
      nodes: [
        for (var i = 0; i < tags.length; i++)
          SubscriptionNode(
            id: 'tag:${tags[i]}',
            tag: tags[i],
            endpoint: '{}',
            position: i,
            maintenance: underMaintenance.contains(tags[i]),
          ),
      ],
    );

    test('follows the server when nothing was chosen by hand', () {
      final subscription = withNodes(['A', 'B', 'C']);
      expect(subscription.preferred?.tag, 'A');
      expect(subscription.candidates.map((each) => each.tag), ['A', 'B', 'C']);
    });

    test('puts a chosen node first and leaves the rest as served', () {
      final subscription = withNodes(['A', 'B', 'C'], pinned: 'tag:B');
      expect(subscription.preferred?.tag, 'B');
      expect(subscription.candidates.map((each) => each.tag), ['B', 'A', 'C']);
    });

    test('skips a node the server has taken out of service', () {
      final subscription = withNodes(['A', 'B', 'C'], underMaintenance: {'A'});
      // The server said so before anybody spent time finding out.
      expect(subscription.preferred?.tag, 'B');
      expect(subscription.candidates.map((each) => each.tag), ['B', 'C']);
    });

    test('has nothing to try when every node is out of service', () {
      final subscription = withNodes(['A'], underMaintenance: {'A'});
      expect(subscription.candidates, isEmpty);
    });

    test('falls back to the server when the chosen node is gone', () {
      final subscription = withNodes(['A', 'B'], pinned: 'tag:Withdrawn');
      expect(subscription.preferred?.tag, 'A');
      expect(subscription.candidates.map((each) => each.tag), ['A', 'B']);
    });
  });

  group('when to come back', () {
    Subscription due({DateTime? fetched, Duration? interval}) => Subscription(
      id: 'x',
      url: 'https://example.com/sub/token',
      lastFetched: fetched,
      updateInterval: interval,
    );

    test('a subscription from before the device headers is unannounced '
        '(#159)', () {
      final old = Subscription.fromJson({'id': 'x', 'url': 'https://e/sub'});
      expect(old.fetchedAsDevice, isFalse);
      expect(old.isUnannounced, isTrue);
      expect(old.copyWith(stateVersion: 'v').isUnannounced, isFalse);

      final marked = old.copyWith(fetchedAsDevice: true);
      expect(marked.toJson()['fetchedAsDevice'], isTrue);
      expect(Subscription.fromJson(marked.toJson()).isUnannounced, isFalse);
      expect(old.toJson().containsKey('fetchedAsDevice'), isFalse);
    });

    test('a subscription never fetched is due', () {
      expect(due().isDue, isTrue);
    });

    test('a server that asked for nothing is not polled', () {
      expect(due(fetched: DateTime(2000)).isDue, isFalse);
    });

    test('the interval the server asked for is honoured', () {
      expect(
        due(
          fetched: DateTime.now().subtract(const Duration(hours: 13)),
          interval: const Duration(hours: 12),
        ).isDue,
        isTrue,
      );
      expect(
        due(
          fetched: DateTime.now().subtract(const Duration(hours: 1)),
          interval: const Duration(hours: 12),
        ).isDue,
        isFalse,
      );
    });
  });

  group('the Caelo document', () {
    String caelo(List<Map<String, dynamic>> nodes) =>
        jsonEncode({'version': 1, 'nodes': nodes});

    test('carries identity and what to show, and keeps the order', () {
      final nodes = readNodes(
        caelo([
          {
            'id': 'fra-01',
            'country': 'de',
            'description': 'Best for video',
            'endpoint': node('Frankfurt'),
          },
          {
            'id': 'ams-01',
            'country': 'NL',
            'maintenance': true,
            'endpoint': node('Amsterdam'),
          },
        ]),
        contentType: caeloDocumentType,
      );

      expect(nodes.map((each) => each.id), ['fra-01', 'ams-01']);
      expect(nodes.first.description, 'Best for video');
      expect(nodes.first.country, 'DE', reason: 'normalised to upper case');
      expect(nodes.first.flag, '🇩🇪', reason: 'built here, not transmitted');
      expect(nodes.last.maintenance, isTrue);
    });

    test('is read as plain sing-box when the server did not say otherwise', () {
      // The content type decides, not what was asked for. A server may ignore
      // the Accept header entirely.
      expect(
        () => readNodes(
          caelo([
            {'id': 'x', 'endpoint': node('A')},
          ]),
        ),
        throwsFormatException,
      );
    });

    test('version 2 carries links beside endpoints, in one order', () {
      const link =
          'vless://00000000-0000-4000-8000-000000000001@192.0.2.10:443?type=tcp&flow=xtls-rprx-vision&security=reality&sni=edge.example.com&pbk=AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8&sid=0123456789abcdef&fp=safari#Example%20Vision';
      final body = jsonEncode({
        'version': 2,
        'nodes': [
          {'id': 'fra-awg', 'country': 'DE', 'endpoint': node('Frankfurt')},
          {
            'id': 'example-vision',
            'country': 'CH',
            'description': 'Example connection',
            'protocol': 'vless',
            'uri': link,
          },
          {
            'id': 'later',
            'protocol': 'hysteria2',
            'uri': 'hysteria2://x@192.0.2.1:443',
          },
        ],
      });

      final read = readSubscription(
        body,
        contentType: caeloDocumentType,
        protocols: {'amneziawg', 'vless'},
      );
      expect(read.nodes.map((each) => each.id), ['fra-awg', 'example-vision']);
      expect(read.nodes.last.protocol, 'vless');
      expect(read.nodes.last.endpoint, link);
      expect(read.nodes.last.tag, 'Example Vision');
      expect(read.nodes.last.country, 'CH');
      expect(read.skipped, ['hysteria2']);

      // A build that runs only AmneziaWG reads the same document for what it
      // can use — which is how one server answers old clients and new.
      final old = readNodes(body, contentType: caeloDocumentType);
      expect(old.map((each) => each.id), ['fra-awg']);
    });

    test('reads what it recognises from a version it does not know', () {
      final nodes = readNodes(
        jsonEncode({
          'version': 99,
          'nodes': [
            {'id': 'fra-01', 'endpoint': node('Frankfurt'), 'whatever': 1},
          ],
        }),
        contentType: caeloDocumentType,
      );

      // Turning down a whole subscription over a field we have not learned yet
      // would mean the client stops working when its server is upgraded.
      expect(nodes.single.id, 'fra-01');
    });
  });

  group('identity when the server gave none', () {
    test('a unique tag identifies a node', () {
      final nodes = readNodes(document([node('First'), node('Second')]));
      expect(nodes.map((each) => each.id), ['tag:First', 'tag:Second']);
    });

    test('a shared tag identifies neither, so position is used', () {
      final nodes = readNodes(
        document([node('Same'), node('Same'), node('Other')]),
      );
      expect(nodes.map((each) => each.id), ['at:0', 'at:1', 'tag:Other']);
    });

    test('an empty tag falls back to position', () {
      final nodes = readNodes(document([node('')]));
      expect(nodes.single.id, 'at:0');
    });
  });

  test('a subscription survives being written down and read back', () {
    final original = Subscription(
      id: 'abc123',
      url: 'https://example.com/sub/token',
      name: 'Mine',
      nodes: readNodes(document([node('First'), node('Second')])),
      usage: SubscriptionUsage.parse('total=10; download=4; expire=1893456000'),
      updateInterval: const Duration(hours: 12),
      lastFetched: DateTime.utc(2026, 8, 11, 12),
      pinnedId: 'tag:Second',
    );

    final restored = Subscription.fromJson(
      jsonDecode(jsonEncode(original.toJson())) as Map<String, dynamic>,
    );

    expect(restored.id, original.id);
    expect(restored.url, original.url);
    expect(restored.name, original.name);
    expect(restored.pinnedId, 'tag:Second');
    expect(restored.updateInterval, const Duration(hours: 12));
    expect(restored.lastFetched, original.lastFetched);
    expect(restored.usage.remainingBytes, 6);
    expect(restored.nodes.map((each) => each.tag), ['First', 'Second']);
    // The endpoint is the thing that eventually reaches a root process. If a
    // round trip through storage changed it, the tunnel would be configured
    // from something the server never sent.
    expect(restored.nodes.first.endpoint, original.nodes.first.endpoint);
  });
}
