import 'dart:convert';
import 'dart:io';

import 'package:caelo/core/app_storage.dart';
import 'package:caelo/core/device_description.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('the name (#138)', () {
    test('a Cyrillic name is sent percent-encoded, and decodes back', () {
      final headers = DeviceDescription.of(name: 'Телефон бабушки').headers;
      final sent = headers['X-Caelo-Device-Name']!;
      expect(sent, isNot(contains('Т')));
      expect(latin1.encode(sent), isNotEmpty, reason: 'a header is latin-1');
      expect(Uri.decodeComponent(sent), 'Телефон бабушки');
    });

    test('an empty name is not sent', () {
      expect(
        DeviceDescription.of(name: '   ').headers,
        isNot(contains('X-Caelo-Device-Name')),
      );
      expect(
        DeviceDescription.of().headers,
        isNot(contains('X-Caelo-Device-Name')),
      );
    });

    test('localhost is not a name', () {
      expect(
        DeviceDescription.of(name: 'localhost').headers,
        isNot(contains('X-Caelo-Device-Name')),
      );
      expect(
        DeviceDescription.of(name: 'LOCALHOST').headers,
        isNot(contains('X-Caelo-Device-Name')),
      );
    });

    test('control characters go, spaces collapse, and it stops at 64', () {
      final name = DeviceDescription.of(name: ' a\tb\n\u0000c ').name;
      expect(name, 'a b c');
      final long = DeviceDescription.of(name: 'я' * 100).name!;
      expect(long.runes.length, 64);
    });

    test('an Android model is named with its maker, once', () {
      expect(
        DeviceDescriptions.androidName('Google', 'Pixel 8'),
        'Google Pixel 8',
      );
      expect(
        DeviceDescriptions.androidName('samsung', 'SM-S918B'),
        'Samsung SM-S918B',
      );
      expect(
        DeviceDescriptions.androidName('Xiaomi', 'Xiaomi 13T'),
        'Xiaomi 13T',
      );
      expect(
        DeviceDescriptions.androidName('', 'sdk_gphone64'),
        'sdk_gphone64',
      );
    });
  });

  group('the platform (#138)', () {
    test('the OS in lower case, then its version', () {
      expect(
        DeviceDescription.of(platform: 'Android 14').platform,
        'android 14',
      );
      expect(DeviceDescription.of(platform: 'iOS 18.1').platform, 'ios 18.1');
      expect(
        DeviceDescription.of(platform: 'iPadOS 18.1').platform,
        'ipados 18.1',
      );
      expect(DeviceDescription.of(platform: 'linux').platform, 'linux');
      expect(
        DeviceDescription.of(
          platform: 'macos 15.1',
        ).headers['X-Caelo-Platform'],
        'macos 15.1',
      );
    });

    test('Windows 11 is told apart from 10 by its build', () {
      expect(DeviceDescriptions.windowsPlatform(10, 19045), 'windows 10');
      expect(DeviceDescriptions.windowsPlatform(10, 22631), 'windows 11');
    });

    test('an unknown platform is not sent', () {
      expect(
        DeviceDescription.of(platform: ' ').headers,
        isNot(contains('X-Caelo-Platform')),
      );
    });
  });

  group('on a request', () {
    late Directory directory;
    late HttpServer server;
    late Map<String, String?> seen;
    final original = DeviceDescriptions.read;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('caelo-device-test-');
      AppStorage.testDirectory = directory;
      DeviceDescriptions.forget();
      seen = {};
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) {
        for (final name in [
          'x-caelo-device',
          'x-caelo-device-name',
          'x-caelo-platform',
        ]) {
          seen[name] = request.headers.value(name);
        }
        request.response.close();
      });
    });

    tearDown(() async {
      DeviceDescriptions.read = original;
      DeviceDescriptions.forget();
      AppStorage.testDirectory = null;
      await server.close(force: true);
      await directory.delete(recursive: true);
    });

    Future<void> send() async {
      final client = HttpClient();
      final request = await client.get('127.0.0.1', server.port, '/');
      await DeviceHeaders.apply(request.headers);
      await (await request.close()).drain<void>();
      client.close();
    }

    test('both headers arrive, beside the identifier', () async {
      DeviceDescriptions.read = () async =>
          DeviceDescription.of(name: 'Ноутбук', platform: 'linux');
      await send();
      expect(seen['x-caelo-device'], isNotEmpty);
      expect(Uri.decodeComponent(seen['x-caelo-device-name']!), 'Ноутбук');
      expect(seen['x-caelo-platform'], 'linux');
    });

    test('a description that cannot be read does not fail the request, and '
        'leaves the headers out', () async {
      DeviceDescriptions.read = () async => throw StateError('no plugin');
      await send();
      expect(seen['x-caelo-device'], isNotEmpty);
      expect(seen['x-caelo-device-name'], isNull);
      expect(seen['x-caelo-platform'], isNull);
    });

    test('it is read once and remembered', () async {
      var reads = 0;
      DeviceDescriptions.read = () async {
        reads++;
        return DeviceDescription.of(platform: 'android 14');
      };
      await send();
      await send();
      expect(reads, 1);
    });
  });
}
