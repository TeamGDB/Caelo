import 'dart:io';

import 'package:flutter/foundation.dart';

import 'diagnostics.dart';
import 'update_check.dart';
import 'update_download.dart';

/// Applies an update on Windows.
///
/// Ours rather than WinSparkle, and not for lack of trying to reuse it: its API
/// takes a single public key, `win_sparkle_set_eddsa_public_key`, with no list
/// form. Windows builds carry no Authenticode signature either, so that one key
/// would be the only thing standing between somebody and a substituted
/// installer — and losing it would end updates for every Windows installation,
/// permanently. That is precisely what the trusted set exists to prevent, and it
/// cannot be expressed through WinSparkle.
///
/// macOS keeps Sparkle, where the fallback to Developer ID with a matching team
/// makes a single key survivable. Here we do the work: fetch, verify against
/// every trusted key, hand over.
abstract final class WindowsUpdater {
  @visibleForTesting
  static bool Function() isWindows = () => Platform.isWindows;

  static bool get isSupported => isWindows();

  /// Whether an update can be installed without asking for anything first.
  ///
  /// Always, on Windows. It exists to match the shape Android needs, where the
  /// answer is a permission somebody may have refused; here the equivalent
  /// moment is the installer's own elevation prompt, which comes later and is
  /// not ours to ask for.
  static Future<bool> canInstall() async => isSupported;

  /// Downloads the update, proves it is ours, and starts the installer.
  ///
  /// Quits once the installer has been started, without waiting for the
  /// installation. What happens next is between the person and Windows: the
  /// installer asks for administrator rights because it registers a service, and
  /// declining that is a legitimate answer this cannot see.
  ///
  /// Quitting releases the application's mutex so the installer can replace
  /// caelo.exe.
  static Future<void> apply(
    AvailableUpdate update, {
    void Function(double)? onProgress,
    Future<void> Function(String path, List<String> arguments)? start,
    void Function()? leave,
  }) async {
    if (!isSupported) return;

    // Verification happens inside fetch, before this ever sees a path. Written
    // as one call rather than download-then-check so that no future edit can
    // reorder them: a file the installer has been given may already be running.
    final file = await UpdateDownload.fetch(update, onProgress: onProgress);
    await install(file.path, start: start, leave: leave);
  }

  /// Starts the installer for a file that has already been verified.
  ///
  /// Separate from [apply] because UpdateFlow downloads and hands over as two
  /// steps, and reports them differently: a download that failed sends somebody
  /// somewhere other than an installer that refused (#71).
  static Future<void> install(
    String path, {
    Future<void> Function(String path, List<String> arguments)? start,
    void Function()? leave,
  }) async {
    if (!isSupported) return;
    Diagnostics.record('starting the installer');
    await (start ?? _start)(path, installerArguments);
    // Out of the installer's way: it replaces this executable, and the
    // installer starts the new one when it is done (#152).
    (leave ?? () => exit(0))();
  }

  /// How the installer is run for an update (#152).
  ///
  /// Silent: no wizard pages, a progress bar only. The elevation prompt stays,
  /// because the installer registers a privileged service and Windows asks
  /// for that whatever the flags; it is still the moment to refuse. No
  /// message boxes, no reboot, and whatever of Caelo is still running is
  /// closed rather than asked about.
  static const installerArguments = [
    '/SILENT',
    '/SUPPRESSMSGBOXES',
    '/NORESTART',
    '/CLOSEAPPLICATIONS',
  ];

  static Future<void> _start(String path, List<String> arguments) async {
    // Detached: this process is about to leave, and the installer outlives it.
    await Process.start(
      path,
      arguments,
      runInShell: false,
      mode: ProcessStartMode.detached,
    );
  }
}
