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
                        // Only when there is something to say beyond "it did
                        // not work". Pressing the button again is the obvious
                        // move and the right one for most failures; these are
                        // the ones where it would waste somebody's afternoon.
                        //
                        // This does lift the button, which the rest of the
                        // screen goes out of its way to avoid. Accepted here
                        // rather than reserving the space: an empty slot under
                        // the button for everyone, forever, to spare a shift in
                        // a state almost nobody reaches is the worse trade, and
                        // the movement is doing the same work as the colour.
                        if (_explain(status.failure, l10n) case final note?)
                          Padding(
                            padding: const EdgeInsets.only(
                              top: CaeloSpace.gutter,
                            ),
                            child: Text(
                              note,
                              textAlign: TextAlign.center,
                              style: CaeloTheme.caption(
                                palette,
                              ).copyWith(color: palette.danger),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: ServerDrawer(
                controller: servers,
                locked: status.phase != TunnelPhase.disconnected,
                selectedLatencyMs: status.phase == TunnelPhase.connected
                    ? status.pingMs
                    : null,
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

/// The sentence for a failure worth naming, or null for the ones that are not.
///
/// Lives here rather than on [TunnelFailure] because the clients that raise
/// these run below the interface and have no locale; an English sentence built
/// down there would surface untranslated in a Russian window.
String? _explain(TunnelFailure? failure, AppLocalizations l10n) =>
    switch (failure) {
      TunnelFailure.serviceOlderThanApp => l10n.serviceOlderThanApp,
      TunnelFailure.appOlderThanService => l10n.appOlderThanService,
      null => null,
    };

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
