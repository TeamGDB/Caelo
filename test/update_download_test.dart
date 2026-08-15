import 'dart:async';
import 'dart:io';

import 'package:caelo/core/update_check.dart';
import 'package:caelo/core/update_download.dart';
import 'package:flutter_test/flutter_test.dart';

AvailableUpdate update({required String url, int size = 0}) => AvailableUpdate(
  version: '9.9.9',
  build: 999,
  url: url,
  sizeBytes: size,
  sha256: 'a' * 64,
  signature: 'c2lnbmF0dXJl',
  notesUrl: 'https://example.invalid/notes',
);

void main() {
  late Directory directory;
  late HttpServer server;
  late List<int> body;
  late int truncateTo;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('caelo-download-test-');
    UpdateDownload.file = (name) async => File('${directory.path}/$name');

    body = List<int>.generate(64 * 1024, (i) => i % 256);
    truncateTo = -1;

    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    unawaited(
      server.forEach((request) async {
        if (request.uri.path == '/missing') {
          request.response.statusCode = 404;
        } else {
          final sent = truncateTo == -1 ? body : body.sublist(0, truncateTo);
          request.response.add(sent);
        }
        await request.response.close();
      }),
    );
  });

  tearDown(() async {
    await server.close(force: true);
    UpdateDownload.file = (name) async => File(name);
    await directory.delete(recursive: true);
  });

  String url([String path = '/Caelo.apk']) =>
      'http://${server.address.address}:${server.port}$path';

  test('saves what it fetched and reports progress', () async {
    final seen = <double>[];
    final file = await UpdateDownload.fetch(
      update(url: url(), size: 65536),
      onProgress: seen.add,
      verify: (_, _) async => true,
    );

    expect(await file.length(), 65536);
    expect(seen, isNotEmpty);
    expect(seen.last, closeTo(1.0, 0.001));
  });

  // The order is the whole point: a file handed to the system installer may
  // already have run, so the check cannot happen afterwards.
  test('deletes a file that is not ours rather than returning it', () async {
    late String checked;
    await expectLater(
      UpdateDownload.fetch(
        update(url: url(), size: 65536),
        verify: (path, _) async {
          checked = path;
          return false;
        },
      ),
      throwsA(
        isA<DownloadFailed>().having(
          (e) => e.reason,
          'reason',
          DownloadFailure.untrusted,
        ),
      ),
    );

    // Gone, not kept for inspection: a file somebody else may have chosen for
    // us, sitting on disk under a plausible name, is how it gets opened later
    // by accident.
    expect(File(checked).existsSync(), isFalse);
    expect(directory.listSync(), isEmpty);
  });

  test('a transfer that stops early is a failure, not a short file', () async {
    truncateTo = 1024;

    await expectLater(
      UpdateDownload.fetch(
        update(url: url(), size: 65536),
        verify: (_, _) async => true,
      ),
      throwsA(
        isA<DownloadFailed>().having(
          (e) => e.reason,
          'reason',
          DownloadFailure.unreachable,
        ),
      ),
    );
    expect(directory.listSync(), isEmpty);
  });

  test('a server that answers with an error leaves nothing behind', () async {
    await expectLater(
      UpdateDownload.fetch(
        update(url: url('/missing'), size: 65536),
        verify: (_, _) async => true,
      ),
      throwsA(isA<DownloadFailed>()),
    );
    expect(directory.listSync(), isEmpty);
  });

  // Somebody who can serve the file can serve more of it than the manifest
  // promised. Finding out how much by reading it all would be the mistake.
  test('stops when more arrives than the manifest promised', () async {
    await expectLater(
      UpdateDownload.fetch(
        update(url: url(), size: 1024),
        verify: (_, _) async => true,
      ),
      throwsA(isA<DownloadFailed>()),
    );
    expect(directory.listSync(), isEmpty);
  });

  test(
    'keeps the extension, which is how Android decides what a file is',
    () async {
      final file = await UpdateDownload.fetch(
        update(url: url('/Caelo-0.1.1-android7+-arm64-v8a.apk'), size: 65536),
        verify: (_, _) async => true,
      );
      expect(file.path, endsWith('.apk'));
    },
  );

  // The default path, which no other test takes because they all inject a
  // verifier -- which is exactly how a call that could never work shipped. It
  // fails here without a core to talk to, and the point is *how*: a rejection,
  // not a NoSuchMethodError from calling a named-parameter function
  // positionally.
  test('the built-in verifier is called the way it is declared', () async {
    await expectLater(
      UpdateDownload.fetch(update(url: url(), size: 65536)),
      throwsA(
        isA<DownloadFailed>().having(
          (e) => e.reason,
          'reason',
          DownloadFailure.untrusted,
        ),
      ),
    );
    expect(directory.listSync(), isEmpty);
  });
}
