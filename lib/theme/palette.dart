import 'package:flutter/widgets.dart';

/// Caelo's colour tokens, in both schemes.
///
/// Surfaces are numbered by distance from the page rather than by darkness:
/// [surface1] is what sits directly on the background, [surface2] is what sits
/// on that. In the dark scheme the ramp climbs; in the light one it descends
/// towards white. Naming it after the position rather than the value is what
/// lets one set of widgets serve both.
///
/// Only one hue carries meaning: [accent] means the tunnel is up. Nothing else
/// in the interface is allowed to be that colour.
@immutable
class CaeloPalette {
  const CaeloPalette({
    required this.brightness,
    required this.background,
    required this.surface1,
    required this.surface2,
    required this.surface3,
    required this.surface4,
    required this.border,
    required this.foreground,
    required this.muted,
    required this.dim,
    required this.accent,
    required this.accentSurface,
    required this.accentBorder,
    required this.danger,
    required this.dangerSurface,
    required this.dangerBorder,
  });

  final Brightness brightness;

  /// The page itself.
  final Color background;

  /// Raised surfaces, nearest the page first. A card sits on [surface1]; a
  /// control resting on that card sits on [surface2].
  final Color surface1;
  final Color surface2;
  final Color surface3;
  final Color surface4;

  /// Hairlines. Never a fill.
  final Color border;

  /// Primary text.
  final Color foreground;

  /// Secondary text — labels, captions, the line under the status.
  final Color muted;

  /// Tertiary text — present, but not asking to be read.
  final Color dim;

  /// Connected.
  final Color accent;

  /// A wash of [accent] quiet enough to carry [foreground] text.
  final Color accentSurface;
  final Color accentBorder;

  /// Failure. Used for the status line and nothing decorative.
  final Color danger;
  final Color dangerSurface;
  final Color dangerBorder;

  /// The dark scheme.
  static const dark = CaeloPalette(
    brightness: Brightness.dark,
    background: Color(0xFF090B0E),
    surface1: Color(0xFF13161B),
    surface2: Color(0xFF1C2026),
    surface3: Color(0xFF232830),
    surface4: Color(0xFF2C323B),
    border: Color(0xFF3D434D),
    foreground: Color(0xFFF0F2F4),
    muted: Color(0xFFAEB4BD),
    dim: Color(0xFF6E757F),
    accent: Color(0xFF54C69A),
    accentSurface: Color(0xFF0E211B),
    accentBorder: Color(0xFF235141),
    danger: Color(0xFFFFB4AB),
    dangerSurface: Color(0xFF2A1512),
    dangerBorder: Color(0xFF5C2A24),
  );

  /// The light scheme.
  ///
  /// The page is tinted and the cards are near-white, which is the opposite of
  /// the dark scheme's arrangement and deliberate: on a light background,
  /// raising a surface means moving it towards white, not away from it.
  static const light = CaeloPalette(
    brightness: Brightness.light,
    background: Color(0xFFD7E7E1),
    surface1: Color(0xFFF7F8F6),
    surface2: Color(0xFFE3EFEB),
    surface3: Color(0xFFD2E0DB),
    surface4: Color(0xFFC2D3CD),
    border: Color(0xFFB3C7C1),
    foreground: Color(0xFF0A3735),
    muted: Color(0xFF496964),
    dim: Color(0xFF6B8781),
    accent: Color(0xFF2FA982),
    accentSurface: Color(0xFFDCF0E7),
    accentBorder: Color(0xFFA9D9C6),
    danger: Color(0xFFB3261E),
    dangerSurface: Color(0xFFF9DEDC),
    dangerBorder: Color(0xFFE6B4B0),
  );
}

/// Which scheme to use.
enum CaeloThemeMode {
  system,
  light,
  dark;

  CaeloPalette resolve(Brightness platform) => switch (this) {
    CaeloThemeMode.light => CaeloPalette.light,
    CaeloThemeMode.dark => CaeloPalette.dark,
    CaeloThemeMode.system =>
      platform == Brightness.light ? CaeloPalette.light : CaeloPalette.dark,
  };
}

/// Makes the resolved palette available to the widgets below it.
class CaeloColors extends InheritedWidget {
  const CaeloColors({required this.palette, required super.child, super.key});

  final CaeloPalette palette;

  static CaeloPalette of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<CaeloColors>();
    // Falling back to dark rather than throwing: a widget rendered outside the
    // app shell — a test, a preview — should still draw.
    return scope?.palette ?? CaeloPalette.dark;
  }

  @override
  bool updateShouldNotify(CaeloColors oldWidget) =>
      palette.brightness != oldWidget.palette.brightness;
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
