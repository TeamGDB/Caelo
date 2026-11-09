// Subscription links opened from outside the app: caelo://add?url=… (#163).
//
// The stores are real and write files; the network is a stand-in that answers
// a subscription with a fixed node list, or refuses one link to show what
// happens when the new subscription does not work.

import 'dart:async';
import 'dart:io';

import 'package:caelo/core/account_gateway.dart';
import 'package:caelo/core/app_link.dart';
import 'package:caelo/core/app_storage.dart';
import 'package:caelo/core/config_store.dart';
import 'package:caelo/core/server_catalog.dart';
import 'package:caelo/core/settings_store.dart';
import 'package:caelo/core/subscription.dart';
import 'package:caelo/core/subscription_fetcher.dart';
import 'package:caelo/core/subscription_store.dart';
import 'package:caelo/main.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_tunnel_client.dart';

const _first = 'https://panel.example.invalid/sub/first';
const _second = 'https://other.example.invalid/sub/second';
const _broken = 'https://panel.example.invalid/sub/revoked';

Uri _link(String url) =>
    Uri.parse('caelo://add?url=${Uri.encodeComponent(url)}');

const _nodes = [
  SubscriptionNode(
    id: 'hel',
    tag: 'Helsinki',
    endpoint: '{"type":"amneziawg","tag":"Helsinki"}',
    position: 0,
    country: 'FI',
  ),
];

class _Links implements AppLinkSource {
  final controller = StreamController<Uri>.broadcast();

  @override
  Stream<Uri> get links => controller.stream;
}

