import 'package:flutter/cupertino.dart';

import '../core/tunnel.dart';
import '../core/tunnel_controller.dart';
import '../l10n/generated/app_localizations.dart';
import '../theme/app_theme.dart';
import '../theme/palette.dart';
import 'settings_screen.dart';
import 'widgets/caelo_surface.dart';
import 'widgets/power_button.dart';

/// The whole product, more or less: a button, a word, and a line of small text
/// saying what you got. Everything else is a settings screen you should never
/// need to open.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = CaeloColors.of(context);
    final controller = TunnelScope.of(context);
    final status = controller.value;
    final l10n = AppLocalizations.of(context);
    final buttonLabel = switch (status.phase) {
      TunnelPhase.disconnected => l10n.connect,
      TunnelPhase.connecting => l10n.statusConnecting,
      TunnelPhase.connected => l10n.statusConnected,
      TunnelPhase.disconnecting => l10n.statusDisconnecting,
      TunnelPhase.failed => l10n.statusFailed,
    };

    return CupertinoPageScaffold(
      backgroundColor: palette.background,
      child: CaeloPageSurface(
        child: SafeArea(
          child: Stack(
            children: [
              Center(
                child: Padding(
                  padding: EdgeInsets.only(
                    bottom: status.hasNode ? 104 : 0,
                    left: CaeloSpace.gutter,
                    right: CaeloSpace.gutter,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      PowerButton(
                        phase: status.phase,
                        label: buttonLabel,
                        onPressed: controller.toggle,
                        semanticLabel:
                            status.phase == TunnelPhase.connected ||
                                status.phase == TunnelPhase.connecting
                            ? l10n.disconnect
                            : l10n.connect,
                      ),
                      const SizedBox(height: CaeloSpace.md),
                      _ConfigurationHint(
                        visible:
                            !controller.hasConfiguration && !status.hasNode,
                      ),
                      const SizedBox(height: CaeloSpace.sm),
                      // The tunnel is real but it lives on a userspace stack
                      // inside this process. Never imply the machine is covered.
                      _Caveat(
                        visible:
                            status.phase == TunnelPhase.connected &&
                            !controller.coversWholeMachine,
                      ),
                      const SizedBox(height: CaeloSpace.control),
                      _ReconnectAction(
                        visible: status.phase == TunnelPhase.connected,
                        onPressed: controller.reconnectDifferently,
                      ),
                    ],
                  ),
                ),
              ),
              if (status.hasNode)
                Positioned(
                  left: CaeloSpace.md,
                  right: CaeloSpace.md,
                  bottom: CaeloSpace.control,
                  child: _ConnectionPanel(status: status),
                ),
              // Bottom corner rather than top: the desktop title bar can use
              // the top edge as a drag region. Lift the action over the real
              // connection panel when that panel is present.
              Positioned(
                bottom: status.hasNode ? 128 : CaeloSpace.control,
                right: CaeloSpace.control,
                child: const _SettingsButton(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ConfigurationHint extends StatelessWidget {
  const _ConfigurationHint({required this.visible});

  final bool visible;

  @override
  Widget build(BuildContext context) {
    final palette = CaeloColors.of(context);
    final l10n = AppLocalizations.of(context);
    return SizedBox(
      height: 18,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: CaeloMotion.quick,
        child: Text(
          visible ? l10n.noConfig : '',
          style: CaeloTheme.caption(palette),
        ),
      ),
    );
  }
}

/// Real connection data reported by the core. The panel does not render until
/// a node is present and never manufactures a flag, grade or latency.
class _ConnectionPanel extends StatelessWidget {
  const _ConnectionPanel({required this.status});

  final TunnelStatus status;

  @override
  Widget build(BuildContext context) {
    final palette = CaeloColors.of(context);
    final l10n = AppLocalizations.of(context);
    final details = <String>[
      if (status.protocol != null) status.protocol!.label,
      if (status.pingMs != null) l10n.latency(status.pingMs!),
    ];

    return CaeloContentWidth(
      child: CaeloPanel(
        radius: CaeloRadius.cardAll,
        padding: const EdgeInsets.symmetric(
          horizontal: CaeloSpace.gutter,
          vertical: CaeloSpace.control,
        ),
        child: Row(
          children: [
            Container(
              width: CaeloSize.minimumTarget,
              height: CaeloSize.minimumTarget,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: palette.accentSurface,
                border: Border.all(color: palette.accentBorder),
              ),
              child: Icon(
                CupertinoIcons.globe,
                color: palette.accent,
                size: 24,
              ),
            ),
            const SizedBox(width: CaeloSpace.control),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    l10n.currentConnection,
                    style: CaeloTheme.caption(palette),
                  ),
                  const SizedBox(height: CaeloSpace.xs),
                  Text(
                    status.node!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: CaeloTheme.body(
                      palette,
                    ).copyWith(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
            if (details.isNotEmpty) ...[
              const SizedBox(width: CaeloSpace.control),
              Text(
                details.join(' · '),
                textAlign: TextAlign.end,
                style: CaeloTheme.caption(palette).copyWith(
                  color: status.pingMs != null && status.pingMs! < 60
                      ? palette.accent
                      : palette.muted,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// States plainly what "connected" currently covers. It disappears when the
/// NetworkExtension lands and the answer becomes "everything".
class _Caveat extends StatelessWidget {
  const _Caveat({required this.visible});

  final bool visible;

  @override
  Widget build(BuildContext context) {
    final palette = CaeloColors.of(context);
    return SizedBox(
      height: 16,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: const Duration(milliseconds: 220),
        child: Text(
          AppLocalizations.of(context).localTunnelOnly,
          style: CaeloTheme.caption(
            palette,
          ).copyWith(color: palette.dim, fontSize: 11),
        ),
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
    final palette = CaeloColors.of(context);
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
            style: CaeloTheme.caption(palette).copyWith(color: palette.dim),
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
    final palette = CaeloColors.of(context);
    return CaeloIconButton(
      icon: CupertinoIcons.gear_alt,
      semanticLabel: AppLocalizations.of(context).settings,
      onPressed: () => Navigator.of(
        context,
      ).push(CupertinoPageRoute<void>(builder: (_) => const SettingsScreen())),
      foreground: palette.muted,
    );
  }
}
