import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../core/diagnostics.dart';
import '../l10n/generated/app_localizations.dart';
import '../theme/app_theme.dart';
import '../theme/palette.dart';
import 'widgets/caelo_surface.dart';

/// The diagnostic log, as it is being written.
///
/// Monospaced and unadorned on purpose: this is meant to be read by whoever is
/// helping, and formatting that looks tidy on screen tends to survive badly
/// once it has been copied into a message.
class LogScreen extends StatefulWidget {
  const LogScreen({super.key});

  @override
  State<LogScreen> createState() => _LogScreenState();
}

class _LogScreenState extends State<LogScreen> {
  final _scroll = ScrollController();

  StreamSubscription<void>? _watch;
  List<String> _lines = const [];
  String? _notice;

  @override
  void initState() {
    super.initState();
    _refresh();
    // On iOS the interesting lines live in another process and have to be
    // fetched rather than read.
    unawaited(Diagnostics.refreshFromExtension());
    // The interesting moment is usually happening right now — someone opens
    // this and then presses connect on another screen.
    _watch = Diagnostics.changes.listen((_) => _refresh());
  }

  @override
  void dispose() {
    _watch?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  void _refresh() {
    if (!mounted) return;
    setState(() => _lines = Diagnostics.merged());

    // Follow the tail, but only from the tail: someone scrolled up is reading
    // something, and yanking them back down is the rudest thing a log view can
    // do.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final position = _scroll.position;
      if (position.pixels > position.maxScrollExtent - 120) {
        _scroll.jumpTo(position.maxScrollExtent);
      }
    });
  }

  Future<void> _flash(String message) async {
    setState(() => _notice = message);
    await Future<void>.delayed(const Duration(seconds: 2));
    if (mounted) setState(() => _notice = null);
  }

  Future<void> _copy(AppLocalizations l10n) async {
    await Clipboard.setData(ClipboardData(text: await Diagnostics.render()));
    await _flash(l10n.logCopied);
  }

  Future<void> _share(AppLocalizations l10n) async {
    try {
      final file = await Diagnostics.export();
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'text/plain')],
          subject: 'Caelo diagnostic log',
        ),
      );
    } on Object catch (error) {
      // Sharing can be declined or unavailable, and neither is worth an
      // exception the user cannot act on. The clipboard is still there.
      await _flash('$error');
    }
  }

  Future<void> _clear(AppLocalizations l10n) async {
    await Diagnostics.clear();
    _refresh();
    await _flash(l10n.logCleared);
  }

  @override
  Widget build(BuildContext context) {
    final palette = CaeloColors.of(context);
    final l10n = AppLocalizations.of(context);

    return CupertinoPageScaffold(
      backgroundColor: palette.background,
      navigationBar: CupertinoNavigationBar(
        backgroundColor: palette.surface1,
        border: Border(bottom: BorderSide(color: palette.border, width: 0)),
        middle: Text(l10n.diagnosticLog),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          minimumSize: Size.zero,
          onPressed: () => _share(l10n),
          child: Icon(
            CupertinoIcons.square_arrow_up,
            size: 20,
            color: palette.accent,
            semanticLabel: l10n.logExport,
          ),
        ),
      ),
      child: CaeloPageSurface(
        child: SafeArea(
          child: CaeloContentWidth(
            child: Column(
              children: [
                Expanded(
                  child: CaeloPanel(
                    margin: const EdgeInsets.all(CaeloSpace.md),
                    radius: CaeloRadius.controlAll,
                    child: _lines.isEmpty
                        ? Center(
                            child: Text(
                              Diagnostics.enabled
                                  ? l10n.logEmpty
                                  : l10n.logDisabled,
                              textAlign: TextAlign.center,
                              style: CaeloTheme.caption(palette),
                            ),
                          )
                        : CupertinoScrollbar(
                            controller: _scroll,
                            child: ListView.builder(
                              controller: _scroll,
                              padding: const EdgeInsets.all(CaeloSpace.sm),
                              itemCount: _lines.length,
                              itemBuilder: (context, index) => Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 1,
                                ),
                                child: Text(
                                  _lines[index],
                                  style: TextStyle(
                                    color: _lines[index].contains('error')
                                        ? palette.danger
                                        : palette.foreground,
                                    fontSize: 11,
                                    fontFamily: 'Menlo',
                                    height: 1.35,
                                  ),
                                ),
                              ),
                            ),
                          ),
                  ),
                ),
                if (_notice != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: CaeloSpace.sm),
                    child: Text(
                      _notice!,
                      style: CaeloTheme.caption(
                        palette,
                      ).copyWith(color: palette.accent),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    CaeloSpace.md,
                    0,
                    CaeloSpace.md,
                    CaeloSpace.md,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      CupertinoButton(
                        minimumSize: const Size(
                          CaeloSize.minimumTarget,
                          CaeloSize.minimumTarget,
                        ),
                        onPressed: () => _copy(l10n),
                        child: Text(
                          l10n.logCopy,
                          style: CaeloTheme.caption(
                            palette,
                          ).copyWith(color: palette.accent, fontSize: 15),
                        ),
                      ),
                      CupertinoButton(
                        minimumSize: const Size(
                          CaeloSize.minimumTarget,
                          CaeloSize.minimumTarget,
                        ),
                        onPressed: () => _clear(l10n),
                        child: Text(
                          l10n.logClear,
                          style: CaeloTheme.caption(
                            palette,
                          ).copyWith(color: palette.danger, fontSize: 15),
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
  }
}
