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
    this.selectedLatencyMs,
    this.showActive = false,
    this.onPicked,
    super.key,
  });

  /// Told after the person picks a server.
  final VoidCallback? onPicked;

  final ServerSelectionController controller;
  final bool locked;

  /// Whether the header names the server actually in use rather than the
  /// choice. They differ when the choice is "automatic".
  final bool showActive;
  final bool limitedScope;
  final int? selectedLatencyMs;

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
      _reportOpen(false);
    }
    if (!identical(widget.controller, oldWidget.controller)) {
      oldWidget.controller.listOpen = false;
    }
  }

  @override
  void dispose() {
    _reportOpen(false);
    _listController.dispose();
    super.dispose();
  }

  /// Tells the list whether it is open in front of somebody: that is when
  /// its servers are measured (#156).
  void _reportOpen(bool open) => widget.controller.listOpen = open;

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
          _reportOpen(expand);
          if (!expand && _listController.hasClients) {
            _listController.jumpTo(0);
          }
        }

        void collapse() {
          if (widget.locked) return;
          setState(() {
            _dragging = false;
            _extent = peek;
          });
          _reportOpen(false);
          if (_listController.hasClients) _listController.jumpTo(0);
        }

        void toggleFromTap() {
          if (widget.locked) return;
          if ((_extent ?? peek) >= expanded) {
            collapse();
          } else {
            setState(() {
              _dragging = false;
              _extent = expanded;
            });
            _reportOpen(true);
          }
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
                child: LayoutBuilder(
                  builder: (context, sheetConstraints) {
                    // Latency for every server or for none (#109). A column
                    // with gaps reads as servers that are broken, when they
                    // are only not measured yet.
                    // Counted over servers that can be dialled: one the
                    // subscription offers and would not issue keys for has
                    // nothing to measure, and must not hide everyone else's.
                    final measurable = widget.controller.servers.where(
                      (server) => server.connectable,
                    );
                    final showLatency =
                        measurable.isNotEmpty &&
                        measurable.every((server) => server.measured);
                    final showsServerList =
                        sheetConstraints.maxHeight >= 152 + CaeloSpace.xl * 2;
                    return Column(
                      children: [
                        _PeekHeader(
                          selected: widget.controller.selected,
                          active: widget.showActive
                              ? widget.controller.active
                              : null,
                          locked: widget.locked,
                          limitedScope: widget.limitedScope,
                          latencyMs: widget.showActive
                              ? widget.selectedLatencyMs
                              : showLatency
                              ? widget.controller.selected?.latencyMs
                              : null,
                          onDragUpdate: updateExtent,
                          onDragEnd: settleExtent,
                          onTap: toggleFromTap,
                          expanded: extent >= expanded,
                        ),
                        if (showsServerList) ...[
                          Padding(
                            padding: const EdgeInsets.fromLTRB(
                              CaeloSpace.gutter,
                              CaeloSpace.gutter,
                              CaeloSpace.gutter,
                              CaeloSpace.xs,
                            ),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                AppLocalizations.of(context).chooseServer,
                                style: CaeloTheme.headline(
                                  palette,
                                ).copyWith(fontSize: 26),
                              ),
                            ),
                          ),
                          Expanded(
                            child: CupertinoScrollbar(
                              controller: _listController,
                              thumbVisibility: true,
                              mainAxisMargin: 0,
                              child: CustomScrollView(
                                key: const ValueKey('server-list-scroll'),
                                controller: _listController,
                                physics: widget.locked
                                    ? const NeverScrollableScrollPhysics()
                                    : const ClampingScrollPhysics(),
                                slivers: [
                                  SliverPadding(
                                    padding: EdgeInsets.fromLTRB(
                                      CaeloSpace.sm,
                                      CaeloSpace.xs,
                                      CaeloSpace.sm,
                                      CaeloSpace.sm +
                                          MediaQuery.paddingOf(context).bottom,
                                    ),
                                    sliver: SliverList.separated(
                                      itemCount:
                                          widget.controller.servers.length,
                                      separatorBuilder: (_, _) =>
                                          const SizedBox(height: 2),
                                      itemBuilder: (context, index) {
                                        final server =
                                            widget.controller.servers[index];
                                        final preparing =
                                            server ==
                                                widget.controller.preparing ||
                                            // Waiting for keys from the
                                            // background pass (#131).
                                            (widget.controller.provisioning &&
                                                server.needsKeys &&
                                                server.available);
                                        return _ServerRow(
                                          server: server,
                                          // Готовящийся показывается выбранным
                                          // сразу: выдача ключей идёт секундами,
                                          // и список, который всё это время
                                          // показывает прежний выбор, читается
                                          // как «не нажалось».
                                          selected:
                                              server ==
                                                  widget.controller.preparing ||
                                              server ==
                                                  widget.controller.selected,
                                          preparing: preparing,
                                          showLatency:
                                              showLatency && server.connectable,
                                          onPressed:
                                              widget.locked ||
                                                  !server.available ||
                                                  // Пока один сервер готовится,
                                                  // остальные не нажимаются:
                                                  // иначе второе нажатие
                                                  // подключит то, что нажали
                                                  // позже, а первый выданный
                                                  // конфиг останется висеть.
                                                  (widget
                                                          .controller
                                                          .isPreparing &&
                                                      !preparing)
                                              ? null
                                              : () async {
                                                  if (!server.needsKeys) {
                                                    collapse();
                                                  }
                                                  await widget.controller
                                                      .select(server);
                                                  widget.onPicked?.call();
                                                },
                                        );
                                      },
                                    ),
                                  ),
                                  // What the list cannot say by itself: an
                                  // empty subscription, and servers this
                                  // build cannot run (#172).
                                  for (final note in widget.controller.notes)
                                    SliverToBoxAdapter(
                                      child: Padding(
                                        padding: const EdgeInsets.fromLTRB(
                                          CaeloSpace.gutter,
                                          0,
                                          CaeloSpace.gutter,
                                          CaeloSpace.sm,
                                        ),
                                        child: Text(
                                          _noteText(
                                            note,
                                            AppLocalizations.of(context),
                                          ),
                                          style: CaeloTheme.caption(palette),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ],
                    );
                  },
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
    required this.active,
    required this.locked,
    required this.limitedScope,
    required this.onDragUpdate,
    required this.onDragEnd,
    required this.onTap,
    required this.expanded,
    required this.latencyMs,
  });

  final ServerOption? selected;

  /// The server in use, when there is a connection and it is worth naming.
  final ServerOption? active;
  final bool locked;
  final bool limitedScope;
  final ValueChanged<double> onDragUpdate;
  final ValueChanged<double> onDragEnd;
  final VoidCallback onTap;
  final bool expanded;
  final int? latencyMs;

  @override
  Widget build(BuildContext context) {
    final palette = CaeloColors.of(context);
    final l10n = AppLocalizations.of(context);
    final choice = selected;
    // The automatic entry names itself until it has picked something, then
    // the header names what it picked and says it was picked for you.
    final pickedForYou = choice != null && choice.automatic && active != null;
    final server = pickedForYou ? active : choice;
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
                              style: CaeloTheme.flag(fontSize: 38),
                            ),
                          ),
                          const SizedBox(width: CaeloSpace.md),
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _name(server, l10n),
                                  key: const ValueKey('selected-server-name'),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: CaeloTheme.title(
                                    palette,
                                  ).copyWith(fontSize: 24),
                                ),
                                // Two lines fit the header; a description
                                // longer than that is not a description.
                                Text(
                                  limitedScope
                                      ? l10n.localTunnelOnly
                                      : pickedForYou
                                      ? l10n.automaticallyChosen
                                      : _description(server, l10n),
                                  key: const ValueKey(
                                    'selected-server-description',
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: CaeloTheme.body(palette).copyWith(
                                    color: palette.muted,
                                    fontSize: 15,
                                    height: 1.2,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (latencyMs case final latency?)
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
                                : expanded
                                ? CupertinoIcons.chevron_down
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
    this.showLatency = false,
    this.preparing = false,
  });

  final ServerOption server;
  final bool selected;

  /// Keys for this server are being asked for right now.
  final bool preparing;
  final VoidCallback? onPressed;

  /// Whether this row shows its measurement: a latency, or a dash for a
  /// server that did not answer.
  final bool showLatency;

  @override
  Widget build(BuildContext context) {
    final palette = CaeloColors.of(context);
    // A server that cannot be used is shown, dimmed, rather than hidden: the
    // list should match the panel, and say why one of them will not do (#126).
    return Opacity(
      opacity: server.available ? 1 : 0.45,
      child: CupertinoButton(
        padding: EdgeInsets.zero,
        onPressed: onPressed,
        child: Container(
          key: ValueKey('server-row-${server.id}'),
          width: double.infinity,
          padding: const EdgeInsets.symmetric(
            horizontal: CaeloSpace.md,
            vertical: 18,
          ),
          decoration: BoxDecoration(
            color: selected ? palette.accentSurface : const Color(0x00000000),
            borderRadius: BorderRadius.circular(18),
          ),
          foregroundDecoration: selected
              ? BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: palette.accent,
                    width: CaeloStroke.emphasis,
                  ),
                )
              : null,
          child: Row(
            children: [
              SizedBox(
                width: 64,
                child: Text(
                  server.flag,
                  textAlign: TextAlign.center,
                  // Opaque on purpose: a disabled button tints emoji through the
                  // default text colour, and every flag paled while another
                  // row was being prepared (#130).
                  style: CaeloTheme.flag(
                    fontSize: 36,
                    color: palette.foreground,
                  ),
                ),
              ),
              const SizedBox(width: CaeloSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _name(server, AppLocalizations.of(context)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: CaeloTheme.body(
                        palette,
                      ).copyWith(fontSize: 20, fontWeight: FontWeight.w600),
                    ),
                    // Wraps rather than ends in an ellipsis: the description
                    // is how somebody tells two servers in one country apart.
                    Text(
                      preparing
                          ? AppLocalizations.of(context).serverPreparing
                          : _description(server, AppLocalizations.of(context)),
                      key: ValueKey('server-description-${server.id}'),
                      style: CaeloTheme.body(
                        palette,
                      ).copyWith(color: palette.muted, fontSize: 17),
                    ),
                  ],
                ),
              ),
              if (showLatency)
                Padding(
                  padding: const EdgeInsets.only(left: CaeloSpace.sm),
                  child: Text(
                    switch (server.latencyMs) {
                      final latency? => AppLocalizations.of(
                        context,
                      ).latency(latency),
                      null => '—',
                    },
                    key: ValueKey('server-latency-${server.id}'),
                    style: CaeloTheme.body(
                      palette,
                    ).copyWith(color: palette.muted, fontSize: 17),
                  ),
                ),
              const SizedBox(width: CaeloSpace.sm),
              SizedBox(
                width: 28,
                child: preparing
                    ? const CupertinoActivityIndicator(radius: 9)
                    : selected
                    ? Icon(
                        CupertinoIcons.check_mark_circled_solid,
                        color: palette.accent,
                        size: 28,
                      )
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _name(ServerOption? server, AppLocalizations l10n) {
  if (server == null) return '—';
  if (server.automatic) return l10n.automaticServer;
  return server.name;
}

String _description(ServerOption? server, AppLocalizations l10n) {
  switch (server?.reason) {
    case UnavailableReason.maintenance:
      return l10n.serverMaintenance;
    case UnavailableReason.notIssued:
      return l10n.serverNotIssued;
    case null:
      break;
  }
  if (server != null && server.automatic) {
    return l10n.automaticServerDescription;
  }
  final value = server?.description.trim() ?? '';
  if (value.isNotEmpty) return value;
  return server?.configId == null ? '' : l10n.customServerDescription;
}

String _noteText(SubscriptionNote note, AppLocalizations l10n) => note.empty
    ? l10n.subscriptionEmpty
    : l10n.subscriptionSkipped(note.skipped.length, note.reasons);
