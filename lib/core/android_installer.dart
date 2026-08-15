import 'dart:io';

import 'package:flutter/services.dart';

/// Hands a verified file to Android's package installer.
///
/// Only the handing over. The file is fetched and checked by [UpdateDownload]
/// first, and that order is the point: once the installer has a file, it may
/// already be running it.
///
/// Android refuses an update signed with a different key than the installed copy
/// regardless of anything here. That protection is welcome and is not what this
/// relies on — it arrives as an opaque failure after the whole download, whereas
/// our own check happens before and can say what went wrong.
abstract final class AndroidInstaller {
  static const _channel = MethodChannel('team.gdb.caelo/installer');

  static bool get isSupported => Platform.isAndroid;

  /// Whether the system will let Caelo start an installation at all.
  ///
  /// Since Android 8 this is granted per application in Settings rather than at
  /// install time, so it can be absent on a device that installed Caelo happily.
  /// Asked before downloading: forty megabytes and then a refusal is a poor way
  /// to discover a permission.
  static Future<bool> canInstall() async {
    if (!isSupported) return false;
    return await _channel.invokeMethod<bool>('canInstall') ?? false;
  }

  /// Opens the one Settings screen that grants it.
  static Future<void> requestPermission() async {
    if (!isSupported) return;
    await _channel.invokeMethod<void>('requestPermission');
  }

  /// Shows the system's install prompt for [path].
  ///
  /// Returns once the prompt has been raised, not once anything is installed:
  /// what happens next is between the person and the system, and Caelo is not
  /// told the outcome. It will find out the ordinary way, by being restarted as
  /// a newer build or not.
  static Future<void> install(String path) async {
    if (!isSupported) return;
    await _channel.invokeMethod<void>('install', path);
  }
}
