import 'dart:async';
import 'package:flutter/cupertino.dart';

import '../core/config_store.dart';
import '../core/diagnostics.dart';
import '../core/ffi/core_library.dart';
import '../core/build_info.dart';
import '../core/android_installer.dart';
import '../core/desktop_updater.dart';
import '../core/update_download.dart';
import '../core/update_flow.dart';
import '../core/settings_store.dart';
import '../l10n/generated/app_localizations.dart';
import '../main.dart' show AccessScope, LocaleModeScope, ThemeModeScope;
import '../theme/app_theme.dart';
import '../theme/palette.dart';
import 'config_screen.dart';
import 'log_screen.dart';
import 'widgets/caelo_surface.dart';

/// Resolved once. The core's version cannot change while the app is running,
/// and a settings screen that re-crosses the FFI boundary on every rebuild is
/// paying for nothing.
CoreVersion? _core;
bool _coreResolved = false;

String _coreSummary(AppLocalizations l10n) {
  if (!_coreResolved) {
    _coreResolved = true;
    try {
      _core = CoreLibrary.version();
    } on Object {
      // A missing core is worth showing plainly rather than crashing the one
      // screen where you would go to find out what is wrong.
      _core = null;
    }
  }

  final core = _core;
  if (core == null) return l10n.coreUnavailable;
  return '${core.core} · AmneziaWG ${core.amneziaWg}';
}

