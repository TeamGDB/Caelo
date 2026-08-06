import 'package:flutter/cupertino.dart';

import '../core/tunnel.dart';
import '../core/tunnel_controller.dart';
import '../l10n/generated/app_localizations.dart';
import '../theme/app_theme.dart';
import '../theme/palette.dart';
import 'settings_screen.dart';
import 'widgets/power_button.dart';

/// The whole product, more or less: a button, a word, and a line of small text
/// saying what you got. Everything else is a settings screen you should never
/// need to open.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = TunnelScope.of(context);
    final status = controller.value;
    final l10n = AppLocalizations.of(context);

    return CupertinoPageScaffold(
      backgroundColor: CaeloColors.background,
      child: Stack(
        children: [
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                PowerButton(
                  phase: status.phase,
                  onPressed: controller.toggle,
                  semanticLabel: status.phase == TunnelPhase.connected
                      ? l10n.disconnect
                      : l10n.connect,
                ),
                const SizedBox(height: CaeloSpace.lg),
                _StatusLine(status: status),
                const SizedBox(height: CaeloSpace.xs + 2),
                _DetailLine(status: status),
                const SizedBox(height: CaeloSpace.xl),
                _ReconnectAction(
                  visible: status.phase == TunnelPhase.connected,
                  onPressed: controller.reconnectDifferently,
                ),
              ],
            ),
          ),
          // Bottom corner rather than top: the title bar is transparent, so
          // anything up there would be sitting in the window's drag region —
          // and settings should be reachable without inviting a visit.
          const Positioned(
            bottom: CaeloSpace.sm,
            right: CaeloSpace.sm,
            child: _SettingsButton(),
          ),
        ],
      ),
    );
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.status});

  final TunnelStatus status;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    final (text, colour) = switch (status.phase) {
      TunnelPhase.disconnected => (l10n.statusDisconnected, CaeloColors.muted),
      TunnelPhase.connecting => (l10n.statusConnecting, CaeloColors.foreground),
      TunnelPhase.connected => (l10n.statusConnected, CaeloColors.foreground),
      TunnelPhase.disconnecting => (
        l10n.statusDisconnecting,
        CaeloColors.muted,
      ),
      TunnelPhase.failed => (l10n.statusFailed, CaeloColors.danger),
    };

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      child: Text(
        text,
        key: ValueKey(text),
        style: CaeloTheme.status.copyWith(color: colour),
      ),
    );
  }
}

/// The line that answers "what am I actually on?" without being asked.
class _DetailLine extends StatelessWidget {
  const _DetailLine({required this.status});

  final TunnelStatus status;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    final parts = <String>[
      if (status.hasNode) l10n.viaNode(status.node!),
      if (status.protocol != null && status.pingMs != null)
        l10n.protocolAndPing(status.protocol!.label, status.pingMs!),
    ];

    // Nothing configured yet is worth saying out loud; a tunnel that is simply
    // down is not, so the line stays empty rather than repeating the status.
    final text = switch (parts.isEmpty) {
      true when status.phase == TunnelPhase.disconnected => l10n.noSubscription,
      true => '',
      false => parts.join('  ·  '),
    };

    return SizedBox(
      height: 18,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        child: Text(text, key: ValueKey(text), style: CaeloTheme.caption),
      ),
    );
  }
}

/// Present only when it can do something, and quiet even then. Reaching for it
/// means the automatic choice was wrong, which should be rare.
class _ReconnectAction extends StatelessWidget {
  const _ReconnectAction({required this.visible, required this.onPressed});

  final bool visible;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: visible ? 1 : 0,
      duration: const Duration(milliseconds: 220),
      child: IgnorePointer(
        ignoring: !visible,
        child: CupertinoButton(
          padding: const EdgeInsets.symmetric(
            horizontal: CaeloSpace.md,
            vertical: CaeloSpace.sm,
          ),
          minimumSize: Size.zero,
          onPressed: onPressed,
          child: Text(
            AppLocalizations.of(context).reconnectDifferently,
            style: CaeloTheme.caption.copyWith(color: CaeloColors.dim),
          ),
        ),
      ),
    );
  }
}

class _SettingsButton extends StatelessWidget {
  const _SettingsButton();

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      padding: const EdgeInsets.all(CaeloSpace.sm),
      minimumSize: Size.zero,
      onPressed: () => Navigator.of(context).push(
        CupertinoPageRoute<void>(builder: (_) => const SettingsScreen()),
      ),
      child: Icon(
        CupertinoIcons.gear_alt,
        size: 20,
        color: CaeloColors.dim,
        semanticLabel: AppLocalizations.of(context).settings,
      ),
    );
  }
}
