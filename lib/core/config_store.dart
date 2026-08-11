import 'app_storage.dart';

/// Where the tunnel configuration lives between launches.
///
/// A `.conf` contains a private key, and this writes it to disk in the clear.
/// That is what every WireGuard client does today and it is still the weakest
/// thing here: this belongs in the Keychain on Apple platforms and in
/// Keystore-backed storage on Android, so the key is protected by the device
/// lock and does not travel in a backup. Both need platform channels, and both
/// are worth doing before the first release rather than after.
///
/// Until then the file lives in the app's private directory, restricted to its
/// owner where the platform has a mode to set.
abstract final class ConfigStore {
  static const _fileName = 'tunnel.conf';

  static Future<String?> read() async {
    final file = await AppStorage.file(_fileName);
    if (!await file.exists()) return null;
    final text = await file.readAsString();
    return text.trim().isEmpty ? null : text;
  }

  static Future<void> write(String configText) async {
    final file = await AppStorage.file(_fileName);
    await file.writeAsString(configText, flush: true);
    try {
      await AppStorage.restrict(file);
    } on Object {
      await file.delete();
      rethrow;
    }
  }

  static Future<void> clear() async {
    final file = await AppStorage.file(_fileName);
    if (await file.exists()) await file.delete();
  }
}
