import 'dart:async';

import 'dart:io';

import 'app_storage.dart';
import 'ffi/core_library.dart';
import 'apple_tunnel_client.dart';
import 'settings_store.dart';

/// What the app has been doing, for when a tunnel will not come up and the
/// person it is not coming up for is somewhere you are not.
///
/// This is deliberately not `debugPrint`. That reaches a console attached to a
/// development machine, which is exactly the situation where the problem does
/// not happen. The whole point of this is release builds.
///
/// It is off by default and holds nothing until it is switched on. A tool
/// people install because their connection is already being interfered with
/// should not keep a record of their connections uninvited.
abstract final class Diagnostics {
  /// How many of the app's own lines are kept. The core keeps its own ring of
  /// a comparable size, and the two are merged only when someone reads them.
  static const _capacity = 400;

  static const _fileName = 'diagnostic.log';

  static final _lines = <String>[];
  static final _changes = StreamController<void>.broadcast();

  static bool _enabled = false;

  /// Fires whenever a line is added, so an open log screen can follow along.
  static Stream<void> get changes => _changes.stream;

  static bool get enabled => _enabled;

  /// Reads the stored preference and brings the core into line with it.
  static Future<void> load() async {
    _enabled = await SettingsStore.diagnostics();
    _applyToCore();
    if (_enabled) {
      await _restore();
      record('diagnostics resumed');
    }
  }

  static Future<void> setEnabled(bool on) async {
    _enabled = on;
    await SettingsStore.setDiagnostics(on);
    _applyToCore();

    if (on) {
      record('diagnostics on');
    } else {
      // Switching it off throws away what was collected. Leaving the file
      // behind would mean the setting says "not recording" while a record sits
      // on disk, which is the kind of thing people are right to be angry about.
      _lines.clear();
      await clear();
    }
    _changes.add(null);
  }

  static void _applyToCore() {
    try {
      CoreLibrary.setVerbose(_enabled);
    } on Object {
      // No core loaded yet, or none at all. The app's own lines are still
      // worth keeping, and this is retried whenever the setting changes.
    }
  }

  /// Records one line. Does nothing at all when diagnostics are off.
  static void record(String message, {Object? error}) {
    if (!_enabled) return;

    final stamp = DateTime.now().toUtc().toIso8601String().substring(11, 23);
    final line = error == null
        ? '$stamp  $message'
        : '$stamp  $message: $error';

    _lines.add(_redact(line));
    if (_lines.length > _capacity) {
      _lines.removeRange(0, _lines.length - _capacity);
    }

    unawaited(_append(line));
    _changes.add(null);
  }

  /// Key material must never reach a file someone is about to send to a
  /// stranger. This runs on every line rather than at the call sites, because
  /// call sites are added by people and the one that forgets is the one that
  /// matters. The core redacts its own lines the same way.
  static final _secrets = RegExp(
    r'((?:private|public|preshared)[_ ]?key\s*[=:]\s*)\S+'
    r'|[A-Za-z0-9+/]{42}[A-Za-z0-9+/=]{1,2}'
    r'|\b[0-9a-f]{64}\b',
    caseSensitive: false,
  );

  static String _redact(String text) =>
      text.replaceAllMapped(_secrets, (match) {
        final labelled = match.group(1);
        return labelled == null ? '<redacted>' : '$labelled<redacted>';
      });

  static Future<void> _append(String line) async {
    try {
      final file = await AppStorage.file(_fileName);
      await file.writeAsString('$line\n', mode: FileMode.append, flush: false);
      await AppStorage.restrict(file);
    } on Object {
      // A log that cannot be written is not worth failing anything over.
    }
  }

  static Future<void> _restore() async {
    try {
      final file = await AppStorage.file(_fileName);
      if (!await file.exists()) return;

      final kept = (await file.readAsLines())
          .where((l) => l.isNotEmpty)
          .toList();
      _lines
        ..clear()
        ..addAll(
          kept.length > _capacity
              ? kept.sublist(kept.length - _capacity)
              : kept,
        );
    } on Object {
      // Nothing to restore.
    }
  }

  static Future<void> clear() async {
    _lines.clear();
    try {
      CoreLibrary.clearLog();
    } on Object {
      // No core to clear.
    }
    try {
      final file = await AppStorage.file(_fileName);
      if (await file.exists()) await file.delete();
    } on Object {
      // Already gone.
    }
    _changes.add(null);
  }

  /// The app's lines and the core's, merged.
  ///
  /// Both are timestamped in UTC, so sorting on the stamp puts them in the
  /// order they actually happened rather than the order they were collected.
  static List<String> merged() {
    final core = <String>[];
    try {
      core.addAll(CoreLibrary.log().lines.map((line) => 'core  $line'));
    } on Object {
      core.add('core  <not loaded>');
    }

    // On Apple platforms the core the app can reach is not the one running
    // the tunnel: that one lives in the extension, in another process, and
    // everything worth reading happens there. Fetched separately, folded in.
    if (AppleTunnelClient.isSupported) {
      core.addAll(_extensionLines.map((l) => 'tun   $l'));
    }

    return [..._lines.map((line) => 'app   $line'), ...core]
      ..sort(_byTimestamp);
  }

  static int _byTimestamp(String a, String b) {
    // Lines are "<source>  <hh:mm:ss.mmm>  ...". A line without a usable stamp
    // sorts to the end rather than throwing.
    String stamp(String line) {
      final parts = line.split(RegExp(r'\s+'));
      return parts.length > 1 ? parts[1] : '~';
    }

    return stamp(a).compareTo(stamp(b));
  }

  static List<String> _extensionLines = const [];

  /// Pulls the tunnel's own log across the process boundary. Apple only; on
  /// every other platform the core in this process is the one that ran it.
  static Future<void> refreshFromExtension() async {
    if (!AppleTunnelClient.isSupported) return;
    _extensionLines = await AppleTunnelClient.extensionLog();
    _changes.add(null);
  }

  /// The whole thing as text, with a header naming the build it came from.
  ///
  /// The header is what makes a pasted log answerable. Without it the first
  /// reply is always "which version?" and the person is already gone.
  static Future<String> render() async {
    await refreshFromExtension();

    final buffer = StringBuffer()
      ..writeln('Caelo diagnostic log')
      ..writeln('collected  ${DateTime.now().toUtc().toIso8601String()}')
      ..writeln('app        0.1.0')
      ..writeln(
        'platform   ${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
      );

    try {
      final version = CoreLibrary.version();
      buffer.writeln(
        'core       ${version.core} (amneziawg-go ${version.amneziaWg})',
      );
    } on Object catch (error) {
      buffer.writeln('core       not loaded: $error');
    }

    buffer
      ..writeln()
      ..writeln('No key material appears below; it is removed as each line is')
      ..writeln('recorded. Server addresses do appear.')
      ..writeln();

    final lines = merged();
    if (lines.isEmpty) {
      buffer.writeln('(nothing recorded)');
    } else {
      lines.forEach(buffer.writeln);
    }

    return buffer.toString();
  }

  /// Writes the rendered log somewhere it can be handed to someone else.
  static Future<File> export() async {
    final file = await AppStorage.file('caelo-log.txt');
    await file.writeAsString(await render(), flush: true);
    return file;
  }
}
