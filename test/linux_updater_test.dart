import 'dart:io';

import 'package:caelo/core/linux_updater.dart';
import 'package:caelo/core/update_check.dart';
import 'package:caelo/core/update_flow.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Set<String> files;
  late String exe;
  late List<List<String>> ran;
  late int exitCode;

  setUp(() {
    files = {'/usr/bin/pkexec', '/usr/bin/apt-get', LinuxUpdater.aptSource};
    exe = '/opt/caelo/caelo';
    ran = [];
    exitCode = 0;
    LinuxUpdater.isLinux = () => true;
    LinuxUpdater.exists = files.contains;
    LinuxUpdater.executable = () => exe;
    LinuxUpdater.run = (program, args) async {
      ran.add([program, ...args]);
      return ProcessResult(0, exitCode, '', '');
    };
  });

  tearDown(() {
    LinuxUpdater.isLinux = () => Platform.isLinux;
    LinuxUpdater.exists = (path) => File(path).existsSync();
    LinuxUpdater.executable = () => Platform.resolvedExecutable;
    LinuxUpdater.run = Process.run;
  });

  group('who can update this copy (#150)', () {
    test('a deb with the Caelo source: apt', () {
      expect(LinuxUpdater.packageManager, LinuxPackageManager.apt);
    });

    test('an rpm with the Caelo repo: dnf', () {
      files
        ..remove(LinuxUpdater.aptSource)
        ..remove('/usr/bin/apt-get')
        ..addAll({LinuxUpdater.dnfRepo, '/usr/bin/dnf'});
      expect(LinuxUpdater.packageManager, LinuxPackageManager.dnf);
    });

    test('an AppImage or the tarball, run from elsewhere: nobody', () {
      exe = '/home/me/Caelo.AppImage';
      expect(LinuxUpdater.isSupported, isFalse);
    });

    test('without the password prompt: nobody', () {
      files.remove('/usr/bin/pkexec');
      expect(LinuxUpdater.isSupported, isFalse);
    });

    test('without the Caelo source the package manager has nothing to '
        'fetch from: nobody', () {
      files.remove(LinuxUpdater.aptSource);
      expect(LinuxUpdater.isSupported, isFalse);
    });
  });

  group('asking it', () {
    test('apt refreshes only the Caelo source and upgrades only caelo', () {
      final command = LinuxUpdater.commandFor(LinuxPackageManager.apt);
      expect(command.take(2), ['/bin/sh', '-c']);
      expect(command.last, contains('sourcelist=${LinuxUpdater.aptSource}'));
      expect(command.last, contains('install -y --only-upgrade caelo'));
    });

    test('through pkexec', () async {
      await LinuxUpdater.install();
      expect(ran.single.first, 'pkexec');
    });

    test('a dismissed password prompt is a choice, not a failure', () async {
      exitCode = 126;
      expect(
        LinuxUpdater.install,
        throwsA(
          isA<LinuxUpdateFailed>().having((e) => e.declined, 'declined', true),
        ),
      );
    });

    test('a failed upgrade says so', () async {
      exitCode = 100;
      expect(
        LinuxUpdater.install,
        throwsA(
          isA<LinuxUpdateFailed>().having((e) => e.declined, 'declined', false),
        ),
      );
    });
  });

  group('the flow without a download', () {
    AvailableUpdate update() => AvailableUpdate(
      version: '0.3.7',
      build: 21,
      url: 'https://example.invalid/x',
      sizeBytes: 1,
      sha256: 'a' * 64,
      signature: 'c2ln',
      notesUrl: 'https://example.invalid/notes',
    );

    UpdateFlow flow(Future<void> Function(String) install) => UpdateFlow(
      look: () async => update(),
      fetch: (_, _) async => throw StateError('nothing to download'),
      canInstall: () async => true,
      install: install,
      readPending: () async => null,
      writePending: (_) async {},
      needsDownload: false,
    );

    test('found, then the package manager installs it', () async {
      final stages = <UpdateStage>[];
      final f = flow((_) async {});
      f.addListener(() => stages.add(f.stage));
      await f.check();
      await f.download();
      expect(
        stages,
        containsAllInOrder([
          UpdateStage.found,
          UpdateStage.installing,
          UpdateStage.handedOver,
        ]),
      );
    });

    test('a dismissed prompt goes back to rest without an error', () async {
      final f = flow(
        (_) async => throw const LinuxUpdateFailed(declined: true),
      );
      await f.check();
      await f.download();
      expect(f.stage, UpdateStage.idle);
    });

    test('a failed upgrade is reported', () async {
      final f = flow(
        (_) async => throw const LinuxUpdateFailed(declined: false),
      );
      await f.check();
      await f.download();
      expect(f.stage, UpdateStage.handOverFailed);
    });
  });
}
