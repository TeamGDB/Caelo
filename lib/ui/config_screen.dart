import 'package:flutter/cupertino.dart';

import '../core/config_store.dart';
import '../l10n/generated/app_localizations.dart';
import '../theme/app_theme.dart';
import '../theme/palette.dart';
import 'widgets/caelo_surface.dart';

/// Where a tunnel configuration is pasted in.
///
/// This is a development affordance, not the product. What ships is a
/// subscription link that fills this in for you; a screen that asks someone to
/// paste a `.conf` is exactly the thing Caelo exists to avoid.
class ConfigScreen extends StatefulWidget {
  const ConfigScreen({this.config, super.key});

  final StoredConfig? config;

  @override
  State<ConfigScreen> createState() => _ConfigScreenState();
}

class _ConfigScreenState extends State<ConfigScreen> {
  final _controller = TextEditingController();
  final _nameController = TextEditingController();
  final _emojiController = TextEditingController();
  bool _loaded = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final existing = widget.config == null
        ? null
        : await ConfigStore.readById(widget.config!.id);
    if (!mounted) return;
    setState(() {
      _controller.text = existing ?? '';
      _nameController.text = widget.config?.name ?? '';
      _emojiController.text = widget.config?.emoji ?? '📄';
      _loaded = true;
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _nameController.dispose();
    _emojiController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final text = _controller.text.trim();
    try {
      if (text.isEmpty) {
        setState(
          () => _error = AppLocalizations.of(context).configurationEmpty,
        );
        return;
      }
      if (!text.contains('[Interface]') || !text.contains('[Peer]')) {
        setState(
          () => _error = AppLocalizations.of(context).configurationFileInvalid,
        );
        return;
      }
      if (widget.config case final config?) {
        await ConfigStore.update(
          config.id,
          _nameController.text,
          text,
          emoji: _emojiController.text,
        );
      } else {
        await ConfigStore.create(
          _nameController.text,
          text,
          emoji: _emojiController.text,
        );
      }
      if (mounted) Navigator.of(context).pop();
    } on Object catch (error) {
      // Failing to store a config silently would leave someone pressing a
      // button that can never work, with nothing on screen explaining why.
      if (mounted) setState(() => _error = error.toString());
    }
  }

  Future<void> _remove() async {
    final config = widget.config;
    if (config == null) return;
    await ConfigStore.delete(config.id);
    if (!mounted) return;
    _controller.clear();
    Navigator.of(context).pop();
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
        middle: Text(l10n.configuration),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          minimumSize: Size.zero,
          onPressed: _loaded ? _save : null,
          child: Text(
            l10n.save,
            style: CaeloTheme.caption(
              palette,
            ).copyWith(color: palette.accent, fontSize: 15),
          ),
        ),
      ),
      child: CaeloPageSurface(
        child: SafeArea(
          child: CaeloContentWidth(
            child: Padding(
              padding: const EdgeInsets.all(CaeloSpace.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: Column(
                      children: [
                        Row(
                          children: [
                            SizedBox(
                              width: 82,
                              child: CupertinoTextField(
                                controller: _emojiController,
                                placeholder: '🏳️',
                                textAlign: TextAlign.center,
                                maxLength: 8,
                                padding: const EdgeInsets.all(CaeloSpace.md),
                                decoration: BoxDecoration(
                                  color: palette.surface1,
                                  borderRadius: CaeloRadius.controlAll,
                                  border: Border.all(color: palette.border),
                                ),
                              ),
                            ),
                            const SizedBox(width: CaeloSpace.sm),
                            Expanded(
                              child: CupertinoTextField(
                                controller: _nameController,
                                placeholder: l10n.configurationName,
                                padding: const EdgeInsets.all(CaeloSpace.md),
                                decoration: BoxDecoration(
                                  color: palette.surface1,
                                  borderRadius: CaeloRadius.controlAll,
                                  border: Border.all(color: palette.border),
                                ),
                              ),
                            ),
                          ],
                        ),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Padding(
                            padding: const EdgeInsets.only(
                              top: CaeloSpace.xs,
                              left: CaeloSpace.xs,
                            ),
                            child: Text(
                              l10n.configurationEmoji,
                              style: CaeloTheme.caption(palette),
                            ),
                          ),
                        ),
                        const SizedBox(height: CaeloSpace.md),
                        Expanded(
                          child: CaeloPanel(
                            radius: CaeloRadius.controlAll,
                            padding: const EdgeInsets.all(CaeloSpace.sm),
                            child: CupertinoTextField.borderless(
                              controller: _controller,
                              maxLines: null,
                              expands: true,
                              textAlignVertical: TextAlignVertical.top,
                              placeholder: l10n.configurationPlaceholder,
                              placeholderStyle: CaeloTheme.caption(
                                palette,
                              ).copyWith(color: palette.dim),
                              style: TextStyle(
                                color: palette.foreground,
                                fontSize: 12,
                                fontFamily: 'Menlo',
                                height: 1.45,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: CaeloSpace.md),
                  Text(
                    _error ?? l10n.configurationWarning,
                    style: CaeloTheme.caption(palette).copyWith(
                      color: _error == null ? palette.dim : palette.danger,
                    ),
                  ),
                  const SizedBox(height: CaeloSpace.sm),
                  if (widget.config != null)
                    CupertinoButton(
                      padding: const EdgeInsets.symmetric(
                        vertical: CaeloSpace.control,
                      ),
                      minimumSize: const Size.fromHeight(
                        CaeloSize.minimumTarget,
                      ),
                      onPressed: _remove,
                      child: Text(
                        l10n.remove,
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
    );
  }
}
