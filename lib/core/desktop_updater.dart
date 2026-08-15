import 'dart:io';

import 'package:flutter/services.dart';

import 'diagnostics.dart';
import 'settings_store.dart';

/// The macOS updater, which is Sparkle behind a platform channel.
///
/// Only macOS answers. Windows and Android do their own downloading against the
/// same manifest (#45, #48), because both would otherwise have to trust a single
/// signing key — and on Windows, where the builds carry no Authenticode
/// signature, that key is the only thing standing between somebody and a
/// substituted installer. Linux has a package manager and wants none of this.
abstract final class DesktopUpdater {
  static const _channel = MethodChannel('team.gdb.caelo/updates');

  /// Whether this platform updates itself through Sparkle.
  ///
  /// Deliberately not "is this a desktop": Linux is a desktop and must not.
  static bool get isSupported => Platform.isMacOS;

  /// Hands Sparkle the setting and lets it start, once.
  ///
  /// Told rather than assumed, and told before the updater starts its cycle.
  /// Starting first and disabling afterwards would let exactly one check escape
  /// — from an installation whose owner had turned checking off, which is the
  /// one case the switch exists to prevent.
  static Future<void> start() async {
    if (!isSupported) return;
    await _tell('start', await SettingsStore.updateChecks());
  }

  /// Follows the switch in Settings while the app is running.
  static Future<void> setEnabled(bool on) => _tell('setEnabled', on);

  /// Checks now, showing Sparkle's own window — somebody asked and is waiting to
  /// see something happen. Unlike the scheduled check, this one is allowed to
  /// interrupt.
  static Future<void> checkNow() => _tell('checkNow', null);

  static Future<void> _tell(String method, Object? argument) async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod<void>(method, argument);
    } on Object catch (error) {
      // An updater that cannot be reached is not a reason to fail whatever the
      // person was doing. It is worth recording, because the symptom otherwise
      // is silence for months.
      Diagnostics.record('the updater did not answer', error: error);
    }
  }
}
