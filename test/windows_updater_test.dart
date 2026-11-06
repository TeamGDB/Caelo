import 'dart:async';
import 'dart:io';

import 'package:caelo/core/app_storage.dart';
import 'package:caelo/core/update_check.dart';
import 'package:caelo/core/update_download.dart';
import 'package:caelo/core/windows_updater.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _Installer extends Fake implements Process {
  @override
  int get pid => 42;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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

  group('waiting for the elevated installer', () {
    const channel = MethodChannel('team.gdb.caelo/windows_updates');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final originalLaunch = WindowsUpdater.launch;
    late List<String> events;
    late bool left;
    late Directory directory;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp(
        'caelo installer-test-',
      );
      AppStorage.testDirectory = directory;
      WindowsUpdater.isWindows = () => true;
      events = [];
      left = false;
      WindowsUpdater.launch = (path, arguments) async {
        expect(path, 'setup.exe');
        expect(arguments, [
          ...WindowsUpdater.installerArguments,
          '/LOG=${File('${directory.path}/${WindowsUpdater.installerLogName}').absolute.path}',
          r'/CAELOUPDATE=Local\Caelo.UpdateReady.test',
        ]);
        events.add('launch');
        return _Installer();
      };
    });

    tearDown(() async {
      messenger.setMockMethodCallHandler(channel, null);
      WindowsUpdater.isWindows = () => Platform.isWindows;
      WindowsUpdater.launch = originalLaunch;
      WindowsUpdater.readyTimeout = const Duration(minutes: 5);
      AppStorage.testDirectory = null;
      await directory.delete(recursive: true);
    });

    void handle(Future<bool> Function() ready) {
      messenger.setMockMethodCallHandler(channel, (call) async {
        events.add(call.method);
        switch (call.method) {
          case 'prepare':
            return r'Local\Caelo.UpdateReady.test';
          case 'isReady':
            expect(call.arguments, 42);
            return ready();
          case 'release':
            return null;
          default:
            fail('unexpected method ${call.method}');
        }
      });
    }

    test('creating the process alone does not close the app', () async {
      final queried = Completer<void>();
      final ready = Completer<bool>();
      handle(() {
        queried.complete();
        return ready.future;
      });

      final installing = WindowsUpdater.install(
        'setup.exe',
        leave: () {
          events.add('leave');
          left = true;
        },
      );
      await queried.future;
      expect(left, isFalse);
      ready.complete(true);
      await installing;
      expect(events, ['prepare', 'launch', 'isReady', 'release', 'leave']);
      expect(left, isTrue);
    });

    test('cancelled UAC or early setup failure keeps the app open', () async {
      handle(() async => throw PlatformException(code: 'installer_stopped'));
      await expectLater(
        WindowsUpdater.install('setup.exe', leave: () => left = true),
        throwsA(isA<WindowsInstallerStopped>()),
      );
      expect(left, isFalse);
      expect(events.last, 'release');
    });

    test('a launch failure releases the handover event', () async {
      handle(() async => fail('must not wait for a failed launch'));
      WindowsUpdater.launch = (_, _) async =>
          throw ProcessException('setup.exe', [], 'cannot start');
      await expectLater(
        WindowsUpdater.install('setup.exe', leave: () => left = true),
        throwsA(isA<ProcessException>()),
      );
      expect(events, ['prepare', 'release']);
      expect(left, isFalse);
    });

    test('a missing acknowledgement times out without leaving', () async {
      handle(() async => false);
      WindowsUpdater.readyTimeout = Duration.zero;
      await expectLater(
        WindowsUpdater.install('setup.exe', leave: () => left = true),
        throwsA(isA<TimeoutException>()),
      );
      expect(left, isFalse);
      expect(events, ['prepare', 'launch', 'release']);
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
