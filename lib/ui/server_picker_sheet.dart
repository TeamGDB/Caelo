import 'package:flutter/cupertino.dart';

import '../core/server_catalog.dart';
import '../l10n/generated/app_localizations.dart';
import '../theme/app_theme.dart';
import '../theme/palette.dart';

/// A persistent part of Home, not a route. Dragging its own scrollable surface
/// changes the extent continuously and snaps between peek and expanded states.
class ServerDrawer extends StatelessWidget {
  const ServerDrawer({
    required this.controller,
    required this.locked,
    required this.limitedScope,
    super.key,
  });

  final ServerSelectionController controller;
  final bool locked;
  final bool limitedScope;

  @override
  Widget build(BuildContext context) {
    final palette = CaeloColors.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final peek = (152 / constraints.maxHeight).clamp(0.18, 0.34);
        const expanded = 0.76;
        return DraggableScrollableSheet(
          key: ValueKey(locked),
          initialChildSize: peek,
          minChildSize: peek,
          maxChildSize: locked ? peek : expanded,
          snap: !locked,
          snapSizes: locked ? null : [peek, expanded],
          builder: (context, scrollController) => Align(
            alignment: Alignment.bottomCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: CaeloSize.contentMaxWidth,
              ),
              child: DecoratedBox(
                key: const ValueKey('server-sheet-surface'),
                decoration: BoxDecoration(
                  color: palette.surface1,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(30),
                  ),
                  border: Border(top: BorderSide(color: palette.border)),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF000000).withValues(alpha: 0.16),
                      blurRadius: 24,
                      offset: const Offset(0, -6),
                    ),
                  ],
                ),
                child: CustomScrollView(
                  controller: scrollController,
                  physics: locked
                      ? const NeverScrollableScrollPhysics()
                      : const ClampingScrollPhysics(),
                  slivers: [
                    SliverToBoxAdapter(
                      child: _PeekHeader(
                        selected: controller.selected,
                        locked: locked,
                        limitedScope: limitedScope,
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(
                          CaeloSpace.gutter,
                          CaeloSpace.lg,
                          CaeloSpace.gutter,
                          CaeloSpace.xs,
                        ),
                        child: Text(
                          AppLocalizations.of(context).chooseServer,
                          style: CaeloTheme.title(palette),
                        ),
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: CaeloSpace.gutter,
                        ),
                        child: Text(
                          AppLocalizations.of(context).serverListMockNotice,
                          style: CaeloTheme.caption(palette),
                        ),
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(
                        CaeloSpace.gutter,
                        CaeloSpace.md,
                        CaeloSpace.gutter,
                        CaeloSpace.xl,
                      ),
                      sliver: SliverList.separated(
                        itemCount: controller.servers.length,
                        separatorBuilder: (_, _) =>
                            const SizedBox(height: CaeloSpace.sm),
                        itemBuilder: (context, index) {
                          final server = controller.servers[index];
                          return _ServerRow(
                            server: server,
                            selected: server == controller.selected,
                            onPressed: locked
                                ? null
                                : () => controller.select(server),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _PeekHeader extends StatelessWidget {
  const _PeekHeader({
    required this.selected,
    required this.locked,
    required this.limitedScope,
  });

  final ServerOption? selected;
  final bool locked;
  final bool limitedScope;

  @override
  Widget build(BuildContext context) {
    final palette = CaeloColors.of(context);
    final l10n = AppLocalizations.of(context);
    final server = selected;
    return SizedBox(
      height: 152,
      child: Column(
        children: [
          const SizedBox(height: CaeloSpace.control),
          Container(
            key: const ValueKey('server-drag-handle'),
            width: 34,
            height: 4,
            decoration: BoxDecoration(
              color: palette.dim,
              borderRadius: CaeloRadius.compactAll,
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                CaeloSpace.gutter,
                CaeloSpace.sm,
                CaeloSpace.gutter,
                CaeloSpace.control,
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
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
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
                    Text(
                      server.badge,
                      style: CaeloTheme.caption(palette).copyWith(
                        color: palette.accent,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  const SizedBox(width: CaeloSpace.sm),
                  Icon(
                    locked ? CupertinoIcons.lock : CupertinoIcons.chevron_up,
                    size: 20,
                    color: palette.dim,
                  ),
                ],
              ),
            ),
          ),
        ],
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
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final palette = CaeloColors.of(context);
    return CupertinoButton(
      padding: EdgeInsets.zero,
      onPressed: onPressed,
      child: Container(
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
