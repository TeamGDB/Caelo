import 'dart:io';

import 'package:flutter/foundation.dart';

import 'diagnostics.dart';
import 'ffi/core_library.dart';
import 'service_client.dart';
import 'subscription.dart' show caeloDocumentType;

/// What this installation can connect to, and how a subscription is told.
///
/// The answer belongs to whatever runs the tunnel. On Android, iOS and macOS
/// that is the core linked into the app (and, on Apple platforms, into its
/// extension, built from the same core). On Linux and Windows with the service
/// installed it is the service, which can be older or newer than the app — so
/// what is announced there is what both can do: the app has to read a node
/// for the service to run it.
///
/// Announced so that a subscription server can choose what to send. Nothing
/// is announced that this build would not run, because a server that believed
/// us would send nodes that do not connect.
abstract final class Capabilities {
  /// Capability for the Caelo document's version 2 (links beside endpoints).
  static const subscriptionV2 = 'subscription-v2';

  static CoreCapabilities? _cached;
  static DateTime? _cachedAt;

  /// Long enough not to ask the service on every request, short enough that a
  /// service updated underneath a running app is noticed.
  static const _keepFor = Duration(minutes: 10);

  /// Set by tests; read instead of asking anything.
  @visibleForTesting
  static CoreCapabilities? override;

  /// What can be run here now.
  static Future<CoreCapabilities> current() async {
    final fixed = override;
    if (fixed != null) return fixed;

    final cached = _cached;
    final at = _cachedAt;
    if (cached != null &&
        at != null &&
        DateTime.now().difference(at) < _keepFor) {
      return cached;
    }

    final found = await _ask();
    _cached = found;
    _cachedAt = DateTime.now();
    return found;
  }

  /// Forgets what was found, so the next [current] asks again.
  static void forget() {
    _cached = null;
    _cachedAt = null;
  }

  static Future<CoreCapabilities> _ask() async {
    CoreCapabilities app;
    try {
      app = CoreLibrary.capabilities();
    } on Object catch (error) {
      // A core that will not load runs nothing; AmneziaWG is what every
      // subscription has always been asked for, and asking for it changes
      // nothing a server sends.
      Diagnostics.record('the core did not say what it runs', error: error);
      return CoreCapabilities.baseline;
    }

    if ((Platform.isLinux || Platform.isWindows) && ServiceClient.isInstalled) {
      try {
        final service = CoreCapabilities.fromJson(
          await ServiceClient.version(),
        );
        return app.intersect(service);
      } on Object catch (error) {
        // The service is installed and not answering. What it runs is
        // unknown, and claiming more than AmneziaWG would be a guess.
        Diagnostics.record(
          'the service did not say what it runs',
          error: error,
        );
        return app.intersect(CoreCapabilities.baseline);
      }
    }
    return app;
  }

  /// The `Accept` header for a subscription document.
  ///
  /// A build that runs only AmneziaWG asks exactly what it always asked, so
  /// that nothing about its requests changes. One that runs more asks for the
  /// Caelo document's version 2 first, and says it can also read the plain
  /// list of links every other client reads.
  static String accept(CoreCapabilities capabilities) {
    if (!_runsMore(capabilities)) {
      return '$caeloMediaType, application/json';
    }
    return '$caeloMediaType;version=2, '
        '$caeloMediaType;q=0.9, '
        'application/json;q=0.8, '
        'text/plain;q=0.7';
  }

  /// The `X-Caelo-Capabilities` header, or null when there is nothing beyond
  /// AmneziaWG to say — the header's absence is what every server has seen
  /// until now, and means exactly that.
  static String? header(CoreCapabilities capabilities) {
    if (!_runsMore(capabilities)) return null;
    final sorted = capabilities.variants.toList()..sort();
    return [subscriptionV2, ...sorted].join(', ');
  }

  static bool _runsMore(CoreCapabilities capabilities) =>
      capabilities.protocols.any((protocol) => protocol != 'amneziawg');

  static const caeloMediaType = caeloDocumentType;
}
