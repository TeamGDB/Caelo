import 'dart:convert';

import '../theme/palette.dart';
import 'app_storage.dart';

/// The handful of preferences the app keeps.
///
/// One small JSON file rather than a key-value plugin. There is not enough here
/// to justify a dependency, and a settings file a person can open and read is a
/// feature in a tool whose users have reason to want to know what it stores.
abstract final class SettingsStore {
  static const _fileName = 'settings.json';

  static Map<String, dynamic>? _cache;

  static Future<Map<String, dynamic>> _load() async {
    final cached = _cache;
    if (cached != null) return cached;

    final file = await AppStorage.file(_fileName);
    if (!await file.exists()) return _cache = {};

    try {
      return _cache =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    } on Object {
      // A corrupt settings file is not worth failing to start over. Defaults
      // are all recoverable by changing them again.
      return _cache = {};
    }
  }

  static Future<void> _save(Map<String, dynamic> settings) async {
    _cache = settings;
    final file = await AppStorage.file(_fileName);
    await file.writeAsString(jsonEncode(settings), flush: true);
  }

  static Future<CaeloThemeMode> themeMode() async {
    final name = (await _load())['themeMode'] as String?;
    return CaeloThemeMode.values.firstWhere(
      (mode) => mode.name == name,
      orElse: () => CaeloThemeMode.system,
    );
  }

  static Future<void> setThemeMode(CaeloThemeMode mode) async {
    final settings = Map<String, dynamic>.from(await _load());
    settings['themeMode'] = mode.name;
    await _save(settings);
  }
}
