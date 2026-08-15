import 'dart:convert';

import 'package:caelo/core/build_info.dart';
import 'package:caelo/core/update_check.dart';
import 'package:flutter_test/flutter_test.dart';

String manifest({
  int build = 999,
  String version = '9.9.9',
  Map<String, dynamic>? artifacts,
}) => jsonEncode({
  'version': version,
  'build': build,
  'published': '2026-08-15T05:32:10Z',
  'notes': 'https://github.com/TeamGDB/Caelo/releases/tag/v9.9.9',
  'artifacts':
      artifacts ??
      {
        for (final key in [
          'macos-dmg',
          'windows-setup-x64',
          'linux-appimage-x64',
          'android-arm64-v8a',
          'android-armeabi-v7a',
          'android-x86_64',
          'android-universal',
        ])
          key: {
            'url': 'https://example.invalid/$key',
            'size': 1024,
            'sha256': 'a' * 64,
            'ed25519': 'c2lnbmF0dXJl',
          },
      },
});

void main() {
  group('deciding whether there is anything newer', () {
    test('finds a build above this one', () {
      final found = UpdateCheck.read(manifest(build: appBuild + 1));
      expect(found, isNotNull);
      expect(found!.build, appBuild + 1);
      expect(found.sizeBytes, 1024);
      expect(found.sha256, isNotEmpty);
      expect(found.signature, isNotEmpty);
    });

    // A manifest without one is not "no check needed", it is unusable. The
    // digest is no substitute: whoever could serve a different file could serve
    // a manifest describing it.
    test(
      'an artifact with no signature yields an empty one, not a default',
      () {
        final found = UpdateCheck.read(
          jsonEncode({
            'version': '9.9.9',
            'build': appBuild + 1,
            'artifacts': {
              UpdateCheck.artifactKey: {
                'url': 'https://example.invalid/x',
                'size': 1,
                'sha256': 'b' * 64,
              },
            },
          }),
        );
        expect(found, isNotNull);
        expect(found!.signature, isEmpty);
      },
    );

    // The marketing version has shipped more than once. Comparing it would have
    // every build of 0.1.0 consider every other one identical, which is the
    // failure that leaves people on a version with a hole in it.
    test('compares the build number, not the version string', () {
      expect(
        UpdateCheck.read(manifest(build: appBuild, version: '99.0.0')),
        isNull,
      );
    });

    test('an older manifest is not an update', () {
      expect(UpdateCheck.read(manifest(build: appBuild - 1)), isNull);
    });

    // Ordinary on Linux, where upgrading belongs to the package manager and the
    // manifest exists only so a line of text can say a newer version is out.
    test('a manifest with nothing for this platform is not an update', () {
      expect(
        UpdateCheck.read(manifest(build: appBuild + 1, artifacts: {})),
        isNull,
      );
    });

    test('a manifest that is not a manifest does not crash the check', () {
      expect(() => UpdateCheck.read('<html>404</html>'), throwsA(anything));
      // ...and look() turns that into "no update" rather than an error nobody
      // asked for: this runs on a timer and a broken server is not an event to
      // put in front of somebody.
      expect(
        UpdateCheck.look(
          fetch: (_) async => '<html>404</html>',
          enabled: () async => true,
        ),
        completion(isNull),
      );
    });
  });

  group('the rules about asking', () {
    // The switch has to stop the request, not filter its result. A check that
    // fetched and then discarded would still have told the server we are here,
    // which is the entire thing being avoided.
    test('makes no request at all when it is switched off', () async {
      var asked = false;
      final found = await UpdateCheck.look(
        fetch: (_) async {
          asked = true;
          return manifest();
        },
        enabled: () async => false,
      );

      expect(asked, isFalse, reason: 'the network was touched anyway');
      expect(found, isNull);
    });

    test('asks when it is switched on', () async {
      var asked = false;
      await UpdateCheck.look(
        fetch: (_) async {
          asked = true;
          return manifest();
        },
        enabled: () async => true,
      );

      expect(asked, isTrue);
    });

    // Nothing about the installation may reach the request. This pins the two
    // things that would be easiest to add without thinking: a version, so the
    // server could answer directly, and anything in a query string.
    test('the address it asks for carries no identifiers', () {
      final url = Uri.parse(UpdateCheck.manifestUrl);

      expect(url.scheme, 'https');
      expect(
        url.hasQuery,
        isFalse,
        reason: 'a query string can carry anything',
      );
      expect(url.userInfo, isEmpty);
      expect(url.path, isNot(contains(appVersion)));
      expect(url.path, isNot(contains('$appBuild')));
    });

    test('the user agent names the program and not the build', () {
      expect(UpdateCheck.userAgent, 'Caelo');
      expect(UpdateCheck.userAgent, isNot(contains(appVersion)));
      expect(UpdateCheck.userAgent, isNot(contains('$appBuild')));
    });

    // It would be the obvious implementation, and it is the one that turns a
    // CDN fetch into something a per-IP quota applies to — sixty an hour,
    // shared by everyone behind one exit node.
    test('it does not ask the GitHub API', () {
      expect(UpdateCheck.manifestUrl, isNot(contains('api.github.com')));
    });
  });

  // The property everything else rests on. One key cannot be replaced: adding a
  // second takes an update, and shipping an update takes the key that is gone.
  // If this ever drops to one, a lost key ends updates for every installation
  // that already exists.
  group('more than one key is trusted', () {
    test('there is a spare', () {
      expect(
        UpdateCheck.trustedKeys.length,
        greaterThanOrEqualTo(2),
        reason: 'a single key cannot be rotated, only lost',
      );
    });

    test('they are distinct, and each is a 32-byte Ed25519 key', () {
      expect(
        UpdateCheck.trustedKeys.toSet().length,
        UpdateCheck.trustedKeys.length,
      );
      for (final key in UpdateCheck.trustedKeys) {
        expect(
          base64Decode(key).length,
          32,
          reason: '$key is not an Ed25519 key',
        );
      }
    });
  });

  group('picking the file for this machine', () {
    // Installing one architecture's APK over another's fails, so these must
    // not collide -- and all three have to name files the manifest publishes.
    test('each Android architecture gets its own build', () {
      final published =
          (jsonDecode(manifest())['artifacts'] as Map<String, dynamic>).keys;
      final chosen = {
        for (final abi in ['arm64-v8a', 'armeabi-v7a', 'x86_64'])
          UpdateCheck.androidKeyFor(abi),
      };

      expect(chosen.length, 3, reason: 'two architectures share a file');
      for (final key in chosen) {
        expect(published, contains(key));
      }
    });

    test(
      'an architecture with no split of its own falls back to universal',
      () {
        expect(UpdateCheck.androidKeyFor('riscv64'), 'android-universal');
      },
    );

    test('the key for this host is one the manifest actually publishes', () {
      final published =
          (jsonDecode(manifest())['artifacts'] as Map<String, dynamic>).keys;
      expect(published, contains(UpdateCheck.artifactKey));
    });
  });
}
