import 'package:caelo/core/account_gateway.dart';
import 'package:caelo/core/subscription.dart';
import 'package:caelo/core/subscription_fetcher.dart';
import 'package:flutter_test/flutter_test.dart';

const _empty = Subscription(id: 'account', url: 'https://example.test/sub/x');
const _node = SubscriptionNode(
  id: 'node',
  tag: 'Server',
  endpoint: '{}',
  position: 0,
);

void main() {
  test('accepts only a subscription that fetched real nodes', () async {
    String? addedUrl;
    final gateway = SubscriptionAccountGateway(
      addSubscription: (url) async {
        addedUrl = url;
        return _empty;
      },
      refreshSubscription: (subscription) async => Subscription(
        id: subscription.id,
        url: subscription.url,
        nodes: const [_node],
      ),
      removeSubscription: (_) async {},
    );

    final session = await gateway.acceptInvitation(
      ' https://example.test/sub/x ',
    );

    expect(addedUrl, 'https://example.test/sub/x');
    expect(session.displayName, 'example.test');
  });

  test('maps a rejected credential to an invalid invitation', () async {
    String? removed;
    final gateway = SubscriptionAccountGateway(
      addSubscription: (_) async => _empty,
      refreshSubscription: (_) async =>
          throw const SubscriptionFailed('not recognised', gone: true),
      removeSubscription: (id) async => removed = id,
    );

    await expectLater(
      gateway.acceptInvitation('https://example.test/sub/revoked'),
      throwsA(isA<InvalidInvitation>()),
    );
    expect(removed, _empty.id);
  });

  test('does not disguise a temporary backend failure as a bad link', () async {
    String? removed;
    final gateway = SubscriptionAccountGateway(
      addSubscription: (_) async => _empty,
      refreshSubscription: (_) async =>
          throw const SubscriptionFailed('network unavailable'),
      removeSubscription: (id) async => removed = id,
    );

    await expectLater(
      gateway.acceptInvitation('https://example.test/sub/x'),
      throwsA(isA<SubscriptionFailed>()),
    );
    expect(removed, _empty.id);
  });

  test('rejects a non-HTTPS link before storing it', () async {
    var additions = 0;
    final gateway = SubscriptionAccountGateway(
      addSubscription: (_) async {
        additions++;
        return _empty;
      },
      refreshSubscription: (_) async => _empty,
      removeSubscription: (_) async {},
    );

    await expectLater(
      gateway.acceptInvitation('http://example.test/sub/x'),
      throwsA(isA<InvalidInvitation>()),
    );
    expect(additions, 0);
  });
}
