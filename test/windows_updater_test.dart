import 'dart:async';
import 'dart:io';

import 'package:caelo/core/update_check.dart';
import 'package:caelo/core/update_download.dart';
import 'package:caelo/core/windows_updater.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('handing over to the Windows installer', () {
    setUp(() => WindowsUpdater.isWindows = () => true);
    tearDown(() => WindowsUpdater.isWindows = () => Platform.isWindows);

    test('runs silently and leaves only after the installer starts', () async {
      const path = r'C:\Users\Someone\Downloads\Caelo setup.exe';
      final started = Completer<void>();
      final events = <String>[];
      final installing = WindowsUpdater.install(
        path,
        start: (file, arguments) {
          expect(file, path);
          expect(arguments, [
            '/SILENT',
            '/SUPPRESSMSGBOXES',
            '/NORESTART',
            '/CLOSEAPPLICATIONS',
          ]);
          events.add('starting');
          return started.future;
        },
        leave: () => events.add('leave'),
      );

      expect(events, ['starting']);
      started.complete();
      await installing;
      expect(events, ['starting', 'leave']);
    });

    test('keeps the app open when the installer cannot start', () async {
      final error = ProcessException('setup.exe', [], 'cannot start');
      var left = false;

      await expectLater(
        WindowsUpdater.install(
          'setup.exe',
          start: (_, _) async => throw error,
          leave: () => left = true,
        ),
        throwsA(same(error)),
      );
      expect(left, isFalse);
    });

    test('does not launch or leave on other platforms', () async {
      WindowsUpdater.isWindows = () => false;
      await WindowsUpdater.install(
        'setup.exe',
        start: (_, _) async => fail('must not launch the installer'),
        leave: () => fail('must not leave'),
      );
    });
  });

  // Not a test of apply(): on a host that is not Windows it returns before doing
  // anything, so calling it here would pass for the wrong reason and read as
  // coverage that does not exist.
  //
  // What is pinned instead is the guard itself, and that a failed download
  // produces no path for an installer to be handed -- the ordering property
  // apply() depends on. The actual installer still needs Windows; see #22.
  test('a failed download yields no file for the installer', () async {
    final directory = await Directory.systemTemp.createTemp('caelo-win-test-');
    addTearDown(() => directory.delete(recursive: true));
    UpdateDownload.file = (name) async => File('${directory.path}/$name');
    addTearDown(() => UpdateDownload.file = (name) async => File(name));

    var started = false;

    // On a host that is not Windows apply() returns before doing anything,
    // which would make this pass for the wrong reason. So the guard is asserted
    // rather than assumed, and the real path is exercised through fetch().
    expect(WindowsUpdater.isSupported, Platform.isWindows);

    await expectLater(
      UpdateDownload.fetch(
        const AvailableUpdate(
          version: '9.9.9',
          build: 999,
          url: 'http://127.0.0.1:1/never',
          sizeBytes: 10,
          sha256: '',
          signature: '',
          notesUrl: '',
        ),
        verify: (_, _) async {
          started = true;
          return false;
        },
      ),
      throwsA(isA<DownloadFailed>()),
    );

    // The unreachable address means it never reached verification either, which
    // is the point: a failed download must not produce a path at all.
    expect(started, isFalse);
    expect(directory.listSync(), isEmpty);
  });
}
