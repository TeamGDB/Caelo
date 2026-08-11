import 'dart:convert';

import 'package:flutter/widgets.dart';

import '../theme/palette.dart';
import 'app_storage.dart';

/// How the interface chooses its locale.
enum CaeloLocaleMode {
  system(null),
  russian(Locale('ru')),
  english(Locale('en'));

  const CaeloLocaleMode(this.locale);

  /// Null deliberately hands locale resolution back to Flutter and the OS.
  final Locale? locale;
}

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

  static Future<CaeloLocaleMode> localeMode() async {
    final name = (await _load())['localeMode'] as String?;
    return CaeloLocaleMode.values.firstWhere(
      (mode) => mode.name == name,
      orElse: () => CaeloLocaleMode.system,
    );
  }

  static Future<void> setLocaleMode(CaeloLocaleMode mode) async {
    final settings = Map<String, dynamic>.from(await _load());
    settings['localeMode'] = mode.name;
    await _save(settings);
  }

  static Future<bool> accessGranted() async =>
      (await _load())['accessGranted'] == true;

  static Future<void> setAccessGranted(bool granted) async {
    final settings = Map<String, dynamic>.from(await _load());
    settings['accessGranted'] = granted;
    await _save(settings);
  }

  static Future<String?> selectedServerId() async =>
      (await _load())['selectedServerId'] as String?;

  static Future<void> setSelectedServerId(String id) async {
    final settings = Map<String, dynamic>.from(await _load());
    settings['selectedServerId'] = id;
    await _save(settings);
  }

  /// Whether the diagnostic log is being kept.
  ///
  /// Off by default, and stored rather than assumed: someone who turned it on
  /// to catch an intermittent problem should not lose it by closing the app.
  static Future<bool> diagnostics() async =>
      (await _load())['diagnostics'] == true;

  static Future<void> setDiagnostics(bool on) async {
    final settings = Map<String, dynamic>.from(await _load());
    settings['diagnostics'] = on;
    await _save(settings);
  }
}