void main() {
  group('invitationFromAppLink', () {
    test('takes the https link out of caelo://add', () {
      expect(invitationFromAppLink(_link(_first)), Uri.parse(_first));
      // A link with a query of its own survives the round trip.
      const withQuery = 'https://panel.example.invalid/sub/t?x=1&y=2';
      expect(invitationFromAppLink(_link(withQuery)), Uri.parse(withQuery));
    });

    test('ignores everything else', () {
      for (final link in [
        'caelo://add',
        'caelo://add?url=',
        'caelo://open?url=${Uri.encodeComponent(_first)}',
        'https://panel.example.invalid/sub/first',
        'other://add?url=${Uri.encodeComponent(_first)}',
        // Not https: a subscription link is a bearer secret.
        'caelo://add?url=${Uri.encodeComponent('http://panel.example.invalid/sub/x')}',
        // Credentials in the link.
        'caelo://add?url=${Uri.encodeComponent('https://me:pw@panel.example.invalid/sub/x')}',
        'caelo://add?url=${Uri.encodeComponent('https:///sub/x')}',
      ]) {
        expect(invitationFromAppLink(Uri.parse(link)), isNull, reason: link);
      }
    });

    test(
      'the platform source does not fail where there is no plugin',
      () async {
        // No platform channel in a unit test: a missing plugin must mean "no
        // links", not a crash at launch.
        final links = const PlatformAppLinkSource().links;
        expect(links, isA<Stream<Uri>>());
      },
    );
  });

  group('opening a link', () {
    late Directory directory;
    late _Links links;
    late FakeTunnelClient tunnel;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('caelo-link-test-');
      AppStorage.testDirectory = directory;
      ConfigStore.directory = () async => directory;
      SubscriptionStore.forget();
      links = _Links();
      tunnel = FakeTunnelClient();
    });

    tearDown(() async {
      AppStorage.testDirectory = null;
      ConfigStore.directory = AppStorage.directory;
      SubscriptionStore.forget();
      await links.controller.close();
      await directory.delete(recursive: true);
    });

    final gateway = SubscriptionAccountGateway(
      refreshSubscription: (subscription) async {
        if (subscription.url == _broken) {
          throw const SubscriptionFailed('gone', gone: true);
        }
        final updated = subscription.copyWith(
          nodes: _nodes,
          lastFetched: DateTime.now(),
          updateInterval: const Duration(hours: 12),
        );
        await SubscriptionStore.save(updated);
        return updated;
      },
    );

    Future<void> settle(WidgetTester tester, {int rounds = 40}) async {
      for (var i = 0; i < rounds; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)),
        );
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    Future<void> waitFor(WidgetTester tester, Finder finder) async {
      final deadline = DateTime.now().add(const Duration(seconds: 20));
      while (finder.evaluate().isEmpty) {
        if (DateTime.now().isAfter(deadline)) fail('timed out: $finder');
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump(const Duration(milliseconds: 50));
      }
      await settle(tester, rounds: 3);
    }

    final home = find.byKey(const ValueKey('selected-server-name'));

    Future<void> launch(WidgetTester tester, {bool signedIn = false}) async {
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        CaeloApp(
          localeMode: CaeloLocaleMode.russian,
          accessGranted: signedIn,
          accountGateway: gateway,
          tunnelClient: tunnel,
          serverCatalog: SubscriptionServerCatalog(
            probeConfiguration: (_) async => {'latency_ms': 30},
          ),
          appLinks: links,
        ),
      );
      await waitFor(tester, signedIn ? home : find.text('Добро пожаловать'));
    }

    Future<List<String>> stored(WidgetTester tester) async =>
        (await tester.runAsync(
          SubscriptionStore.all,
        ))!.map((s) => s.url).toList();

    Future<void> signInWith(WidgetTester tester, String url) async {
      await tester.runAsync(() async {
        final s = await SubscriptionStore.add(url);
        await SubscriptionStore.save(s.copyWith(nodes: _nodes));
        await SettingsStore.setAccessGranted(true);
      });
    }

    testWidgets('not signed in: asks, names the host, then signs in', (
      tester,
    ) async {
      await launch(tester);
      links.controller.add(_link(_first));
      await waitFor(tester, find.text('Добавить подписку?'));
      expect(find.textContaining('panel.example.invalid'), findsOneWidget);
      // Nothing is stored before the person agrees.
      expect(await stored(tester), isEmpty);

      await tester.tap(find.byKey(const ValueKey('app-link-confirm')));
      await waitFor(tester, home);
      expect(await stored(tester), [_first]);
    });

    testWidgets('cancelled: nothing changes', (tester) async {
      await launch(tester);
      links.controller.add(_link(_first));
      await waitFor(tester, find.text('Добавить подписку?'));
      await tester.tap(find.text('Отмена'));
      await settle(tester);
      expect(find.text('Добро пожаловать'), findsOneWidget);
      expect(await stored(tester), isEmpty);
    });

    testWidgets('a link that is not caelo://add asks nothing', (tester) async {
      await launch(tester);
      links.controller.add(Uri.parse('caelo://add?url=nonsense'));
      links.controller.add(Uri.parse('https://panel.example.invalid/sub/x'));
      await settle(tester);
      expect(find.byType(CupertinoAlertDialog), findsNothing);
    });

    testWidgets('the same subscription again: says so, changes nothing', (
      tester,
    ) async {
      await signInWith(tester, _first);
      await launch(tester, signedIn: true);
      links.controller.add(_link(_first));
      await waitFor(tester, find.text('Уже добавлена'));
      await tester.tap(find.text('Готово'));
      await settle(tester);
      expect(await stored(tester), [_first]);
    });

    testWidgets(
      'another subscription: warns, replaces once the new one works',
      (tester) async {
        await signInWith(tester, _first);
        await launch(tester, signedIn: true);
        links.controller.add(_link(_second));
        await waitFor(tester, find.text('Заменить подписку?'));
        expect(find.textContaining('other.example.invalid'), findsOneWidget);

        await tester.tap(find.byKey(const ValueKey('app-link-confirm')));
        await settle(tester);
        await waitFor(tester, home);
        expect(await stored(tester), [_second]);
      },
    );

    testWidgets('a replacement that does not work keeps the old subscription', (
      tester,
    ) async {
      await signInWith(tester, _first);
      await launch(tester, signedIn: true);
      links.controller.add(_link(_broken));
      await waitFor(tester, find.text('Заменить подписку?'));
      await tester.tap(find.byKey(const ValueKey('app-link-confirm')));
      await waitFor(tester, find.text('Не удалось добавить подписку'));
      expect(find.text('Проверьте ссылку приглашения'), findsOneWidget);
      await tester.tap(find.text('Готово'));
      await settle(tester);
      expect(await stored(tester), [_first]);
      expect(home, findsOneWidget);
    });

    testWidgets('a second link while the first is being asked about waits', (
      tester,
    ) async {
      await launch(tester);
      links.controller.add(_link(_first));
      await waitFor(tester, find.text('Добавить подписку?'));
      links.controller.add(_link(_second));
      await settle(tester);
      expect(find.byType(CupertinoAlertDialog), findsOneWidget);
    });
  });
}
