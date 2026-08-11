import 'package:flutter/foundation.dart';

import 'subscription.dart';
import 'subscription_fetcher.dart';
import 'subscription_store.dart';

@immutable
class AccountSession {
  const AccountSession({required this.displayName});

  final String displayName;
}

/// Backend boundary for invitation and QR authentication.
abstract interface class AccountGateway {
  Future<AccountSession> acceptInvitation(String invitation);

  Future<AccountSession> signInWithQr();
}

class InvalidInvitation implements Exception {
  const InvalidInvitation();
}

class QrSignInUnavailable implements Exception {
  const QrSignInUnavailable();
}

typedef AddSubscription = Future<Subscription> Function(String url);
typedef RefreshSubscription =
    Future<Subscription> Function(Subscription subscription);
typedef RemoveSubscription = Future<void> Function(String id);

/// Turns the invitation credential into the subscription it represents.
///
/// The URL is a bearer secret. This boundary hands it only to the subscription
/// store and fetcher; it is never copied into diagnostics or an account model.
class SubscriptionAccountGateway implements AccountGateway {
  const SubscriptionAccountGateway({
    this.addSubscription = SubscriptionStore.add,
    this.refreshSubscription = _refresh,
    this.removeSubscription = SubscriptionStore.remove,
  });

  final AddSubscription addSubscription;
  final RefreshSubscription refreshSubscription;
  final RemoveSubscription removeSubscription;

  @override
  Future<AccountSession> acceptInvitation(String invitation) async {
    final uri = Uri.tryParse(invitation.trim());
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      throw const InvalidInvitation();
    }

    final subscription = await addSubscription(uri.toString());
    try {
      final refreshed = await refreshSubscription(subscription);
      if (!refreshed.hasNodes) {
        await removeSubscription(subscription.id);
        throw const InvalidInvitation();
      }
      return AccountSession(
        displayName: refreshed.name.isEmpty ? uri.host : refreshed.name,
      );
    } on SubscriptionFailed catch (error) {
      // A first attempt that failed must not leave a dead credential in the
      // settings. A previously useful cache is kept by the fetcher.
      if (!subscription.hasNodes) await removeSubscription(subscription.id);
      if (error.gone) throw const InvalidInvitation();
      rethrow;
    }
  }

  @override
  Future<AccountSession> signInWithQr() async {
    throw const QrSignInUnavailable();
  }

  static Future<Subscription> _refresh(Subscription subscription) =>
      SubscriptionFetcher.refresh(subscription, throwOnFailure: true);
}
