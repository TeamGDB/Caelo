import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'build_info.dart';
import 'diagnostics.dart';
import 'ffi/core_library.dart';
import 'settings_store.dart';

/// A newer build than this one, and where to get it.
@immutable
class AvailableUpdate {
  const AvailableUpdate({
    required this.version,
    required this.build,
    required this.url,
    required this.sizeBytes,
    required this.sha256,
    required this.signature,
    required this.notesUrl,
  });

  final String version;
  final int build;
  final String url;
  final int sizeBytes;
  final String sha256;

  /// Base64 Ed25519 over the file's bytes, made by one of [UpdateCheck
  /// .trustedKeys]. Empty when the manifest carried none, which is treated as
  /// unsigned and therefore unusable rather than as "no check needed".
  final String signature;

  final String notesUrl;
}

/// Asks whether a newer build exists, under rules that keep the asking from
/// being worth anything to whoever is listening.
///
/// A client that contacts a server on a schedule is a client that reports when
/// it is running and from where. In most software that is a footnote. Here it is
/// the thing people installed us to avoid, so the constraints below are part of
/// the feature rather than a hardening pass over it:
///
///  * **Nothing identifies the installation.** No identifier, no query string,
///    no header that varies. Two copies of Caelo on the same platform produce
///    byte-identical requests, which is what makes the request worthless as a
///    beacon rather than merely small.
///  * **The version is not sent.** It would be the obvious thing to send and
///    would let the server answer "you are current" directly. Instead the whole
///    manifest is fetched and compared here, because a request carrying a
///    version distinguishes installations from one another.
///  * **Through the tunnel when there is one.** Where the platform routes the
///    whole machine this happens by itself. Where it does not — the in-process
///    tunnel — the caller supplies [fetch] that goes through it.
///  * **Checking is not downloading.** This decides whether something newer
///    exists. Fetching it is a separate act that the person agrees to, because
///    it is large and their connection may be metered.
abstract final class UpdateCheck {
  /// The public keys a release may be signed by, base64, as they appear in
  /// docs/updates.md.
  ///
  /// Two of them, from the first release onwards, and that is the entire reason
  /// this is a list. A single key cannot be replaced: adding a second one takes
  /// an update, and shipping an update takes the key you no longer have. With a
  /// spare, a lost or compromised key is an afternoon — sign the next release
  /// with the spare, then ship a build whose list drops the old one and adds a
  /// fresh spare.
  ///
  /// The spare is never used until it has to be, and is kept somewhere the first
  /// one is not. Storing both together would make this list decoration.
  ///
  /// macOS is the exception that needs none of this: Sparkle falls back to
  /// Developer ID with a matching team when its own signature check fails,
  /// precisely so that a key can be rotated, and Apple reissues that
  /// certificate. Windows has no such fallback — the builds are unsigned — so
  /// there this list is the only thing that makes a lost key survivable.
  static const trustedKeys = [
    'FC7JiwkRA+FUJO36lY3VHWQGuQ7Mqm3e0xKbO2S98/E=',
    'YO9ZAcc1L0Ugzn84y5DS+md61cOU7wT3lf9PQ6xkZYk=',
  ];

  /// A static file, not an API.
  ///
  /// api.github.com allows sixty unauthenticated requests an hour per IP, and
  /// this check goes through the tunnel — so everyone sharing an exit node would
  /// share one quota and all but the first few would be refused. The busier the
  /// node, the more broken updates would become, which is exactly backwards.
  static const manifestUrl = 'https://teamgdb.github.io/Caelo/latest.json';

  /// No version in it. A user agent reaches every server that answers, and one
  /// that named the build would sort installations into groups for anybody
  /// counting. This says which program is asking and nothing else.
  static const userAgent = 'Caelo';

  static const timeout = Duration(seconds: 20);

  /// The largest manifest worth reading. It lists a handful of files; anything
  /// beyond this is a mistake or somebody seeing what happens if they stream at
  /// us, and reading it to find out would be the mistake.
  static const maxBytes = 256 * 1024;

  /// Whether a newer build exists, or null when this one is current, when the
  /// person has turned checking off, or when the answer could not be had.
  ///
  /// A failure is null rather than an exception: nobody asked for this, it
  /// happens on a timer, and a network error while quietly checking is not an
  /// event worth putting in front of anyone.
  static Future<AvailableUpdate?> look({
    Future<String> Function(String url)? fetch,
    Future<bool> Function()? enabled,
  }) async {
    final allowed = await (enabled ?? SettingsStore.updateChecks)();
    // Read before anything else touches the network. The switch has to stop the
    // request, not filter its result.
    if (!allowed) return null;

    try {
      final body = await (fetch ?? _fetch)(manifestUrl);
      return read(body);
    } on Object catch (error) {
      Diagnostics.record('update check failed', error: error);
      return null;
    }
  }

