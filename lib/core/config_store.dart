import 'dart:io';

/// Where the tunnel configuration lives between launches.
///
/// A `.conf` contains a private key, and this writes it to disk in the clear.
/// That is what every WireGuard client does today and it is still the weakest
/// thing here: on macOS this belongs in the Keychain, so the key is protected
/// by the login password and does not travel in a Time Machine backup. Doing
/// that needs platform channels, and it is worth doing before the first
/// release rather than after.
///
/// Until then the file is created 0600 inside the app's own container, which
/// keeps it away from other users but not from anything running as you.
abstract final class ConfigStore {
  static const _directoryName = 'Caelo';
  static const _fileName = 'tunnel.conf';

  static File _file() {
    final home = Platform.environment['HOME'];
    if (home == null || home.isEmpty) {
      throw StateError('HOME is not set, so there is nowhere to keep a config');
    }
    return File('$home/Library/Application Support/$_directoryName/$_fileName');
  }

  static Future<String?> read() async {
    final file = _file();
    if (!await file.exists()) return null;
    final text = await file.readAsString();
    return text.trim().isEmpty ? null : text;
  }

  static Future<void> write(String configText) async {
    final file = _file();
    await file.parent.create(recursive: true);
    await file.writeAsString(configText, flush: true);

    // Dart cannot set a file mode directly. Getting this wrong is worse than
    // failing loudly, so the result is checked rather than assumed.
    final result = await Process.run('chmod', ['600', file.path]);
    if (result.exitCode != 0) {
      await file.delete();
      throw StateError('could not restrict permissions on ${file.path}');
    }
  }

  static Future<void> clear() async {
    final file = _file();
    if (await file.exists()) await file.delete();
  }
}
