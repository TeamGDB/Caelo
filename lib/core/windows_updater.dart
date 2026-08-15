import 'dart:io';

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
  static bool get isSupported => Platform.isWindows;

  /// Whether an update can be installed without asking for anything first.
  ///
  /// Always, on Windows. It exists to match the shape Android needs, where the
  /// answer is a permission somebody may have refused; here the equivalent
  /// moment is the installer's own elevation prompt, which comes later and is
  /// not ours to ask for.
  static Future<bool> canInstall() async => isSupported;

  /// Downloads the update, proves it is ours, and starts the installer.
  ///
  /// Returns once the installer has been started, not once anything is
  /// installed. What happens next is between the person and Windows: the
  /// installer asks for administrator rights because it registers a service, and
  /// declining that is a legitimate answer this cannot see.
  ///
  /// The application is expected to quit shortly afterwards. It holds a mutex
  /// the installer waits on, and until it lets go the installer cannot replace
  /// a running caelo.exe.
  static Future<void> apply(
    AvailableUpdate update, {
    void Function(double)? onProgress,
    Future<ProcessResult> Function(String path)? start,
  }) async {
    if (!isSupported) return;

    // Verification happens inside fetch, before this ever sees a path. Written
    // as one call rather than download-then-check so that no future edit can
    // reorder them: a file the installer has been given may already be running.
    final file = await UpdateDownload.fetch(update, onProgress: onProgress);
    await install(file.path, start: start);
  }

  /// Starts the installer for a file that has already been verified.
  ///
  /// Separate from [apply] because UpdateFlow downloads and hands over as two
  /// steps, and reports them differently: a download that failed sends somebody
  /// somewhere other than an installer that refused (#71).
  static Future<void> install(
    String path, {
    Future<ProcessResult> Function(String path)? start,
  }) async {
    if (!isSupported) return;
    Diagnostics.record('starting the installer');
    await (start ?? _start)(path);
  }

  static Future<ProcessResult> _start(String path) {
    // No arguments: the installer is interactive on purpose. A silent upgrade
    // of a VPN client that registers a privileged service is not something to
    // do behind somebody's back, and the elevation prompt is the one moment
    // Windows gives them to refuse.
    //
    // Started detached, because this process is about to be replaced by the
    // thing it just started.
    return Process.run(path, const [], runInShell: false);
  }
}
