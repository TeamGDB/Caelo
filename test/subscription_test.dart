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
    Subscription withNodes(List<String> tags, {String? pinned}) => Subscription(
      id: 'x',
      url: 'https://example.com/sub/token',
      pinnedTag: pinned,
      nodes: [
        for (var i = 0; i < tags.length; i++)
          SubscriptionNode(tag: tags[i], endpoint: '{}', position: i),
      ],
    );

    test('follows the server when nothing was chosen by hand', () {
      final subscription = withNodes(['A', 'B', 'C']);
      expect(subscription.preferred?.tag, 'A');
      expect(subscription.candidates.map((each) => each.tag), ['A', 'B', 'C']);
    });

    test('puts a chosen node first and leaves the rest as served', () {
      final subscription = withNodes(['A', 'B', 'C'], pinned: 'B');
      expect(subscription.preferred?.tag, 'B');
      expect(subscription.candidates.map((each) => each.tag), ['B', 'A', 'C']);
    });

    test('falls back to the server when the chosen node is gone', () {
      final subscription = withNodes(['A', 'B'], pinned: 'Withdrawn');
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

  test('a subscription survives being written down and read back', () {
    final original = Subscription(
      id: 'abc123',
      url: 'https://example.com/sub/token',
      name: 'Mine',
      nodes: readNodes(document([node('First'), node('Second')])),
      usage: SubscriptionUsage.parse('total=10; download=4; expire=1893456000'),
      updateInterval: const Duration(hours: 12),
      lastFetched: DateTime.utc(2026, 8, 11, 12),
      pinnedTag: 'Second',
    );

    final restored = Subscription.fromJson(
      jsonDecode(jsonEncode(original.toJson())) as Map<String, dynamic>,
    );

    expect(restored.id, original.id);
    expect(restored.url, original.url);
    expect(restored.name, original.name);
    expect(restored.pinnedTag, 'Second');
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
