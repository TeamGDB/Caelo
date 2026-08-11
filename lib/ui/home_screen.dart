import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';

import '../core/tunnel.dart';
import '../core/tunnel_controller.dart';
import '../core/server_catalog.dart';
import '../l10n/generated/app_localizations.dart';
import '../theme/app_theme.dart';
import '../theme/palette.dart';
import 'settings_screen.dart';
import 'server_picker_sheet.dart';
import 'widgets/caelo_surface.dart';
import 'widgets/power_button.dart';

/// The product centre: one primary action and a persistent server surface.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = CaeloColors.of(context);
    final controller = TunnelScope.of(context);
    final status = controller.value;
    final l10n = AppLocalizations.of(context);
    final servers = ServerSelectionScope.of(context);
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
                    // The server surface permanently owns this space. Tunnel
                    // phase changes must never move the primary control.
                    bottom: 126,
                    left: CaeloSpace.gutter,
                    right: CaeloSpace.gutter,
                  ),
                  child: PowerButton(
                    phase: status.phase,
                    label: buttonLabel,
                    onPressed: controller.toggle,
                    semanticLabel:
                        status.phase == TunnelPhase.connected ||
                            status.phase == TunnelPhase.connecting
                        ? l10n.disconnect
                        : l10n.connect,
                  ),
                ),
              ),
              Positioned(
                left: CaeloSpace.md,
                right: CaeloSpace.md,
                bottom: CaeloSpace.control,
                child: _ServerPanel(
                  controller: servers,
                  locked: status.phase != TunnelPhase.disconnected,
                  limitedScope:
                      status.phase == TunnelPhase.connected &&
                      !controller.coversWholeMachine,
                ),
              ),
              // Mobile SafeArea starts below the status bar. macOS reports no
              // such inset for its transparent title bar, so reserve its chrome
              // explicitly and keep the button out of the traffic-light row.
              Positioned(
                top: defaultTargetPlatform == TargetPlatform.macOS
                    ? 36
                    : CaeloSpace.control,
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

/// Subscription server selection. While the backend is absent the controller
/// provides explicitly isolated presentation mocks; this widget never mutates
/// or fabricates [TunnelStatus].
class _ServerPanel extends StatelessWidget {
  const _ServerPanel({
    required this.controller,
    required this.locked,
    required this.limitedScope,
  });

  final ServerSelectionController controller;
  final bool locked;
  final bool limitedScope;

  Future<void> _choose(BuildContext context) async {
    if (locked || controller.servers.isEmpty) return;
    await showCaeloServerPicker(context, controller);
  }

  @override
  Widget build(BuildContext context) {
    final palette = CaeloColors.of(context);
    final l10n = AppLocalizations.of(context);
    final server = controller.selected;

    return CaeloContentWidth(
      child: GestureDetector(
        onTap: locked ? null : () => _choose(context),
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          height: 110,
          child: CaeloPanel(
            radius: CaeloRadius.cardAll,
            padding: const EdgeInsets.symmetric(
              horizontal: CaeloSpace.gutter,
              vertical: CaeloSpace.control,
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 54,
                  child: Text(
                    server?.flag ?? '—',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 30),
                  ),
                ),
                const SizedBox(width: CaeloSpace.control),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        l10n.selectedServer,
                        style: CaeloTheme.caption(palette),
                      ),
                      const SizedBox(height: CaeloSpace.xs),
                      Text(
                        server?.name ?? '—',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: CaeloTheme.title(palette),
                      ),
                      Text(
                        limitedScope
                            ? l10n.localTunnelOnly
                            : server?.location ?? l10n.serverListMockNotice,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: CaeloTheme.caption(palette),
                      ),
                    ],
                  ),
                ),
                if (server != null)
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      _ServerBadge(label: server.badge),
                      const SizedBox(height: CaeloSpace.xs),
                      if (server.latencyMs case final latency?)
                        Text(
                          l10n.latency(latency),
                          style: CaeloTheme.caption(palette).copyWith(
                            color: latency < 60
                                ? palette.accent
                                : palette.muted,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                    ],
                  ),
                const SizedBox(width: CaeloSpace.sm),
                Icon(
                  locked ? CupertinoIcons.lock : CupertinoIcons.chevron_up,
                  size: 18,
                  color: palette.dim,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ServerBadge extends StatelessWidget {
  const _ServerBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = CaeloColors.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.accentSurface,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: palette.accentBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Text(
          label,
          style: CaeloTheme.caption(
            palette,
          ).copyWith(color: palette.accent, fontWeight: FontWeight.w600),
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
      onPressed: () async {
        final servers = ServerSelectionScope.of(context);
        final tunnel = TunnelScope.of(context);
        await Navigator.of(context).push(
          CupertinoPageRoute<void>(builder: (_) => const SettingsScreen()),
        );
        await servers.load();
        await tunnel.refreshConfiguration();
      },
      foreground: palette.muted,
    );
  }
}
