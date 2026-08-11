import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'app_storage.dart';

@immutable
class StoredConfig {
  const StoredConfig({
    required this.id,
    required this.name,
    this.emoji = '📄',
    this.description = '',
  });

  final String id;
  final String name;
  final String emoji;
  final String description;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'emoji': emoji,
    'description': description,
  };

  static StoredConfig fromJson(Map<String, dynamic> json) => StoredConfig(
    id: json['id'] as String,
    name: json['name'] as String,
    emoji: json['emoji'] as String? ?? '📄',
    description: json['description'] as String? ?? '',
  );
}

/// Stores multiple private tunnel configurations while exposing only the
/// selected configuration to tunnel clients through [read].
abstract final class ConfigStore {
  static const _legacyFileName = 'tunnel.conf';
  static const _indexFileName = 'configs.json';
  static const _filePrefix = 'config-';
  static const _subscriptionId = '@subscription';
  static const _subscriptionFileName = 'subscription-node.conf';

  @visibleForTesting
  static Future<Directory> Function() directory = AppStorage.directory;

  static Future<File> _file(String name) async =>
      File('${(await directory()).path}/$name');

  static Future<File> _configFile(String id) => _file('$_filePrefix$id.conf');

  static Future<({List<StoredConfig> configs, String? selectedId})>
  _loadIndex() async {
    await _migrateLegacy();
    final file = await _file(_indexFileName);
    if (!await file.exists()) {
      return (configs: const <StoredConfig>[], selectedId: null);
    }
    try {
      final json =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final configs = (json['configs'] as List<dynamic>? ?? const [])
          .map((item) => StoredConfig.fromJson(item as Map<String, dynamic>))
          .toList(growable: false);
      return (configs: configs, selectedId: json['selectedId'] as String?);
    } on Object {
      return (configs: const <StoredConfig>[], selectedId: null);
    }
  }

  static Future<void> _saveIndex(
    List<StoredConfig> configs,
    String? selectedId,
  ) async {
    final file = await _file(_indexFileName);
    await file.writeAsString(
      jsonEncode({
        'selectedId': selectedId,
        'configs': configs.map((config) => config.toJson()).toList(),
      }),
      flush: true,
    );
  }

  static Future<void> _migrateLegacy() async {
    final index = await _file(_indexFileName);
    if (await index.exists()) return;
    final legacy = await _file(_legacyFileName);
    if (!await legacy.exists()) return;
    final text = await legacy.readAsString();
    if (text.trim().isEmpty) {
      await legacy.delete();
      return;
    }
    const config = StoredConfig(id: 'legacy', name: 'Imported configuration');
    final target = await _configFile(config.id);
    await target.writeAsString(text, flush: true);
    await AppStorage.restrict(target);
    await _saveIndex(const [config], config.id);
    await legacy.delete();
  }

  static Future<List<StoredConfig>> list() async =>
      (await _loadIndex()).configs;

  static Future<String?> selectedId() async => (await _loadIndex()).selectedId;

  /// The active configuration used by every tunnel client.
  static Future<String?> read() async {
    final index = await _loadIndex();
    final selectedId = index.selectedId;
    if (selectedId == null) return null;
    final file = selectedId == _subscriptionId
        ? await _file(_subscriptionFileName)
        : await _configFile(selectedId);
    if (!await file.exists()) return null;
    final text = await file.readAsString();
    return text.trim().isEmpty ? null : text;
  }

  static Future<String?> readById(String id) async {
    final file = await _configFile(id);
    if (!await file.exists()) return null;
    return file.readAsString();
  }

  static Future<StoredConfig> create(
    String name,
    String configText, {
    String emoji = '📄',
    String description = '',
  }) async {
    final index = await _loadIndex();
    final id = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final config = StoredConfig(
      id: id,
      name: _normaliseName(name),
      emoji: _normaliseEmoji(emoji),
      description: description.trim(),
    );
    await _writeConfig(config.id, configText);
    await _saveIndex([...index.configs, config], config.id);
    return config;
  }

  static Future<void> update(
    String id,
    String name,
    String configText, {
    String emoji = '📄',
    String description = '',
  }) async {
    final index = await _loadIndex();
    if (!index.configs.any((config) => config.id == id)) {
      throw StateError('configuration does not exist');
    }
    await _writeConfig(id, configText);
    await _saveIndex([
      for (final config in index.configs)
        if (config.id == id)
          StoredConfig(
            id: id,
            name: _normaliseName(name),
            emoji: _normaliseEmoji(emoji),
            description: description.trim(),
          )
        else
          config,
    ], index.selectedId);
  }

  static Future<void> select(String id) async {
    final index = await _loadIndex();
    if (!index.configs.any((config) => config.id == id)) return;
    await _saveIndex(index.configs, id);
  }

  /// Makes a node selected from a subscription the active tunnel endpoint.
  ///
  /// It deliberately stays outside [list]: a server-owned node is not a custom
  /// configuration and must not appear in Settings as if the user created it.
  static Future<void> activateSubscriptionNode(String endpoint) async {
    if (endpoint.trim().isEmpty) {
      throw ArgumentError('a subscription node needs an endpoint');
    }
    final index = await _loadIndex();
    final file = await _file(_subscriptionFileName);
    await file.writeAsString(endpoint, flush: true);
    try {
      await AppStorage.restrict(file);
      await _saveIndex(index.configs, _subscriptionId);
    } on Object {
      if (await file.exists()) await file.delete();
      rethrow;
    }
  }

  static Future<void> delete(String id) async {
    final index = await _loadIndex();
    final remaining = index.configs
        .where((config) => config.id != id)
        .toList(growable: false);
    final file = await _configFile(id);
    if (await file.exists()) await file.delete();
    final selected = index.selectedId == id
        ? remaining.firstOrNull?.id
        : index.selectedId;
    await _saveIndex(remaining, selected);
  }

  /// Compatibility for import call sites: create another named configuration.
  static Future<void> write(String configText) async {
    await create('Imported configuration', configText);
  }

  /// Compatibility for old call sites: delete only the selected configuration.
  static Future<void> clear() async {
    final id = await selectedId();
    if (id != null) await delete(id);
  }

  static Future<void> _writeConfig(String id, String configText) async {
    final file = await _configFile(id);
    await file.writeAsString(configText, flush: true);
    try {
      await AppStorage.restrict(file);
    } on Object {
      await file.delete();
      rethrow;
    }
  }

  static String _normaliseName(String name) {
    final trimmed = name.trim();
    return trimmed.isEmpty ? 'Configuration' : trimmed;
  }

  static String _normaliseEmoji(String emoji) {
    final trimmed = emoji.trim();
    return trimmed.isEmpty ? '📄' : trimmed;
  }
}
