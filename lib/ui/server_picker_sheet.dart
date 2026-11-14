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
        final headerHeight = _PeekHeader.heightFor(context);
        final listTitleHeight =
            MediaQuery.textScalerOf(context).scale(26) * 1.2;
        final listHeading = listTitleHeight + CaeloSpace.gutter + CaeloSpace.xs;
        final peek = (headerHeight / constraints.maxHeight).clamp(0.18, 1.0);
        final expanded =
            ((headerHeight + listHeading + 96) / constraints.maxHeight).clamp(
              0.75,
              1.0,
            );
        final extent = widget.locked
            ? peek
            : _dragging
            ? (_extent ?? peek).clamp(peek, expanded)
            : _extent == null
            ? peek
            : expanded;
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
            _extent = expand ? expanded : null;
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
            _extent = null;
          });
          _reportOpen(false);
          if (_listController.hasClients) _listController.jumpTo(0);
        }

        void toggleFromTap() {
          if (widget.locked) return;
          if (extent >= expanded) {
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
                        sheetConstraints.maxHeight > headerHeight + listHeading;
                    return Column(
                      children: [
                        _PeekHeader(
                          height: headerHeight,
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
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
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
    required this.height,
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

  final double height;

  // При крупном шрифте растёт и шапка: фиксированные 152 px обрезали
  // название и две строки описания ещё до раскрытия списка.
  static double heightFor(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    double growth(double size) =>
        (scaler.scale(size) - size).clamp(0, double.infinity);
    return 152 +
        growth(22) * (28 / 21) +
        growth(24) * (28 / 21) +
        growth(15) * 2.4;
  }

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
        height: height,
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
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
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
                          _DetailsWithMeasure(
                            details: Column(
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
                            measure:
                                latencyMs != null ||
                                    (server?.protocol.isNotEmpty ?? false)
                                ? _Measure(
                                    latency: switch (latencyMs) {
                                      final latency? => Text(
                                        l10n.latency(latency),
                                        style: CaeloTheme.body(palette)
                                            .copyWith(
                                              color: palette.primary,
                                              fontSize: 18,
                                            ),
                                      ),
                                      null => null,
                                    },
                                    protocol: server?.protocol ?? '',
                                    badgeKey: const ValueKey(
                                      'selected-server-protocol',
                                    ),
                                  )
                                : null,
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
              _DetailsWithMeasure(
                details: Column(
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
                measure: showLatency || server.protocol.isNotEmpty
                    ? _Measure(
                        latency: showLatency
                            ? Text(
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
                              )
                            : null,
                        protocol: server.protocol,
                        badgeKey: ValueKey('server-protocol-${server.id}'),
                        onAccent: selected,
                      )
                    : null,
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

// Правая колонка занимает свою естественную ширину, но не больше половины
// места после флага и галочки. Остальное достаётся имени и описанию;
// короткий AWG не сдвигает правый край относительно длинного VLESS.
class _DetailsWithMeasure extends StatelessWidget {
  const _DetailsWithMeasure({required this.details, required this.measure});
  final Widget details;
  final Widget? measure;

  @override
  Widget build(BuildContext context) => Expanded(
    child: LayoutBuilder(
      builder: (context, constraints) => Row(
        children: [
          Expanded(child: details),
          if (measure case final content?)
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: constraints.maxWidth / 2),
              child: Padding(
                padding: const EdgeInsets.only(left: CaeloSpace.sm),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerEnd,
                  child: content,
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

/// The latency, and under it what carries the server (#174): `AWG`,
/// `VLESS · Vision`. Kept as two elements in one column at the row's end, so
/// that the name keeps the whole width it had and a badge never reads as part
/// of it.
class _Measure extends StatelessWidget {
  const _Measure({
    required this.latency,
    required this.protocol,
    required this.badgeKey,
    this.onAccent = false,
  });

  final Widget? latency;
  final String protocol;
  final Key badgeKey;

  /// Drawn on the selected row's wash, where a fill of its own would look
  /// like a second selection.
  final bool onAccent;

  @override
  Widget build(BuildContext context) {
    final palette = CaeloColors.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        ?latency,
        if (latency != null && protocol.isNotEmpty) const SizedBox(height: 6),
        if (protocol.isNotEmpty)
          // A badge, not a sentence: it grows with the text, but not so far
          // that the row has to shrink everything else around it.
          MediaQuery.withClampedTextScaling(
            maxScaleFactor: 1.3,
            child: Container(
              key: badgeKey,
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
              decoration: BoxDecoration(
                color: onAccent ? null : palette.surface2,
                border: Border.all(
                  color: palette.border,
                  width: CaeloStroke.hairline,
                ),
                borderRadius: CaeloRadius.compactAll,
              ),
              child: Text(
                protocol,
                maxLines: 1,
                // "VLESS Vision": a screen reader has nothing to say about the
                // dot between them.
                semanticsLabel: protocol.replaceAll(' · ', ' '),
                style: CaeloTheme.caption(palette).copyWith(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w600,
                  height: 1.25,
                  letterSpacing: 0.1,
                ),
              ),
            ),
          ),
      ],
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

String _noteText(SubscriptionNote note, AppLocalizations l10n) {
  final text = note.empty
      ? l10n.subscriptionEmpty
      : l10n.subscriptionSkipped(note.skipped.length, note.reasons);
  // Named when there is a name: with two subscriptions, a note that does not
  // say which one is a riddle.
  return note.title.isEmpty ? text : '${note.title}: $text';
}
