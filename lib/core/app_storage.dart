import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Where Caelo keeps things between launches.
///
/// The location is asked for rather than constructed. On macOS it lands in the
/// application container, on Android in the app's private files directory; a
/// path assembled by hand from `HOME` is right on exactly one of those.
abstract final class AppStorage {
  static Directory? _resolved;

  static Future<Directory> directory() async {
    final cached = _resolved;
    if (cached != null) return cached;

    final base = await getApplicationSupportDirectory();
    final directory = Directory('${base.path}/caelo');
    await directory.create(recursive: true);
    _resolved = directory;
    return directory;
  }

  static Future<File> file(String name) async =>
      File('${(await directory()).path}/$name');

  /// Restricts a file to its owner.
  ///
  /// A no-op on platforms where the app's directory is already private to it.
  /// Dart cannot set a mode directly, so this shells out — and checks, because
  /// silently failing to protect a private key is worse than not trying.
  static Future<void> restrict(File file) async {
    if (!Platform.isMacOS && !Platform.isLinux) return;

    final result = await Process.run('chmod', ['600', file.path]);
    if (result.exitCode != 0) {
      throw StateError('could not restrict permissions on ${file.path}');
    }
  }
}
