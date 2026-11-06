import 'dart:async';

import 'package:flutter/cupertino.dart';

import '../core/android_installer.dart';
import '../core/update_download.dart';
import '../core/update_flow.dart';
import '../l10n/generated/app_localizations.dart';

/// Looks for a newer build on its own and offers it on Home (#133).
///
/// The switch in Settings has defaulted to on since #51, yet on Android
/// nothing looked unless somebody opened Settings and pressed Check now, so a
/// person who installed a release never heard of the next one. This checks
/// at every launch and every time the app comes back (#148), at most once
/// per [every], and asks before
/// downloading anything. [UpdateCheck] honours the switch.
class UpdatePrompt extends StatefulWidget {
  const UpdatePrompt({
    required this.child,
    this.flow,
    this.enabled,
    // A floor, not a schedule: coming back from a system dialog (the VPN
    // prompt, the installer) is a return too, and checking twice within a
    // minute would only show the same offer twice (#148).
    this.every = const Duration(minutes: 1),
    super.key,
  });

  final Widget child;

  /// A seam for tests; the platform flow otherwise.
  final UpdateFlow? flow;

  /// Whether this platform updates itself through [UpdateFlow].
  final bool? enabled;
  final Duration every;

  @override
  State<UpdatePrompt> createState() => _UpdatePromptState();
}

class _UpdatePromptState extends State<UpdatePrompt>
    with WidgetsBindingObserver {
  late final UpdateFlow _flow = widget.flow ?? UpdateFlow();
  DateTime? _lastCheck;
  bool _showing = false;

  bool get _enabled => widget.enabled ?? UpdateFlow.isSupported;

  @override
  void initState() {
    super.initState();
    if (!_enabled) return;
    WidgetsBinding.instance.addObserver(this);
    _flow.addListener(_onStage);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // What the last hand-over to the installer came to (#73), then whether
      // there is something newer.
      await _flow.reconcile();
      if (_flow.stage == UpdateStage.idle) unawaited(_check());
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    unawaited(_flow.resumed());
    final last = _lastCheck;
    if (last == null || DateTime.now().difference(last) >= widget.every) {
      unawaited(_check());
    }
  }

  Future<void> _check() async {
    if (_flow.stage != UpdateStage.idle) return;
    _lastCheck = DateTime.now();
    await _flow.check();
    // Nothing newer is not news when nobody asked.
    if (_flow.stage == UpdateStage.current) _flow.dismiss();
  }

  void _onStage() {
    if (!mounted || _showing) return;
    final stage = _flow.stage;
    if (stage == UpdateStage.found ||
        stage == UpdateStage.needsPermission ||
        stage == UpdateStage.handOverFailed ||
        stage == UpdateStage.notInstalled ||
        stage == UpdateStage.failed) {
      unawaited(_show(stage));
    }
  }

  Future<void> _show(UpdateStage stage) async {
    _showing = true;
    final l10n = AppLocalizations.of(context);
    final update = _flow.available;
    try {
      await showCupertinoDialog<void>(
        context: context,
        builder: (dialog) => CupertinoAlertDialog(
          title: Text(switch (stage) {
            UpdateStage.found => l10n.updateFound(update?.version ?? ''),
            UpdateStage.needsPermission => l10n.checkForUpdates,
            UpdateStage.notInstalled => l10n.updateNotInstalled,
            _ => l10n.updateFailed,
          }),
          content: switch (stage) {
            UpdateStage.found => null,
            UpdateStage.needsPermission => Text(l10n.updateNeedsPermission),
            UpdateStage.notInstalled => Text(
              l10n.updateNotInstalledExplanation,
            ),
            UpdateStage.handOverFailed => Text(
              _flow.needsDownload
                  ? l10n.updateHandOverFailed
                  : l10n.updateLinuxFailed,
            ),
            _ => Text(
              _flow.failure == DownloadFailure.untrusted
                  ? l10n.updateNotOurs
                  : l10n.updateFailed,
            ),
          },
          actions: [
            CupertinoDialogAction(
              key: const ValueKey('update-later'),
              onPressed: () {
                Navigator.of(dialog).pop();
                _flow.dismiss();
              },
              child: Text(l10n.cancel),
            ),
            if (stage == UpdateStage.found)
              CupertinoDialogAction(
                key: const ValueKey('update-now'),
                isDefaultAction: true,
                onPressed: () {
                  Navigator.of(dialog).pop();
                  unawaited(_flow.download());
                },
                child: Text(
                  _flow.needsDownload
                      ? l10n.updateDownload(
                          ((update?.sizeBytes ?? 0) / 1048576).toStringAsFixed(
                            0,
                          ),
                        )
                      : l10n.updateInstall,
                ),
              ),
            if (stage == UpdateStage.needsPermission)
              CupertinoDialogAction(
                isDefaultAction: true,
                onPressed: () {
                  Navigator.of(dialog).pop();
                  unawaited(AndroidInstaller.requestPermission());
                  _flow.dismiss();
                },
                child: Text(l10n.updateOpenSettings),
              ),
            if (stage == UpdateStage.notInstalled)
              CupertinoDialogAction(
                isDefaultAction: true,
                onPressed: () {
                  Navigator.of(dialog).pop();
                  _flow.dismiss();
                  unawaited(_flow.check());
                },
                child: Text(l10n.updateTryAgain),
              ),
          ],
        ),
      );
    } finally {
      _showing = false;
    }
  }

  @override
  void dispose() {
    if (_enabled) {
      WidgetsBinding.instance.removeObserver(this);
      _flow.removeListener(_onStage);
      if (widget.flow == null) _flow.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Downloading tens of megabytes with nothing on screen reads as a press
    // that did nothing.
    return ListenableBuilder(
      listenable: _flow,
      builder: (context, child) => Stack(
        children: [
          child!,
          if (_flow.stage == UpdateStage.downloading ||
              _flow.stage == UpdateStage.installing)
            Positioned(
              left: 16,
              right: 16,
              bottom: 24,
              child: SafeArea(
                child: DecoratedBox(
                  key: const ValueKey('update-progress'),
                  decoration: BoxDecoration(
                    color: CupertinoColors.systemBackground.resolveFrom(
                      context,
                    ),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: const [
                      BoxShadow(color: Color(0x33000000), blurRadius: 16),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      children: [
                        const CupertinoActivityIndicator(),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _flow.stage == UpdateStage.installing
                                ? AppLocalizations.of(
                                    context,
                                  ).updateInstallingNow
                                : '${AppLocalizations.of(context).updateDownloading} '
                                      '${(_flow.progress * 100).toStringAsFixed(0)}%',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      child: widget.child,
    );
  }
}
