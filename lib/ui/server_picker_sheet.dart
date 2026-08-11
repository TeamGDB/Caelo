import 'package:flutter/cupertino.dart';

import '../core/server_catalog.dart';
import '../l10n/generated/app_localizations.dart';
import '../theme/app_theme.dart';
import '../theme/palette.dart';

/// A persistent part of Home, not a route. Dragging its own scrollable surface
/// changes the extent continuously and snaps between peek and expanded states.
class ServerDrawer extends StatefulWidget {
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
  State<ServerDrawer> createState() => _ServerDrawerState();
}

class _ServerDrawerState extends State<ServerDrawer> {
  final ScrollController _listController = ScrollController();
  double? _extent;
  bool _dragging = false;

  @override
  void didUpdateWidget(ServerDrawer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.locked && !oldWidget.locked) {
      _extent = null;
      if (_listController.hasClients) _listController.jumpTo(0);
    }
  }

  @override
  void dispose() {
    _listController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = CaeloColors.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final peek = (152 / constraints.maxHeight).clamp(0.18, 0.30);
        const expanded = 0.75;
        final extent = widget.locked ? peek : (_extent ?? peek);
        void updateExtent(double delta) {
          if (widget.locked) return;
          setState(() {
            _dragging = true;
            _extent = (extent - delta / constraints.maxHeight).clamp(
              peek,
              expanded,
            );
          });
        }

        void settleExtent(double velocity) {
          if (widget.locked) return;
          final current = _extent ?? peek;
          final expand =
              velocity < -250 ||
              (velocity <= 250 && current > (peek + expanded) / 2);
          setState(() {
            _dragging = false;
            _extent = expand ? expanded : peek;
          });
          if (!expand && _listController.hasClients) {
            _listController.jumpTo(0);
          }
        }

        void expandFromTap() {
          if (widget.locked || (_extent ?? peek) >= expanded) return;
          setState(() {
            _dragging = false;
            _extent = expanded;
          });
        }

        return Align(
          alignment: Alignment.bottomCenter,
          child: AnimatedContainer(
            duration: _dragging ? Duration.zero : CaeloMotion.standard,
            curve: Curves.easeOutCubic,
            height: constraints.maxHeight * extent,
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
                child: Column(
                  children: [
                    _PeekHeader(
                      selected: widget.controller.selected,
                      locked: widget.locked,
                      limitedScope: widget.limitedScope,
                      onDragUpdate: updateExtent,
                      onDragEnd: settleExtent,
                      onTap: expandFromTap,
                    ),
                    Expanded(
                      child: CustomScrollView(
                        key: const ValueKey('server-list-scroll'),
                        controller: _listController,
                        physics: widget.locked
                            ? const NeverScrollableScrollPhysics()
                            : const ClampingScrollPhysics(),
                        slivers: [
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
                          SliverPadding(
                            padding: EdgeInsets.fromLTRB(
                              CaeloSpace.sm,
                              CaeloSpace.xs,
                              CaeloSpace.sm,
                              CaeloSpace.xl +
                                  MediaQuery.paddingOf(context).bottom,
                            ),
                            sliver: SliverList.separated(
                              itemCount: widget.controller.servers.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(height: 2),
                              itemBuilder: (context, index) {
                                final server = widget.controller.servers[index];
                                return _ServerRow(
                                  server: server,
                                  selected:
                                      server == widget.controller.selected,
                                  onPressed: widget.locked
                                      ? null
                                      : () => widget.controller.select(server),
                                );
                              },
                            ),
                          ),
                        ],
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
    required this.onDragUpdate,
    required this.onDragEnd,
    required this.onTap,
  });

  final ServerOption? selected;
  final bool locked;
  final bool limitedScope;
  final ValueChanged<double> onDragUpdate;
  final ValueChanged<double> onDragEnd;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = CaeloColors.of(context);
    final l10n = AppLocalizations.of(context);
    final server = selected;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      onVerticalDragUpdate: (details) => onDragUpdate(details.delta.dy),
      onVerticalDragEnd: (details) =>
          onDragEnd(details.velocity.pixelsPerSecond.dy),
      child: SizedBox(
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
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: CaeloSpace.control,
                    ),
                    child: Text(
                      l10n.selectedServer,
                      style: CaeloTheme.title(
                        palette,
                      ).copyWith(color: palette.muted, fontSize: 22),
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(
                        CaeloSpace.gutter,
                        0,
                        CaeloSpace.gutter,
                        CaeloSpace.control,
                      ),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 64,
                            child: Text(
                              server?.flag ?? '—',
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontSize: 38),
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
                                  style: CaeloTheme.title(
                                    palette,
                                  ).copyWith(fontSize: 24),
                                ),
                                Text(
                                  limitedScope
                                      ? l10n.localTunnelOnly
                                      : server?.location ??
                                            l10n.serverListMockNotice,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: CaeloTheme.body(palette).copyWith(
                                    color: palette.muted,
                                    fontSize: 17,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (server?.latencyMs case final latency?)
                            Text(
                              l10n.latency(latency),
                              style: CaeloTheme.body(
                                palette,
                              ).copyWith(color: palette.primary, fontSize: 18),
                            ),
                          const SizedBox(width: CaeloSpace.sm),
                          Icon(
                            locked
                                ? CupertinoIcons.lock
                                : CupertinoIcons.chevron_up,
                            size: 22,
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
          horizontal: CaeloSpace.md,
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
              width: 64,
              child: Text(
                server.flag,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 36),
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
                    ).copyWith(fontSize: 20, fontWeight: FontWeight.w600),
                  ),
                  Text(
                    server.location,
                    style: CaeloTheme.body(
                      palette,
                    ).copyWith(color: palette.muted, fontSize: 17),
                  ),
                ],
              ),
            ),
            if (server.latencyMs case final latency?)
              Text(
                AppLocalizations.of(context).latency(latency),
                style: CaeloTheme.body(
                  palette,
                ).copyWith(color: palette.muted, fontSize: 18),
              ),
            if (selected) ...[
              const SizedBox(width: CaeloSpace.control),
              Icon(
                CupertinoIcons.check_mark_circled_solid,
                color: palette.accent,
                size: 28,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
