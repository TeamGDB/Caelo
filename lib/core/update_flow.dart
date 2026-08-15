import 'dart:io';

import 'package:flutter/foundation.dart';

import 'android_installer.dart';
import 'desktop_updater.dart';
import 'update_check.dart';
import 'update_download.dart';

/// Where an update attempt has got to.
///
/// A state rather than a sequence of callbacks because the interface has to
/// render each of these, including the ones nobody plans for: no permission,
/// and a file that turned out not to be ours.
enum UpdateStage {
  idle,
  checking,

  /// Nothing newer. Worth showing: a check that says nothing looks like a check
  /// that did not happen, and people press it again.
  current,

  found,
  downloading,

  /// The system installer has been asked to take over. Nothing further is known
  /// — whether it installs is between the person and Android.
  handedOver,

  /// Android will not let Caelo start an installation. Asked before downloading
  /// rather than after: tens of megabytes and then a refusal is a poor way to
  /// discover a permission.
  needsPermission,

  failed,
}

/// Drives checking, downloading and installing on the platforms that do it
/// themselves.
///
/// macOS is not one of them: Sparkle owns that flow, window and all, and this
/// defers to it rather than reimplementing a worse one. What remains here is
/// Android, and Windows once there is a machine to try it on.
class UpdateFlow extends ChangeNotifier {
  UpdateFlow({
    Future<AvailableUpdate?> Function()? look,
    Future<File> Function(AvailableUpdate, void Function(double))? fetch,
    Future<bool> Function()? canInstall,
    Future<void> Function(String)? install,
  }) : _look = look ?? UpdateCheck.look,
       _fetch = fetch ?? _defaultFetch,
       _canInstall = canInstall ?? AndroidInstaller.canInstall,
       _install = install ?? AndroidInstaller.install;

  final Future<AvailableUpdate?> Function() _look;
  final Future<File> Function(AvailableUpdate, void Function(double)) _fetch;
  final Future<bool> Function() _canInstall;
  final Future<void> Function(String) _install;

  UpdateStage stage = UpdateStage.idle;

  /// Set synchronously on entry, unlike [stage].
  ///
  /// Guarding on the stage alone let a second press through: the stage does not
  /// become `downloading` until after the permission has been asked about, and
  /// two taps inside that await started two downloads of the same file.
  bool _busy = false;
  AvailableUpdate? available;
  double progress = 0;
  DownloadFailure? failure;

  /// Whether this platform installs its own updates through this flow.
  ///
  /// macOS is excluded although it updates itself, because Sparkle does it. A
  /// second path on the same platform would mean two things able to replace the
  /// application, which is one more than anything needs.
  static bool get isSupported =>
      AndroidInstaller.isSupported && !DesktopUpdater.isSupported;

  void _to(UpdateStage next) {
    stage = next;
    notifyListeners();
  }

  Future<void> check() async {
    if (_busy) return;
    _busy = true;
    _to(UpdateStage.checking);

    try {
      final found = await _look();
      available = found;
      _to(found == null ? UpdateStage.current : UpdateStage.found);
    } finally {
      _busy = false;
    }
  }

  Future<void> download() async {
    final update = available;
    if (update == null || _busy) return;
    _busy = true;

    try {
      // Before the download, not after. This is the whole reason the permission
      // is a state of its own rather than an error at the end.
      if (!await _canInstall()) {
        _to(UpdateStage.needsPermission);
        return;
      }

      progress = 0;
      _to(UpdateStage.downloading);

      final file = await _fetch(update, (value) {
        progress = value;
        notifyListeners();
      });
      // Verification happened inside the fetch. Reaching here means the file is
      // signed by a key this build trusts, and only then is the installer told
      // about it.
      await _install(file.path);
      _to(UpdateStage.handedOver);
    } on DownloadFailed catch (error) {
      failure = error.reason;
      _to(UpdateStage.failed);
    } on Object {
      failure = DownloadFailure.unreachable;
      _to(UpdateStage.failed);
    } finally {
      _busy = false;
    }
  }

  void dismiss() {
    available = null;
    failure = null;
    progress = 0;
    _to(UpdateStage.idle);
  }

  static Future<File> _defaultFetch(
    AvailableUpdate update,
    void Function(double) onProgress,
  ) => UpdateDownload.fetch(update, onProgress: onProgress);
}
