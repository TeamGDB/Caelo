import 'dart:io';

import 'package:caelo/core/update_check.dart';
import 'package:caelo/core/update_download.dart';
import 'package:caelo/core/update_flow.dart';
import 'package:caelo/core/windows_updater.dart';
import 'package:flutter_test/flutter_test.dart';

AvailableUpdate get _update => AvailableUpdate(
  version: '0.1.2',
  build: 5,
  url: 'https://example.invalid/Caelo.apk',
  sizeBytes: 1024,
  sha256: 'a' * 64,
  signature: 'c2ln',
  notesUrl: 'https://example.invalid/notes',
);

void main() {
  test('says so when there is nothing newer', () async {
    final flow = UpdateFlow(look: () async => null);
    await flow.check();

    // Not idle. A check that says nothing looks like a check that did not
    // happen, and people press it again.
    expect(flow.stage, UpdateStage.current);
    expect(flow.available, isNull);
  });

  test('offers what it found rather than fetching it', () async {
    var fetched = false;
    final flow = UpdateFlow(
      look: () async => _update,
      fetch: (_, _) async {
        fetched = true;
        return File('unused');
      },
    );
    await flow.check();

    expect(flow.stage, UpdateStage.found);
    expect(flow.available?.version, '0.1.2');
    // Tens of megabytes are not fetched because somebody pressed "check".
    expect(fetched, isFalse);
  });

  // Asked before the download, not after: forty megabytes and then a refusal is
  // a poor way to discover a permission.
  test('asks about permission before spending the bandwidth', () async {
    var fetched = false;
    final flow = UpdateFlow(
      look: () async => _update,
      canInstall: () async => false,
      fetch: (_, _) async {
        fetched = true;
        return File('unused');
      },
    );

    await flow.check();
    await flow.download();

    expect(flow.stage, UpdateStage.needsPermission);
    expect(fetched, isFalse);
  });

  test('reports progress and hands the file over once', () async {
    final seen = <double>[];
    var installed = '';
    final flow = UpdateFlow(
      look: () async => _update,
      canInstall: () async => true,
      fetch: (_, onProgress) async {
        onProgress(0.5);
        onProgress(1);
        return File('/tmp/caelo-update.apk');
      },
      install: (path) async => installed = path,
    );
    flow.addListener(() {
      if (flow.stage == UpdateStage.downloading) seen.add(flow.progress);
    });

    await flow.check();
    await flow.download();

    expect(seen, containsAllInOrder([0.5, 1.0]));
    expect(installed, '/tmp/caelo-update.apk');
    expect(flow.stage, UpdateStage.handedOver);
  });

  // The property the whole thing rests on: a file that failed verification is
  // never handed to the installer, because a file the installer has may already
  // be running.
  test('installs nothing when the download was not ours', () async {
    var installed = false;
    final flow = UpdateFlow(
      look: () async => _update,
      canInstall: () async => true,
      fetch: (_, _) async =>
          throw const DownloadFailed(DownloadFailure.untrusted),
      install: (_) async => installed = true,
    );

    await flow.check();
    await flow.download();

    expect(installed, isFalse);
    expect(flow.stage, UpdateStage.failed);
    expect(flow.failure, DownloadFailure.untrusted);
  });

  test('a second press while downloading does not start another', () async {
    var started = 0;
    final flow = UpdateFlow(
      look: () async => _update,
      canInstall: () async => true,
      fetch: (_, _) async {
        started++;
        await Future<void>.delayed(const Duration(milliseconds: 20));
        return File('/tmp/caelo-update.apk');
      },
      install: (_) async {},
    );

    await flow.check();
    final first = flow.download();
    await flow.download();
    await first;

    expect(started, 1);
  });

  test(
    'an early Windows installer exit has an uncertain, neutral outcome',
    () async {
      var pendingWritten = false;
      final flow = UpdateFlow(
        look: () async => _update,
        fetch: (_, _) async => File('verified.exe'),
        canInstall: () async => true,
        install: (_) async => throw const WindowsInstallerStopped(),
        writePending: (_) async => pendingWritten = true,
      );
      await flow.check();
      await flow.download();

      expect(flow.stage, UpdateStage.installerStopped);
      expect(flow.failure, isNull);
      expect(pendingWritten, isFalse, reason: 'nothing was handed over');
      flow.dismiss();
      expect(flow.stage, UpdateStage.idle);
    },
  );

  test('a process launch error remains a handover failure', () async {
    final flow = UpdateFlow(
      look: () async => _update,
      fetch: (_, _) async => File('verified.exe'),
      canInstall: () async => true,
      install: (_) async =>
          throw ProcessException('setup.exe', [], 'cannot start'),
    );
    await flow.check();
    await flow.download();

    expect(flow.stage, UpdateStage.handOverFailed);
    expect(flow.failure, isNull);
  });

  group('whether the update installed (#73)', () {
    test('remembers what was handed over', () async {
      int? pending;
      final flow = UpdateFlow(
        look: () async => _update,
        fetch: (_, _) async => File('unused'),
        canInstall: () async => true,
        install: (_) async {},
        readPending: () async => pending,
        writePending: (build) async => pending = build,
      );
      await flow.check();
      await flow.download();

      expect(flow.stage, UpdateStage.handedOver);
      expect(pending, _update.build);
    });

    test('coming back to the same copy means it did not install', () async {
      int? pending;
      final flow = UpdateFlow(
        look: () async => _update,
        fetch: (_, _) async => File('unused'),
        canInstall: () async => true,
        install: (_) async {},
        readPending: () async => pending,
        writePending: (build) async => pending = build,
      );
      await flow.check();
      await flow.download();
      await flow.resumed();

      expect(flow.stage, UpdateStage.notInstalled);
      expect(pending, isNull);
    });

    test('resuming for any other reason says nothing', () async {
      final flow = UpdateFlow(
        readPending: () async => null,
        writePending: (_) async {},
      );
      await flow.resumed();
      expect(flow.stage, UpdateStage.idle);
    });

    test('a launch at an older build reports it once', () async {
      int? pending = 20;
      final flow = UpdateFlow(
        readPending: () async => pending,
        writePending: (build) async => pending = build,
        currentBuild: 13,
      );
      await flow.reconcile();

      expect(flow.stage, UpdateStage.notInstalled);
      expect(pending, isNull);

      final next = UpdateFlow(
        readPending: () async => pending,
        writePending: (build) async => pending = build,
        currentBuild: 13,
      );
      await next.reconcile();
      expect(next.stage, UpdateStage.idle);
    });

    test('a launch at the new build is quiet and clears the note', () async {
      int? pending = 20;
      final flow = UpdateFlow(
        readPending: () async => pending,
        writePending: (build) async => pending = build,
        currentBuild: 20,
      );
      await flow.reconcile();

      expect(flow.stage, UpdateStage.idle);
      expect(pending, isNull);
    });
  });
}