/// Settings exist for the cases the automatic choice cannot cover. They are not
/// a control panel, and the main screen should never send you here.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  List<StoredConfig> configs = const [];

  /// Null until it has been read. Rendering a switch before then would show it
  /// off for a frame and then move it, which reads as the app changing the
  /// setting by itself.
  bool? updateChecks;

  /// Built once and kept: it holds the download in flight, and rebuilding it on
  /// every frame would lose the progress it is reporting.
  late final UpdateFlow updates = UpdateFlow()..addListener(_onUpdateStage);

  @override
  void initState() {
    super.initState();
    onConfigChanged();
    unawaited(_loadUpdateChecks());
  }

  @override
  void dispose() {
    updates.removeListener(_onUpdateStage);
    updates.dispose();
    super.dispose();
  }

  void _onUpdateStage() {
    if (!mounted) return;
    setState(() {});
    // Everything except a bare result wants a dialog. `current` deliberately
    // does not: "you are up to date" as a modal is a box somebody has to
    // dismiss to learn nothing.
    if (updates.stage == UpdateStage.found ||
        updates.stage == UpdateStage.needsPermission ||
        updates.stage == UpdateStage.failed) {
      unawaited(_showUpdateDialog());
    }
  }

  Future<void> _showUpdateDialog() async {
    final l10n = AppLocalizations.of(context);
    final stage = updates.stage;
    final update = updates.available;

    await showCupertinoDialog<void>(
      context: context,
      builder: (dialog) => CupertinoAlertDialog(
        title: Text(switch (stage) {
          UpdateStage.found => l10n.updateFound(update?.version ?? ''),
          UpdateStage.needsPermission => l10n.checkForUpdates,
          _ => l10n.updateFailed,
        }),
        content: Text(switch (stage) {
          UpdateStage.found => '',
          UpdateStage.needsPermission => l10n.updateNeedsPermission,
          _ =>
            updates.failure == DownloadFailure.untrusted
                ? l10n.updateNotOurs
                : l10n.updateFailed,
        }),
        actions: [
          CupertinoDialogAction(
            onPressed: () {
              Navigator.of(dialog).pop();
              updates.dismiss();
            },
            child: Text(l10n.cancel),
          ),
          if (stage == UpdateStage.found)
            CupertinoDialogAction(
              isDefaultAction: true,
              onPressed: () {
                Navigator.of(dialog).pop();
                unawaited(updates.download());
              },
              child: Text(
                l10n.updateDownload(
                  ((update?.sizeBytes ?? 0) / 1048576).toStringAsFixed(0),
                ),
              ),
            ),
          if (stage == UpdateStage.needsPermission)
            CupertinoDialogAction(
              isDefaultAction: true,
              onPressed: () {
                Navigator.of(dialog).pop();
                unawaited(AndroidInstaller.requestPermission());
                updates.dismiss();
              },
              child: Text(l10n.updateOpenSettings),
            ),
        ],
      ),
    );
  }

  String _updateRowValue(AppLocalizations l10n) => switch (updates.stage) {
    UpdateStage.checking => l10n.updateChecking,
    UpdateStage.current => l10n.updateCurrent,
    UpdateStage.downloading =>
      '${l10n.updateDownloading} ${(updates.progress * 100).toStringAsFixed(0)}%',
    UpdateStage.handedOver => l10n.updateInstalling,
    _ => '',
  };

  Future<void> _loadUpdateChecks() async {
    final on = await SettingsStore.updateChecks();
    if (mounted) setState(() => updateChecks = on);
  }

  Future<void> onConfigChanged() async {
    final loaded = await ConfigStore.list();
    if (mounted) setState(() => configs = loaded);
  }

  String _themeLabel(AppLocalizations l10n, CaeloThemeMode? mode) =>
      switch (mode) {
        CaeloThemeMode.light => l10n.themeLight,
        CaeloThemeMode.dark => l10n.themeDark,
        _ => l10n.themeSystem,
      };

  String _localeLabel(AppLocalizations l10n, CaeloLocaleMode? mode) =>
      switch (mode) {
        CaeloLocaleMode.russian => l10n.languageRussian,
        CaeloLocaleMode.english => l10n.languageEnglish,
        _ => l10n.languageSystem,
      };

  Future<void> _pickTheme(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final scope = ThemeModeScope.maybeOf(context);
    if (scope == null) return;

    final chosen = await showCupertinoModalPopup<CaeloThemeMode>(
      context: context,
      builder: (sheetContext) => CupertinoActionSheet(
        title: Text(l10n.theme),
        actions: [
          for (final mode in CaeloThemeMode.values)
            CupertinoActionSheetAction(
              onPressed: () => Navigator.of(sheetContext).pop(mode),
              isDefaultAction: mode == scope.mode,
              child: Text(_themeLabel(l10n, mode)),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(sheetContext).pop(),
          child: Text(l10n.done),
        ),
      ),
    );

    if (chosen != null) await scope.onChanged(chosen);
  }

  Future<void> _pickLocale(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final scope = LocaleModeScope.maybeOf(context);
    if (scope == null) return;

    final chosen = await showCupertinoModalPopup<CaeloLocaleMode>(
      context: context,
      builder: (sheetContext) => CupertinoActionSheet(
        title: Text(l10n.appearanceLanguage),
        actions: [
          for (final mode in CaeloLocaleMode.values)
            CupertinoActionSheetAction(
              onPressed: () => Navigator.of(sheetContext).pop(mode),
              isDefaultAction: mode == scope.mode,
              child: Text(_localeLabel(l10n, mode)),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(sheetContext).pop(),
          child: Text(l10n.done),
        ),
      ),
    );

    if (chosen != null) await scope.onChanged(chosen);
  }

  @override
  Widget build(BuildContext context) {
    final palette = CaeloColors.of(context);
    final l10n = AppLocalizations.of(context);
    final themeScope = ThemeModeScope.maybeOf(context);
    final localeScope = LocaleModeScope.maybeOf(context);
    final accessScope = AccessScope.maybeOf(context);

    return CupertinoPageScaffold(
      backgroundColor: palette.background,
      navigationBar: CupertinoNavigationBar(
        backgroundColor: palette.surface1,
        border: Border(bottom: BorderSide(color: palette.border, width: 0)),
        middle: Text(l10n.settings),
      ),
      child: CaeloPageSurface(
        child: SafeArea(
          child: CaeloContentWidth(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: CaeloSpace.lg),
              children: [
                _Section(
                  header: l10n.subscriptions,
                  children: [
                    for (final config in configs)
                      _Row(
                        label: config.name,
                        value: l10n.customConfiguration,
                        onTap: () async {
                          await Navigator.of(context).push(
                            CupertinoPageRoute<void>(
                              builder: (_) => ConfigScreen(config: config),
                            ),
                          );
                          onConfigChanged();
                        },
                      ),
                    _Row(
                      label: l10n.addConfiguration,
                      labelColour: palette.accent,
                      onTap: () async {
                        await Navigator.of(context).push(
                          CupertinoPageRoute<void>(
                            builder: (_) => const ConfigScreen(),
                          ),
                        );
                        onConfigChanged();
                      },
                    ),
                    if (accessScope != null)
                      _Row(
                        label: l10n.forgetAccount,
                        labelColour: palette.danger,
                        onTap: () {
                          final changeAccess = accessScope.onChanged;
                          Navigator.of(
                            context,
                          ).popUntil((route) => route.isFirst);
                          changeAccess(false);
                        },
                      ),
                  ],
                ),
                _Section(
                  header: l10n.appearance,
                  children: [
                    _Row(
                      label: l10n.theme,
                      value: _themeLabel(l10n, themeScope?.mode),
                      onTap: themeScope == null
                          ? null
                          : () => _pickTheme(context),
                    ),
                    _Row(
                      label: l10n.appearanceLanguage,
                      value: _localeLabel(l10n, localeScope?.mode),
                      onTap: localeScope == null
                          ? null
                          : () => _pickLocale(context),
                    ),
                  ],
                ),
                _Section(
                  header: l10n.updates,
                  footer: l10n.updateCheckNote,
                  children: [
                    _Row(
                      label: l10n.checkForUpdates,
                      trailing: CupertinoSwitch(
                        value: updateChecks ?? false,
                        activeTrackColor: palette.accent,
                        onChanged: updateChecks == null
                            ? null
                            : (on) async {
                                await SettingsStore.setUpdateChecks(on);
                                // The updater is told rather than left to read
                                // the file: it schedules its own work, and one
                                // that learned about this at the next launch
                                // would keep checking until then.
                                await DesktopUpdater.setEnabled(on);
                                if (mounted) setState(() => updateChecks = on);
                              },
                      ),
                    ),
                    if (DesktopUpdater.isSupported)
                      _Row(
                        label: l10n.checkNow,
                        onTap: () => unawaited(DesktopUpdater.checkNow()),
                      ),
                    // Android does its own: Sparkle owns the flow on macOS, and
                    // two things able to replace the application is one more
                    // than anything needs.
                    if (UpdateFlow.isSupported)
                      _Row(
                        label: l10n.checkNow,
                        value: _updateRowValue(l10n),
                        onTap: updates.stage == UpdateStage.downloading
                            ? null
                            : () => unawaited(updates.check()),
                      ),
                  ],
                ),
                _Section(
                  header: l10n.diagnostics,
                  footer: l10n.diagnosticLogNote,
                  children: [
                    _Row(
                      label: l10n.diagnosticLogOn,
                      trailing: CupertinoSwitch(
                        value: Diagnostics.enabled,
                        activeTrackColor: palette.accent,
                        onChanged: (on) async {
                          await Diagnostics.setEnabled(on);
                          if (mounted) setState(() {});
                        },
                      ),
                    ),
                    _Row(
                      label: l10n.viewLog,
                      onTap: () => Navigator.of(context).push(
                        CupertinoPageRoute<void>(
                          builder: (_) => const LogScreen(),
                        ),
                      ),
                    ),
                  ],
                ),
                _Section(
                  header: l10n.about,
                  children: [
                    const _Row(
                      label: 'Caelo',
                      value: '$appVersion ($appBuild)',
                    ),
                    _Row(label: l10n.core, value: _coreSummary(l10n)),
                    _Row(label: l10n.licence, value: 'GPL-3.0-or-later'),
                    _Row(
                      label: l10n.sourceCode,
                      value: 'github.com/TeamGDB/Caelo',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.header, required this.children, this.footer});

  final String header;
  final List<Widget> children;

  /// Explains a section whose consequences are not obvious from its rows.
  /// Anything that starts keeping a record of what someone does deserves one.
  final String? footer;

  @override
  Widget build(BuildContext context) {
    final palette = CaeloColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: CaeloSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              CaeloSpace.md + CaeloSpace.xs,
              0,
              CaeloSpace.md,
              CaeloSpace.sm,
            ),
            child: Text(
              header.toUpperCase(),
              style: CaeloTheme.sectionHeader(palette),
            ),
          ),
          CaeloPanel(
            margin: const EdgeInsets.symmetric(horizontal: CaeloSpace.md),
            radius: CaeloRadius.controlAll,
            child: Column(children: _separated(children, palette)),
          ),
          if (footer != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                CaeloSpace.md + CaeloSpace.xs,
                CaeloSpace.sm,
                CaeloSpace.md + CaeloSpace.xs,
                0,
              ),
              child: Text(footer!, style: CaeloTheme.caption(palette)),
            ),
        ],
      ),
    );
  }

  static List<Widget> _separated(List<Widget> rows, CaeloPalette palette) {
    return [
      for (var i = 0; i < rows.length; i++) ...[
        if (i > 0)
          Padding(
            padding: const EdgeInsets.only(left: CaeloSpace.md),
            child: ColoredBox(
              color: palette.border,
              child: const SizedBox(height: 1, width: double.infinity),
            ),
          ),
        rows[i],
      ],
    ];
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.label,
    this.value,
    this.labelColour,
    this.onTap,
    this.trailing,
  });

  final String label;
  final String? value;
  final Color? labelColour;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final palette = CaeloColors.of(context);
    // Rows with no action yet are shown dimmed rather than hidden, so the shape
    // of the screen does not change once the core wires them up.
    final enabled = onTap != null || value != null || trailing != null;

    return Semantics(
      button: onTap != null,
      enabled: enabled,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: CaeloSize.minimumTarget + CaeloSpace.sm,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: CaeloSpace.md),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 15,
                      color: labelColour == null
                          ? palette.foreground
                          : labelColour!.withValues(alpha: enabled ? 1 : 0.4),
                    ),
                  ),
                ),
                if (value != null)
                  Flexible(
                    child: Text(
                      value!,
                      style: CaeloTheme.rowValue(palette),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ?trailing,
                if (onTap != null) ...[
                  const SizedBox(width: CaeloSpace.sm),
                  Icon(
                    CupertinoIcons.chevron_forward,
                    size: 16,
                    color: palette.dim,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
