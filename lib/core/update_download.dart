import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'app_storage.dart';
import 'diagnostics.dart';
import 'update_check.dart';

/// Why a download did not end in something installable.
///
/// Separate cases because the remedies differ: a network that gave out is worth
/// retrying, and a file that failed verification is not — it is either a
/// corrupted transfer or somebody handing us a different program, and Caelo
/// cannot tell which. Both mean the same thing to the person, though, which is
/// why neither message speculates.
enum DownloadFailure {
  /// The transfer did not complete.
  unreachable,

  /// It completed, and the result is not ours.
  ///
  /// Not "corrupt": whoever could serve a different file could serve a manifest
  /// describing it, so the only claim that can be made is that the signature
  /// does not match a key this build trusts.
  untrusted,

  /// There was nowhere to put it.
  noRoom,
}

class DownloadFailed implements Exception {
  const DownloadFailed(this.reason);

  final DownloadFailure reason;

  @override
  String toString() => switch (reason) {
    DownloadFailure.unreachable => 'the download did not finish',
    DownloadFailure.untrusted => 'the downloaded file was not signed by Caelo',
    DownloadFailure.noRoom => 'there was no room to save the download',
  };
}

/// Fetches an update and proves it is ours before anything can run it.
///
/// The order is the whole point: **verify, then hand over.** A file that has
/// been given to the system installer is a file that may already have run, so
/// the check cannot come afterwards, and it cannot be optional because on
/// Android and Windows there is no second opinion — no Gatekeeper, and on
/// Windows no Authenticode signature either.
///
/// The SHA-256 in the manifest is not what decides. It is useful for spotting a
/// transfer that went wrong, but it proves nothing against somebody who can
/// serve files: they would serve a manifest describing what they sent. Only the
/// signature is something they cannot produce.
abstract final class UpdateDownload {
  /// Where a partly-fetched update lives.
  ///
  /// Its own name, and replaced rather than appended to, so an interrupted
  /// download cannot be resumed into something half of one version and half of
  /// another — which would fail verification, but only after using somebody's
  /// bandwidth twice.
  static const fileName = 'update-pending';

  @visibleForTesting
  static Future<File> Function(String) file = AppStorage.file;

  /// Downloads [update], checks it, and returns the file to install.
  ///
  /// Throws [DownloadFailed]. Progress is reported from 0 to 1 if [onProgress]
  /// is given; a download with no visible progress reads as a frozen app, and
  /// these are tens of megabytes.
  static Future<File> fetch(
    AvailableUpdate update, {
    void Function(double)? onProgress,
    Future<bool> Function(String path, AvailableUpdate update)? verify,
  }) async {
    final target = await file('$fileName${_suffix(update.url)}');

    try {
      await _download(update, target, onProgress);
    } on DownloadFailed {
      await _discard(target);
      rethrow;
    } on Object catch (error) {
      await _discard(target);
      Diagnostics.record('downloading an update failed', error: error);
      throw const DownloadFailed(DownloadFailure.unreachable);
    }

    // Wrapped rather than passed directly. UpdateCheck.isOurs takes named
    // parameters, and `verify ?? UpdateCheck.isOurs` has no common function
    // type, so Dart infers plain `Function` and the call becomes dynamic --
    // which compiled cleanly and threw NoSuchMethodError on a device (#71).
    // Every test injected `verify`, so the default was never once executed.
    final check =
        verify ??
        (String path, AvailableUpdate update) =>
            UpdateCheck.isOurs(path: path, update: update);

    final ours = await check(target.path, update);
    if (!ours) {
      // Removed rather than kept for inspection. A file that failed this check
      // is one somebody may have chosen for us, and leaving it on disk with a
      // plausible name is how it later gets opened by accident.
      await _discard(target);
      throw const DownloadFailed(DownloadFailure.untrusted);
    }

    return target;
  }

  static Future<void> _download(
    AvailableUpdate update,
    File target,
    void Function(double)? onProgress,
  ) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 30);
    try {
      final request = await client.getUrl(Uri.parse(update.url));
      // The same as every other request Caelo makes on its own: nothing that
      // distinguishes this installation from any other.
      request.headers.set(HttpHeaders.userAgentHeader, UpdateCheck.userAgent);
      final response = await request.close();

      if (response.statusCode >= 400) {
        throw const DownloadFailed(DownloadFailure.unreachable);
      }

      final sink = target.openWrite();
      var written = 0;
      try {
        await for (final chunk in response) {
          written += chunk.length;
          // The manifest says how large this should be. Anything past it is
          // either a mistake or somebody streaming at us to fill the disk, and
          // finding out which by continuing would be the mistake.
          if (update.sizeBytes > 0 && written > update.sizeBytes) {
            throw const DownloadFailed(DownloadFailure.unreachable);
          }
          sink.add(chunk);
          if (onProgress != null && update.sizeBytes > 0) {
            onProgress(written / update.sizeBytes);
          }
        }
      } finally {
        await sink.close();
      }

      // A transfer that stopped early leaves a file that is a prefix of the
      // right one. It would fail verification anyway; failing here says why.
      if (update.sizeBytes > 0 && written != update.sizeBytes) {
        throw const DownloadFailed(DownloadFailure.unreachable);
      }
    } on FileSystemException {
      throw const DownloadFailed(DownloadFailure.noRoom);
    } finally {
      client.close(force: true);
    }
  }

  static Future<void> _discard(File target) async {
    try {
      if (await target.exists()) await target.delete();
    } on Object {
      // Nothing useful to do about it, and the caller is already reporting a
      // failure they can act on.
    }
  }

  /// Keeps the extension, because the system installer on Android decides what
  /// to do with a file partly by its name.
  static String _suffix(String url) {
    final path = Uri.tryParse(url)?.path ?? '';
    final dot = path.lastIndexOf('.');
    return dot == -1 ? '' : path.substring(dot);
  }
}
