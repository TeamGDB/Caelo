import 'package:flutter/cupertino.dart';

import 'palette.dart';

/// The Cupertino theme, assembled from [CaeloColors].
///
/// Typography is the platform's own — SF on Apple systems, whatever Cupertino
/// falls back to elsewhere. Caelo ships no font of its own: the interface is
/// meant to look like it came with the operating system, and a bundled
/// typeface would work against that as well as adding a megabyte to a binary
/// people download over a censored connection.
abstract final class CaeloTheme {
  static CupertinoThemeData get data => const CupertinoThemeData(
    brightness: Brightness.dark,
    primaryColor: CaeloColors.accent,
    primaryContrastingColor: CaeloColors.background,
    scaffoldBackgroundColor: CaeloColors.background,
    barBackgroundColor: CaeloColors.ink900,
    applyThemeToAll: true,
    textTheme: CupertinoTextThemeData(
      primaryColor: CaeloColors.accent,
      textStyle: TextStyle(
        color: CaeloColors.foreground,
        fontSize: 15,
        letterSpacing: -0.2,
      ),
      navTitleTextStyle: TextStyle(
        color: CaeloColors.foreground,
        fontSize: 16,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.3,
      ),
      navLargeTitleTextStyle: TextStyle(
        color: CaeloColors.foreground,
        fontSize: 32,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.8,
      ),
      actionTextStyle: TextStyle(color: CaeloColors.accent, fontSize: 15),
    ),
  );

  /// The connection status, set large and tight under the button.
  static const status = TextStyle(
    color: CaeloColors.foreground,
    fontSize: 22,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.5,
  );

  /// The line under the status: which node, which protocol, what latency.
  static const caption = TextStyle(
    color: CaeloColors.muted,
    fontSize: 13,
    letterSpacing: -0.1,
  );

  /// Section headers in settings.
  static const sectionHeader = TextStyle(
    color: CaeloColors.dim,
    fontSize: 11,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.6,
  );

  /// Values on the right-hand side of a settings row.
  static const rowValue = TextStyle(color: CaeloColors.muted, fontSize: 14);
}
