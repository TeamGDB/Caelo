import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';

import '../core/tunnel.dart';
import '../core/tunnel_controller.dart';
import '../core/server_catalog.dart';
import '../l10n/generated/app_localizations.dart';
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
        child: Stack(
          children: [
            Positioned.fill(
              child: SafeArea(
                child: Align(
                  // Lower than geometric centre: the primary action remains
                  // reachable by a thumb without colliding with the server peek.
                  alignment: const Alignment(0, 0),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: CaeloSpace.gutter,
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
              ),
            ),
            Positioned.fill(
              child: ServerDrawer(
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
            Positioned.fill(
              child: SafeArea(
                child: Stack(
                  children: [
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
          ],
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