  /// Parses a manifest and returns what is newer than this build.
  ///
  /// Separate from fetching so that the comparison can be tested without a
  /// network, and so that a manifest naming a platform we are not running on is
  /// unambiguously nothing rather than an error.
  @visibleForTesting
  static AvailableUpdate? read(String body) {
    final document = jsonDecode(body) as Map<String, dynamic>;
    final build = document['build'] as int?;
    if (build == null || build <= appBuild) return null;

    final artifacts = document['artifacts'] as Map<String, dynamic>?;
    final artifact = artifacts?[artifactKey] as Map<String, dynamic>?;
    // A manifest that carries no file for this platform is not an update. This
    // is the ordinary state on Linux, where upgrading is the package manager's
    // job and the manifest exists only so a line of text can say a newer
    // version is out.
    if (artifact == null) return null;

    return AvailableUpdate(
      version: document['version'] as String? ?? '',
      build: build,
      url: artifact['url'] as String? ?? '',
      sizeBytes: artifact['size'] as int? ?? 0,
      sha256: artifact['sha256'] as String? ?? '',
      signature: artifact['ed25519'] as String? ?? '',
      notesUrl: document['notes'] as String? ?? '',
    );
  }

  /// Which file in the manifest belongs to this machine.
  ///
  /// Android is per-architecture: installing the x86_64 build over an arm64-v8a
  /// installation fails, and always taking the universal one means downloading
  /// roughly three architectures to use one.
  static String get artifactKey {
    if (Platform.isMacOS) return 'macos-dmg';
    if (Platform.isWindows) return 'windows-setup-x64';
    if (Platform.isLinux) return 'linux-appimage-x64';
    if (Platform.isAndroid) return androidKeyFor(_abi);
    return 'none';
  }

  /// The Android split for an architecture, kept separate from [artifactKey] so
  /// that it can be exercised anywhere. Reached only on Android, which is not
  /// where the tests run — folded into the platform switch it would have been
  /// untested code with a test next to it saying otherwise.
  @visibleForTesting
  static String androidKeyFor(String abi) => switch (abi) {
    'arm64-v8a' => 'android-arm64-v8a',
    'armeabi-v7a' => 'android-armeabi-v7a',
    'x86_64' => 'android-x86_64',
    // An architecture we publish no split for still gets the universal build
    // rather than nothing at all.
    _ => 'android-universal',
  };

  /// Whether a file downloaded for [update] is one we published.
  ///
  /// Checking the SHA-256 from the manifest is not a substitute: whoever could
  /// hand over a different file could hand over a manifest describing it. The
  /// signature is the only part an attacker cannot produce, which is why it
  /// rather than the digest decides.
  static Future<bool> isOurs({
    required String path,
    required AvailableUpdate update,
  }) async {
    if (update.signature.isEmpty) return false;
    try {
      await CoreLibrary.verifyRelease(
        path: path,
        signature: update.signature,
        trustedKeys: trustedKeys,
      );
      return true;
    } on Object catch (error) {
      Diagnostics.record('a downloaded update was not ours', error: error);
      return false;
    }
  }

  /// Overridden in tests, which do not run on the architecture they describe.
  @visibleForTesting
  static String? debugAbi;

  static String get _abi => debugAbi ?? _hostAbi();

  static String _hostAbi() {
    // Dart reports the architecture in the version banner and nowhere more
    // directly. Reading it here rather than adding a plugin for one string.
    final banner = Platform.version;
    if (banner.contains('arm64')) return 'arm64-v8a';
    if (banner.contains('arm')) return 'armeabi-v7a';
    if (banner.contains('x64')) return 'x86_64';
    return 'universal';
  }

  static Future<String> _fetch(String url) async {
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final request = await client.getUrl(Uri.parse(url)).timeout(timeout);
      // Everything set here is a constant. Nothing derived from this
      // installation, its configuration or its history may be added: the
      // property being defended is that two copies send the same bytes.
      request.headers.set(HttpHeaders.userAgentHeader, userAgent);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      // Caching would make the request vary by what this copy fetched last,
      // which is a weak identifier and an easy one to forget about.
      request.headers.set(HttpHeaders.cacheControlHeader, 'no-store');

      final response = await request.close().timeout(timeout);
      if (response.statusCode >= 400) {
        throw HttpException('the server answered ${response.statusCode}');
      }

      final buffer = <int>[];
      await for (final chunk in response) {
        buffer.addAll(chunk);
        if (buffer.length > maxBytes) {
          throw const HttpException('the manifest is larger than it should be');
        }
      }
      return utf8.decode(buffer);
    } finally {
      client.close(force: true);
    }
  }
}
