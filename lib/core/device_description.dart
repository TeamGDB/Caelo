import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';

import 'capabilities.dart';
import 'device_identity.dart';

/// What this device is called and what it runs, for the subscription's list
/// of devices (#138).
///
/// [DeviceIdentity] says "the same installation as last time" and nothing
/// else. This is the other half: something a person recognises in the panel,
/// where every device used to be listed as "Device". It is what the device
/// calls itself — the name somebody gave their phone or computer — and the
/// OS, and it is only ever sent to the subscription the person pasted.
@immutable
class DeviceDescription {
  const DeviceDescription({this.name, this.platform});

  /// What the device calls itself, or null when that is not known.
  final String? name;

  /// The OS in lower case and its version, `android 14`, `windows 11`; or
  /// null when not known.
  final String? platform;

  static const nothing = DeviceDescription();

  /// The headers this adds to a subscription request. A value that is not
  /// known is left out rather than sent empty: the server keeps what it had.
  Map<String, String> get headers => {
    if (name case final name?) 'X-Caelo-Device-Name': Uri.encodeComponent(name),
    'X-Caelo-Platform': ?platform,
  };

  /// Builds a description, dropping what does not describe anything.
  ///
  /// A name of `localhost` is what Android and many containers report as
  /// their hostname, and says nothing; an empty one says less.
  factory DeviceDescription.of({String? name, String? platform}) {
    return DeviceDescription(
      name: _cleanName(name),
      platform: _cleanPlatform(platform),
    );
  }

  static String? _cleanName(String? raw) {
    if (raw == null) return null;
    // Whitespace first, so a tab or a newline becomes a space rather than
    // vanishing between two words; then whatever control characters remain.
    final collapsed = raw
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r'[\u0000-\u001f\u007f]'), '')
        .trim();
    if (collapsed.isEmpty) return null;
    if (collapsed.toLowerCase() == 'localhost') return null;
    // The server cuts at 64 as well; cutting here keeps the header short.
    final runes = collapsed.runes.toList();
    return runes.length <= 64
        ? collapsed
        : String.fromCharCodes(runes.take(64));
  }

  static String? _cleanPlatform(String? raw) {
    if (raw == null) return null;
    final value = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (value.isEmpty) return null;
    final space = value.indexOf(' ');
    return space < 0
        ? value.toLowerCase()
        : '${value.substring(0, space).toLowerCase()}${value.substring(space)}';
  }
}

/// Puts the device's headers on a subscription request: its identifier, and
/// its name and platform when they are known.
abstract final class DeviceHeaders {
  static Future<void> apply(HttpHeaders headers) async {
    headers.set('X-Caelo-Device', await DeviceIdentity.get());
    // What this installation can connect to, on every request a subscription
    // sees — the document, its state, and asking for or replacing a node —
    // so that a server answers each of them alike (#172). Absent when there
    // is nothing beyond AmneziaWG to say, which is what every server has seen
    // until now.
    final capabilities = Capabilities.header(await Capabilities.current());
    if (capabilities != null) headers.set('X-Caelo-Capabilities', capabilities);
    for (final MapEntry(:key, :value)
        in (await DeviceDescriptions.get()).headers.entries) {
      headers.set(key, value);
    }
  }
}

/// Reads and remembers this device's description.
abstract final class DeviceDescriptions {
  static DeviceDescription? _cache;

  /// Where the description comes from. A seam for tests; the platform
  /// otherwise.
  @visibleForTesting
  static Future<DeviceDescription> Function() read = _fromPlatform;

  /// The description, read once per run.
  ///
  /// Never throws. This is called while building the headers of a
  /// subscription request, and not knowing what the device is called is no
  /// reason to fail a refresh: the headers are left out, which the server
  /// reads as "nothing new to say".
  static Future<DeviceDescription> get() async {
    final cached = _cache;
    if (cached != null) return cached;
    try {
      return _cache = await read();
    } on Object {
      return _cache = DeviceDescription.nothing;
    }
  }

  @visibleForTesting
  static void forget() => _cache = null;

  static Future<DeviceDescription> _fromPlatform() async {
    final info = DeviceInfoPlugin();
    if (Platform.isAndroid) {
      final android = await info.androidInfo;
      return DeviceDescription.of(
        name: androidName(android.manufacturer, android.model),
        platform: 'android ${android.version.release}',
      );
    }
    if (Platform.isIOS) {
      final ios = await info.iosInfo;
      return DeviceDescription.of(
        // The name somebody gave the phone; since iOS 16 it is the model
        // ("iPhone") unless an entitlement says otherwise, which still beats
        // "Device".
        name: ios.name.isNotEmpty ? ios.name : ios.modelName,
        // "iPadOS" for an iPad, "iOS" for a phone: the panel tells them apart.
        platform: '${ios.systemName} ${ios.systemVersion}',
      );
    }
    if (Platform.isMacOS) {
      final mac = await info.macOsInfo;
      final minor = mac.minorVersion == 0 ? '' : '.${mac.minorVersion}';
      return DeviceDescription.of(
        name: mac.computerName,
        platform: 'macos ${mac.majorVersion}$minor',
      );
    }
    if (Platform.isWindows) {
      final windows = await info.windowsInfo;
      return DeviceDescription.of(
        name: windows.computerName,
        platform: windowsPlatform(windows.majorVersion, windows.buildNumber),
      );
    }
    if (Platform.isLinux) {
      return DeviceDescription.of(
        name: Platform.localHostname,
        platform: 'linux',
      );
    }
    return DeviceDescription.of(
      name: Platform.localHostname,
      platform: Platform.operatingSystem,
    );
  }

  /// "Google Pixel 8" from "Google" and "Pixel 8", and not "samsung SM-S918B
  /// SM-S918B" style repetition when the model already names the maker.
  @visibleForTesting
  static String androidName(String manufacturer, String model) {
    final maker = manufacturer.trim();
    final device = model.trim();
    if (maker.isEmpty) return device;
    if (device.toLowerCase().startsWith(maker.toLowerCase())) return device;
    final capitalised = maker[0].toUpperCase() + maker.substring(1);
    return '$capitalised $device';
  }

  /// Windows 11 still reports itself as 10.0; the build number is what
  /// tells them apart, from 22000 on.
  @visibleForTesting
  static String windowsPlatform(int majorVersion, int buildNumber) {
    if (majorVersion == 10 && buildNumber >= 22000) return 'windows 11';
    return 'windows $majorVersion';
  }
}
