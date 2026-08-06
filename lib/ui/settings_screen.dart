import 'package:flutter/cupertino.dart';

import '../l10n/generated/app_localizations.dart';
import '../theme/app_theme.dart';
import '../theme/palette.dart';

/// Settings exist for the cases the automatic choice cannot cover. They are not
/// a control panel, and the main screen should never send you here.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return CupertinoPageScaffold(
      backgroundColor: CaeloColors.background,
      navigationBar: CupertinoNavigationBar(
        backgroundColor: CaeloColors.ink900,
        border: const Border(
          bottom: BorderSide(color: CaeloColors.ink700, width: 0),
        ),
        middle: Text(l10n.settings),
      ),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: CaeloSpace.lg),
          children: [
            _Section(
              header: l10n.subscriptions,
              children: [
                _Row(
                  label: l10n.addSubscription,
                  labelColour: CaeloColors.accent,
                  // Lands with the core: nothing to add a subscription to yet.
                  onTap: null,
                ),
              ],
            ),
            _Section(
              header: l10n.appearanceLanguage,
              children: [
                _Row(label: l10n.appearanceLanguage, value: l10n.languageSystem),
              ],
            ),
            _Section(
              header: l10n.about,
              children: [
                const _Row(label: 'Caelo', value: '0.1.0'),
                _Row(label: l10n.licence, value: 'GPL-3.0-or-later'),
                _Row(label: l10n.sourceCode, value: 'github.com/TeamGDB/Caelo'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.header, required this.children});

  final String header;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
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
            child: Text(header.toUpperCase(), style: CaeloTheme.sectionHeader),
          ),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: CaeloSpace.md),
            decoration: BoxDecoration(
              color: CaeloColors.ink900,
              borderRadius: CaeloRadius.mediumAll,
              border: Border.all(color: CaeloColors.ink700, width: 1),
            ),
            child: Column(children: _separated(children)),
          ),
        ],
      ),
    );
  }

  static List<Widget> _separated(List<Widget> rows) {
    return [
      for (var i = 0; i < rows.length; i++) ...[
        if (i > 0)
          const Padding(
            padding: EdgeInsets.only(left: CaeloSpace.md),
            child: ColoredBox(
              color: CaeloColors.ink700,
              child: SizedBox(height: 1, width: double.infinity),
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
  });

  final String label;
  final String? value;
  final Color? labelColour;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    // Rows with no action yet are shown dimmed rather than hidden, so the shape
    // of the screen does not change once the core wires them up.
    final enabled = onTap != null || value != null;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: CaeloSpace.md,
          vertical: CaeloSpace.sm + CaeloSpace.xs,
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 15,
                  color: labelColour == null
                      ? CaeloColors.foreground
                      : labelColour!.withValues(alpha: enabled ? 1 : 0.4),
                ),
              ),
            ),
            if (value != null)
              Text(
                value!,
                style: CaeloTheme.rowValue,
                overflow: TextOverflow.ellipsis,
              ),
          ],
        ),
      ),
    );
  }
}
