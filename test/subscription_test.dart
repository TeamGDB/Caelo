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

    test('refuses a document with nothing usable in it', () {
      expect(
        () => readNodes(document([node('Vless', type: 'vless')])),
        throwsFormatException,
      );
      expect(() => readNodes('{"endpoints":[]}'), throwsFormatException);
      expect(() => readNodes('{}'), throwsFormatException);
      expect(() => readNodes('[]'), throwsFormatException);
    });
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
