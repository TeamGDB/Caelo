import 'package:flutter/cupertino.dart';

import '../core/server_catalog.dart';
import '../l10n/generated/app_localizations.dart';
import '../theme/app_theme.dart';
import '../theme/palette.dart';
import 'widgets/caelo_surface.dart';

Future<void> showCaeloServerPicker(
  BuildContext context,
  ServerSelectionController controller,
) => showCupertinoModalPopup<void>(
  context: context,
  barrierDismissible: true,
  builder: (_) => ServerPickerSheet(controller: controller),
);

class ServerPickerSheet extends StatelessWidget {
  const ServerPickerSheet({required this.controller, super.key});

  final ServerSelectionController controller;

  @override
  Widget build(BuildContext context) {
    final palette = CaeloColors.of(context);
    final l10n = AppLocalizations.of(context);
    return Align(
      alignment: Alignment.bottomCenter,
      child: FractionallySizedBox(
        heightFactor: 0.72,
        child: CaeloContentWidth(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: palette.surface1,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(30),
              ),
              border: Border(top: BorderSide(color: palette.border)),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF000000).withValues(alpha: 0.18),
                  blurRadius: 28,
                  offset: const Offset(0, -8),
                ),
              ],
            ),
            child: SafeArea(
              top: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: CaeloSpace.control),
                  Center(
                    child: Container(
                      width: 34,
                      height: 4,
                      decoration: BoxDecoration(
                        color: palette.dim,
                        borderRadius: CaeloRadius.compactAll,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      CaeloSpace.gutter,
                      CaeloSpace.lg,
                      CaeloSpace.gutter,
                      CaeloSpace.xs,
                    ),
                    child: Text(
                      l10n.chooseServer,
                      style: CaeloTheme.title(palette),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: CaeloSpace.gutter,
                    ),
                    child: Text(
                      l10n.serverListMockNotice,
                      style: CaeloTheme.caption(palette),
                    ),
                  ),
                  const SizedBox(height: CaeloSpace.md),
                  Expanded(
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(
                        CaeloSpace.gutter,
                        0,
                        CaeloSpace.gutter,
                        CaeloSpace.lg,
                      ),
                      itemCount: controller.servers.length,
                      separatorBuilder: (_, _) =>
                          const SizedBox(height: CaeloSpace.sm),
                      itemBuilder: (context, index) {
                        final server = controller.servers[index];
                        return _ServerRow(
                          server: server,
                          selected: server == controller.selected,
                          onPressed: () async {
                            await controller.select(server);
                            if (context.mounted) Navigator.pop(context);
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ServerRow extends StatelessWidget {
  const _ServerRow({
    required this.server,
    required this.selected,
    required this.onPressed,
  });

  final ServerOption server;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final palette = CaeloColors.of(context);
    return CupertinoButton(
      padding: EdgeInsets.zero,
      onPressed: onPressed,
      child: AnimatedContainer(
        duration: CaeloMotion.quick,
        padding: const EdgeInsets.all(CaeloSpace.control),
        decoration: BoxDecoration(
          color: selected ? palette.accentSurface : palette.surface2,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected ? palette.accent : palette.border,
            width: selected ? CaeloStroke.emphasis : CaeloStroke.hairline,
          ),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 48,
              child: Text(
                server.flag,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 28),
              ),
            ),
            const SizedBox(width: CaeloSpace.control),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    server.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: CaeloTheme.body(
                      palette,
                    ).copyWith(fontWeight: FontWeight.w600),
                  ),
                  Text(server.location, style: CaeloTheme.caption(palette)),
                ],
              ),
            ),
            Text(
              server.badge,
              style: CaeloTheme.caption(
                palette,
              ).copyWith(color: palette.accent, fontWeight: FontWeight.w600),
            ),
            if (server.latencyMs case final latency?) ...[
              const SizedBox(width: CaeloSpace.sm),
              Text('$latency ms', style: CaeloTheme.caption(palette)),
            ],
            const SizedBox(width: CaeloSpace.sm),
            Icon(
              selected
                  ? CupertinoIcons.check_mark_circled_solid
                  : CupertinoIcons.circle,
              color: selected ? palette.accent : palette.dim,
              size: 24,
            ),
          ],
        ),
      ),
    );
  }
}
