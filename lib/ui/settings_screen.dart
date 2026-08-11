import 'package:flutter/cupertino.dart';

import '../core/config_store.dart';
import '../core/diagnostics.dart';
import '../core/ffi/core_library.dart';
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
  bool hasConfig = false;

  @override
  void initState() {
    super.initState();
    onConfigChanged();
  }

  Future<void> onConfigChanged() async {
    final config = await ConfigStore.read();
    if (mounted) setState(() => hasConfig = config != null);
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
                    _Row(
                      label: l10n.configuration,
                      value: hasConfig
                          ? l10n.configurationInstalled
                          : l10n.configurationNone,
                      onTap: () async {
                        await Navigator.of(context).push(
                          CupertinoPageRoute<void>(
                            builder: (_) => const ConfigScreen(),
                          ),
                        );
                        onConfigChanged();
                      },
                    ),
                    _Row(
                      label: l10n.addSubscription,
                      labelColour: palette.accent,
                      // Lands with the subscription parser in the core.
                      onTap: null,
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
                    const _Row(label: 'Caelo', value: '0.1.0'),
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
