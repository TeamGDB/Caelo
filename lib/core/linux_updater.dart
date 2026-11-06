import 'dart:io';

import 'package:flutter/foundation.dart';

import 'diagnostics.dart';

/// Which package manager installed this copy, if one did and can update it.
enum LinuxPackageManager { apt, dnf }

/// Updating on Linux by asking the package manager to do it (#150).
///
/// docs/updates.md rules out the app replacing files that belong to apt or
/// dnf, and that rule stands: nothing here downloads or writes a package. The
/// button runs the package manager's own upgrade of the one package, through
/// the system's password prompt, exactly what `sudo apt upgrade` would do for
/// it, and then restarts the app. The tunnel is held by the privileged
/// service meanwhile and is adopted again by the restarted app.
///
/// Only for a copy installed from the deb or the rpm with the Caelo
/// repository configured. An AppImage or the tarball keeps the notice.
abstract final class LinuxUpdater {
  static const installedAt = '/opt/caelo/';
  static const aptSource = '/etc/apt/sources.list.d/caelo.list';
  static const dnfRepo = '/etc/yum.repos.d/caelo.repo';

  /// Seams for tests: what exists on disk and on PATH, and where this
  /// process runs from.
  @visibleForTesting
  static bool Function(String path) exists = _exists;
  @visibleForTesting
  static String Function() executable = () => Platform.resolvedExecutable;
  @visibleForTesting
  static bool Function() isLinux = () => Platform.isLinux;
  @visibleForTesting
  static Future<ProcessResult> Function(String, List<String>) run = Process.run;

  static bool _exists(String path) => File(path).existsSync();

  static bool _onPath(String tool) =>
      ['/usr/bin/$tool', '/bin/$tool', '/usr/local/bin/$tool'].any(exists);

  /// The package manager to ask, or null when this copy is not one it owns.
  static LinuxPackageManager? get packageManager {
    if (!isLinux()) return null;
    if (!executable().startsWith(installedAt)) return null;
    if (!_onPath('pkexec')) return null;
    if (exists(aptSource) && _onPath('apt-get')) return LinuxPackageManager.apt;
    if (exists(dnfRepo) && _onPath('dnf')) return LinuxPackageManager.dnf;
    return null;
  }

  static bool get isSupported => packageManager != null;

  /// What the system is asked to run, as root, through pkexec.
  ///
  /// apt refreshes only the Caelo source, so an update does not wait on every
  /// mirror the machine knows, and upgrades only this package; it never
  /// installs it where it is absent. dnf does the same by naming the package.
  @visibleForTesting
  static List<String> commandFor(LinuxPackageManager manager) =>
      switch (manager) {
        LinuxPackageManager.apt => [
          '/bin/sh',
          '-c',
          'apt-get update'
              ' -o Dir::Etc::sourcelist=$aptSource'
              ' -o Dir::Etc::sourceparts=-'
              ' -o APT::Get::List-Cleanup=0'
              ' && DEBIAN_FRONTEND=noninteractive'
              ' apt-get install -y --only-upgrade caelo',
        ],
        LinuxPackageManager.dnf => [
          'dnf',
          '-y',
          'upgrade',
          '--refresh',
          'caelo',
        ],
      };

  /// Upgrades the package. Throws when it did not happen: the password
  /// prompt was dismissed (pkexec answers 126), or the package manager
  /// failed; [LinuxUpdateFailed.declined] tells the two apart.
  static Future<void> install() async {
    final manager = packageManager;
    if (manager == null) {
      throw const LinuxUpdateFailed(declined: false);
    }
    Diagnostics.record('asking ${manager.name} to upgrade caelo');
    final result = await run('pkexec', commandFor(manager));
    if (result.exitCode == 0) {
      Diagnostics.record('upgraded by ${manager.name}');
      return;
    }
    Diagnostics.record(
      'upgrade did not happen: ${manager.name} exited ${result.exitCode}',
    );
    throw LinuxUpdateFailed(declined: result.exitCode == 126);
  }

  /// Starts the upgraded app and leaves. The tunnel stays with the service.
  static Future<void> relaunch() async {
    await Process.start(
      '${installedAt}caelo',
      const [],
      mode: ProcessStartMode.detached,
    );
    exit(0);
  }
}

class LinuxUpdateFailed implements Exception {
  const LinuxUpdateFailed({required this.declined});

  /// The password prompt was dismissed: nothing is wrong.
  final bool declined;

  @override
  String toString() =>
      declined ? 'the password prompt was dismissed' : 'the upgrade failed';
}
