import 'dart:async';

import 'package:caelo/core/subscription.dart';
import 'package:caelo/core/subscription_fetcher.dart';
import 'package:flutter_test/flutter_test.dart';

Subscription _sub(String id, List<AvailableServer> offers, {String? error}) =>
    Subscription(
      id: id,
      url: 'https://example.invalid/$id',
      available: offers,
      lastError: error,
    );

AvailableServer _offer(String id, {bool ready = false}) =>
    AvailableServer(id: id, name: id, ready: ready);

void main() {
  test('asks for keys on every server that has none (#110)', () async {
    final asked = <String>[];
    final refreshed = <String>[];
    final granted = await SubscriptionFetcher.enableAll(
      subscriptions: () async => [
        _sub('a', [_offer('kazy', ready: true), _offer('mett'), _offer('neo')]),
      ],
      grant: (subscription, server) async {
        asked.add(server);
        return true;
      },
      refreshOne: (subscription) async {
        refreshed.add(subscription.id);
        return subscription;
      },
    );

    expect(asked, ['mett', 'neo']);
    expect(granted, 2);
    // Once at the end, not once per server.
    expect(refreshed, ['a']);
  });

  test('one at a time, never in a burst', () async {
    var inFlight = 0;
    var most = 0;
    await SubscriptionFetcher.enableAll(
      subscriptions: () async => [
        _sub('a', [for (var i = 0; i < 6; i++) _offer('s$i')]),
      ],
      grant: (_, _) async {
        inFlight++;
        most = most < inFlight ? inFlight : most;
        await Future<void>.delayed(const Duration(milliseconds: 2));
        inFlight--;
        return true;
      },
      refreshOne: (subscription) async => subscription,
    );
    expect(most, 1);
  });

  test(
    'a refused grant is skipped, and nothing granted means no refresh',
    () async {
      var refreshes = 0;
      final granted = await SubscriptionFetcher.enableAll(
        subscriptions: () async => [
          _sub('a', [_offer('x'), _offer('y')]),
        ],
        grant: (_, _) async => false,
        refreshOne: (subscription) async {
          refreshes++;
          return subscription;
        },
      );
      expect(granted, 0);
      expect(refreshes, 0);
    },
  );

  test('a subscription its server disowned is left alone', () async {
    var asked = 0;
    await SubscriptionFetcher.enableAll(
      subscriptions: () async => [
        _sub('a', [_offer('x')], error: subscriptionGoneMessage),
      ],
      grant: (_, _) async {
        asked++;
        return true;
      },
      refreshOne: (subscription) async => subscription,
    );
    expect(asked, 0);
  });

  test('a second caller joins the pass already running', () async {
    final gate = Completer<void>();
    var asked = 0;
    Future<int> run() => SubscriptionFetcher.enableAll(
      subscriptions: () async => [
        _sub('a', [_offer('x')]),
      ],
      grant: (_, _) async {
        asked++;
        await gate.future;
        return true;
      },
      refreshOne: (subscription) async => subscription,
    );

    final first = run();
    final second = run();
    gate.complete();
    expect(await first, 1);
    expect(await second, 1);
    expect(asked, 1);
  });
}
