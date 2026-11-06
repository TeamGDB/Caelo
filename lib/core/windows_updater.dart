import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'app_storage.dart';
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
  static const _channel = MethodChannel('team.gdb.caelo/windows_updates');
  static const installerLogName = 'windows-installer.log';

  @visibleForTesting
  static bool Function() isWindows = () => Platform.isWindows;

  @visibleForTesting
  static Future<Process> Function(String, List<String>) launch = _launch;

  @visibleForTesting
  static Duration readyTimeout = const Duration(minutes: 5);

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
  /// Quits only after the elevated installer signals that it is ready. A
  /// cancelled UAC prompt or a failure before that keeps the application open.
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
    try {
      await (start ?? _start)(path, installerArguments);
    } on PlatformException catch (error) {
      // The loader cannot distinguish a declined UAC prompt from an early
      // setup exit. Neither means the download failed or that the user erred.
      if (error.code == 'installer_stopped') {
        throw const WindowsInstallerStopped();
      }
      rethrow;
    }
    // The installer has passed UAC and now waits for our mutex to disappear.
    // Only then can it replace the executable and start the new app (#152).
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
    final log = await AppStorage.file(installerLogName);
    final event = await _channel.invokeMethod<String>('prepare');
    if (event == null) throw StateError('no installer handover event');
    try {
      // The loader starts without elevation so Inno Setup retains the original
      // user for relaunch. Its elevated child acknowledges us after UAC.
      final process = await launch(path, [
        ...arguments,
        '/LOG=${log.absolute.path}',
        '/CAELOUPDATE=$event',
      ]);
      final elapsed = Stopwatch()..start();
      while (true) {
        if (elapsed.elapsed >= readyTimeout) {
          throw TimeoutException('the installer did not become ready');
        }
        if (await _channel.invokeMethod<bool>('isReady', process.pid) == true) {
          return;
        }
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    } finally {
      await _channel.invokeMethod<void>('release');
    }
  }

  static Future<Process> _launch(String path, List<String> arguments) =>
      Process.start(
        path,
        arguments,
        runInShell: false,
        mode: ProcessStartMode.detached,
      );
}

/// Setup exited before handover, possibly because the user declined UAC.
/// The reason is unknown, so the interface must cover cancellation and failure.
class WindowsInstallerStopped implements Exception {
  const WindowsInstallerStopped();

  @override
  String toString() => 'the installer closed before handover';
}
