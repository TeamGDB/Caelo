import 'dart:io';

import 'package:flutter/services.dart';

/// Keeps the desktop window's chrome in step with the palette.
///
/// The title bar is transparent and the content runs up behind the traffic
/// lights, so the window's own appearance has to match what Flutter is
/// painting. It cannot simply follow the system: the app's scheme does not, and
/// a dark title bar over a light window reads as a bug rather than a setting.
abstract final class WindowChrome {
  static const _channel = MethodChannel('team.gdb.caelo/window');

  static Brightness? _applied;

  /// Cheap to call on every build — it only crosses the channel when the
  /// answer has actually changed.
  static void setBrightness(Brightness brightness) {
    if (!Platform.isMacOS || _applied == brightness) return;
    _applied = brightness;

    // Nothing to do if the platform side is not listening: the window simply
    // keeps the appearance it started with, which is not worth an error.
    _channel
        .invokeMethod<void>(
          'setBrightness',
          brightness == Brightness.light ? 'light' : 'dark',
        )
        .catchError((_) {});
  }
}
