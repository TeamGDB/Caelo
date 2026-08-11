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
        final peek = (112 / constraints.maxHeight).clamp(0.14, 0.26);
        const expanded = 0.75;
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
                          CaeloSpace.gutter,
                          CaeloSpace.gutter,
                          CaeloSpace.xs,
                        ),
                        child: Text(
                          AppLocalizations.of(context).chooseServer,
                          style: CaeloTheme.headline(
                            palette,
                          ).copyWith(fontSize: 26),
                        ),
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: CaeloSpace.lg,
                        ),
                        child: Text(
                          AppLocalizations.of(context).serverListMockNotice,
                          style: CaeloTheme.body(
                            palette,
                          ).copyWith(color: palette.muted, height: 1.45),
                        ),
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(
                        CaeloSpace.lg,
                        52,
                        CaeloSpace.lg,
                        CaeloSpace.xl,
                      ),
                      sliver: SliverList.separated(
                        itemCount: controller.servers.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 2),
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
      height: 112,
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
            child: Column(
              children: [
                const SizedBox(height: CaeloSpace.xs),
                Text(
                  l10n.selectedServer,
                  style: CaeloTheme.body(
                    palette,
                  ).copyWith(color: palette.muted, fontWeight: FontWeight.w600),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      CaeloSpace.lg,
                      0,
                      CaeloSpace.lg,
                      CaeloSpace.sm,
                    ),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 58,
                          child: Text(
                            server?.flag ?? '—',
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 32),
                          ),
                        ),
                        const SizedBox(width: CaeloSpace.md),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                server?.name ?? '—',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: CaeloTheme.title(palette),
                              ),
                              Text(
                                limitedScope
                                    ? l10n.localTunnelOnly
                                    : server?.location ??
                                          l10n.serverListMockNotice,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: CaeloTheme.body(
                                  palette,
                                ).copyWith(color: palette.muted),
                              ),
                            ],
                          ),
                        ),
                        if (server?.latencyMs case final latency?)
                          Text(
                            l10n.latency(latency),
                            style: CaeloTheme.body(
                              palette,
                            ).copyWith(color: palette.primary),
                          ),
                        const SizedBox(width: CaeloSpace.sm),
                        Icon(
                          locked
                              ? CupertinoIcons.lock
                              : CupertinoIcons.chevron_up,
                          size: 20,
                          color: palette.muted,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
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
        key: ValueKey('server-row-${server.id}'),
        padding: const EdgeInsets.symmetric(
          horizontal: CaeloSpace.control,
          vertical: 18,
        ),
        decoration: BoxDecoration(
          color: selected ? palette.accentSurface : const Color(0x00000000),
          borderRadius: BorderRadius.circular(18),
          border: selected
              ? Border.all(color: palette.accent, width: CaeloStroke.emphasis)
              : null,
        ),
        child: Row(
          children: [
            SizedBox(
              width: 58,
              child: Text(
                server.flag,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 28),
              ),
            ),
            const SizedBox(width: CaeloSpace.md),
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
                    ).copyWith(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                  Text(
                    server.location,
                    style: CaeloTheme.body(
                      palette,
                    ).copyWith(color: palette.muted),
                  ),
                ],
              ),
            ),
            if (server.latencyMs case final latency?)
              Text(
                AppLocalizations.of(context).latency(latency),
                style: CaeloTheme.body(palette).copyWith(color: palette.muted),
              ),
            if (selected) ...[
              const SizedBox(width: CaeloSpace.control),
              Icon(
                CupertinoIcons.check_mark_circled_solid,
                color: palette.accent,
                size: 24,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
