import 'package:flutter/cupertino.dart';

import 'palette.dart';

/// The Cupertino theme and type scale, resolved against a [CaeloPalette].
///
/// Typography is the platform's own — SF on Apple systems, whatever Cupertino
/// falls back to elsewhere. Caelo ships no font of its own: the interface is
/// meant to look like it came with the operating system, and a bundled typeface
/// would work against that as well as adding a megabyte to a binary people
/// download over a censored connection.
///
/// The sizes come from the Android prototype's scale, which was built against
/// real screens. Cupertino widgets sit slightly tighter than Material ones, so
/// the steps are kept and the leading is not.
abstract final class CaeloTheme {
  static CupertinoThemeData data(CaeloPalette palette) => CupertinoThemeData(
    brightness: palette.brightness,
    primaryColor: palette.accent,
    primaryContrastingColor: palette.background,
    scaffoldBackgroundColor: palette.background,
    barBackgroundColor: palette.surface1,
    applyThemeToAll: true,
    textTheme: CupertinoTextThemeData(
      primaryColor: palette.accent,
      textStyle: TextStyle(
        color: palette.foreground,
        fontSize: 15,
        letterSpacing: -0.2,
      ),
      navTitleTextStyle: TextStyle(
        color: palette.foreground,
        fontSize: 17,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.3,
      ),
      navLargeTitleTextStyle: TextStyle(
        color: palette.foreground,
        fontSize: 30,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.4,
      ),
      actionTextStyle: TextStyle(color: palette.accent, fontSize: 16),
    ),
  );

  /// The connection status, set large and tight under the button.
  static TextStyle status(CaeloPalette palette) => TextStyle(
    color: palette.foreground,
    fontSize: 21,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.4,
  );

  /// The line under the status: which node, which protocol, what latency.
  static TextStyle caption(CaeloPalette palette) =>
      TextStyle(color: palette.muted, fontSize: 13, letterSpacing: -0.1);

  /// Section headers in settings.
  static TextStyle sectionHeader(CaeloPalette palette) => TextStyle(
    color: palette.dim,
    fontSize: 11,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.6,
  );

  /// Values on the right-hand side of a settings row.
  static TextStyle rowValue(CaeloPalette palette) =>
      TextStyle(color: palette.muted, fontSize: 15);

  /// Row labels and anything else that reads as body copy.
  static TextStyle body(CaeloPalette palette) =>
      TextStyle(color: palette.foreground, fontSize: 16);
}
