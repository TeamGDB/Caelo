import 'dart:async';

import 'package:app_links/app_links.dart';

/// A subscription link handed to Caelo from outside: a browser, a messenger,
/// the panel's "Open in Caelo" button (#163).
///
/// The only form accepted is `caelo://add?url=<percent-encoded https link>`.
/// The link inside is the ordinary subscription URL, the one a person would
/// otherwise paste, so nothing about the subscription protocol changes.
///
/// Parsing is deliberately strict and deliberately says nothing about why a
/// link was refused: it arrives from anywhere on the internet, and the only
/// useful answer to a malformed one is to ignore it.
Uri? invitationFromAppLink(Uri link) {
  if (link.scheme != 'caelo' || link.host != 'add') return null;
  final raw = link.queryParameters['url'];
  if (raw == null) return null;
  final uri = Uri.tryParse(raw.trim());
  // The same rule as a pasted invitation (SubscriptionAccountGateway): an
  // https link with a host and no credentials in it.
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty) {
    return null;
  }
  return uri;
}

/// Where links come from. A seam for tests; the platform otherwise.
abstract interface class AppLinkSource {
  /// Every link the app is opened with, the one that launched it included.
  Stream<Uri> get links;
}

/// The operating system, through `app_links`.
///
/// Its stream carries the link that started the app as well as later ones,
/// which is why it is subscribed to once, at launch.
class PlatformAppLinkSource implements AppLinkSource {
  const PlatformAppLinkSource();

  @override
  Stream<Uri> get links {
    try {
      return AppLinks().uriLinkStream;
    } on Object {
      // No plugin on this platform (tests, an unsupported embedder): no links,
      // which is what the app did before #163.
      return const Stream.empty();
    }
  }
}
