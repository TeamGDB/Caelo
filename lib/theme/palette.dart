import 'package:flutter/widgets.dart';

/// Caelo's colour tokens.
///
/// The palette is dark only, and deliberately so: the app is a single screen
/// that is mostly black with one thing glowing on it. A light variant would
/// dilute that without making anything easier to use.
///
/// The neutrals are a near-black ramp rather than greys — surfaces separate by
/// a few points of luminance, not by outlines. Only one hue carries meaning:
/// [accent] means the tunnel is up. Nothing else in the interface is allowed
/// to be that colour.
abstract final class CaeloColors {
  /// The page itself. Not a dark grey — actual black.
  static const background = Color(0xFF000000);

  /// Raised surfaces, darkest to lightest. Cards sit on [ink900]; a control
  /// resting on a card sits on [ink800]; [ink500] is a hairline border, never
  /// a fill.
  static const ink900 = Color(0xFF0B0B0B);
  static const ink850 = Color(0xFF0E0E0E);
  static const ink800 = Color(0xFF141414);
  static const ink700 = Color(0xFF1C1C1C);
  static const ink600 = Color(0xFF242424);
  static const ink500 = Color(0xFF2E2E2E);

  /// Primary text.
  static const foreground = Color(0xFFFAFAFA);

  /// Secondary text — labels, captions, the line under the status.
  static const muted = Color(0xFF7C7C7C);

  /// Tertiary text — present but not asking to be read.
  static const dim = Color(0xFF5A5A5A);

  /// Connected. The only saturated colour in the app.
  static const accent = Color(0xFF5DCAA5);

  /// A wash of [accent] dark enough to carry [foreground] text.
  static const accentSurface = Color(0xFF0F2018);

  /// Border for surfaces filled with [accentSurface].
  static const accentBorder = Color(0xFF1F4438);

  /// Failure. Used for the status line and nothing decorative.
  static const danger = Color(0xFFE0605C);
  static const dangerSurface = Color(0xFF200F0F);
  static const dangerBorder = Color(0xFF4A2020);
}

/// Corner radii. Three values, and there is no fourth.
abstract final class CaeloRadius {
  static const small = Radius.circular(4);
  static const medium = Radius.circular(8);

  static const smallAll = BorderRadius.all(small);
  static const mediumAll = BorderRadius.all(medium);
}

/// Spacing step. Everything is a multiple of 4.
abstract final class CaeloSpace {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 16.0;
  static const lg = 24.0;
  static const xl = 40.0;
}
