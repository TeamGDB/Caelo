import 'package:file_selector/file_selector.dart';
import 'package:flutter/cupertino.dart';

import '../core/account_gateway.dart';
import '../core/config_store.dart';
import '../l10n/generated/app_localizations.dart';
import '../theme/app_theme.dart';
import '../theme/palette.dart';
import 'widgets/caelo_surface.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({
    required this.gateway,
    required this.onGranted,
    super.key,
  });

  final AccountGateway gateway;
  final Future<void> Function() onGranted;

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  final _invitation = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _invitation.dispose();
    super.dispose();
  }

  Future<void> _submitInvitation() async {
    final l10n = AppLocalizations.of(context);
    if (_invitation.text.trim().isEmpty) {
      setState(() => _error = l10n.invitationEmpty);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.gateway.acceptInvitation(_invitation.text);
      await widget.onGranted();
    } on InvalidInvitation {
      if (mounted) setState(() => _error = l10n.invitationInvalid);
    } on Object {
      if (mounted) setState(() => _error = l10n.invitationUnavailable);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signInWithQr() async {
    final l10n = AppLocalizations.of(context);
    final proceed = await showCupertinoDialog<bool>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: Text(l10n.qrLogin),
        content: Text(l10n.qrMockExplanation),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.continueAction),
          ),
        ],
      ),
    );
    if (proceed != true) return;
    await widget.gateway.signInWithQr();
    await widget.onGranted();
  }

  Future<void> _importConfiguration() async {
    final l10n = AppLocalizations.of(context);
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(label: 'WireGuard configuration', extensions: ['conf']),
      ],
    );
    if (file == null) return;
    final text = await file.readAsString();
    if (!text.contains('[Interface]') || !text.contains('[Peer]')) {
      if (mounted) setState(() => _error = l10n.configurationFileInvalid);
      return;
    }
    await ConfigStore.create(
      file.name.replaceFirst(RegExp(r'\.conf$'), ''),
      text,
    );
    await widget.onGranted();
  }

  @override
  Widget build(BuildContext context) {
    final palette = CaeloColors.of(context);
    final l10n = AppLocalizations.of(context);
    return CupertinoPageScaffold(
      backgroundColor: palette.background,
      child: CaeloPageSurface(
        child: SafeArea(
          child: CaeloContentWidth(
            child: LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: CaeloSpace.gutter,
                  vertical: CaeloSpace.lg,
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: constraints.maxHeight - CaeloSpace.lg * 2,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(31),
                        child: Image.asset(
                          'docs/caelo.png',
                          width: 108,
                          height: 108,
                          fit: BoxFit.cover,
                        ),
                      ),
                      const SizedBox(height: CaeloSpace.lg),
                      Text(
                        l10n.welcome,
                        textAlign: TextAlign.center,
                        style: CaeloTheme.headline(palette),
                      ),
                      const SizedBox(height: CaeloSpace.sm),
                      Text(
                        l10n.welcomeExplanation,
                        textAlign: TextAlign.center,
                        style: CaeloTheme.body(
                          palette,
                        ).copyWith(color: palette.muted, height: 1.45),
                      ),
                      const SizedBox(height: CaeloSpace.lg),
                      CupertinoTextField(
                        controller: _invitation,
                        enabled: !_busy,
                        keyboardType: TextInputType.url,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _submitInvitation(),
                        placeholder: l10n.invitationPlaceholder,
                        prefix: Padding(
                          padding: const EdgeInsets.only(left: CaeloSpace.md),
                          child: Icon(
                            CupertinoIcons.link,
                            color: palette.muted,
                          ),
                        ),
                        padding: const EdgeInsets.all(CaeloSpace.md),
                        decoration: BoxDecoration(
                          color: palette.surface1,
                          borderRadius: CaeloRadius.controlAll,
                          border: Border.all(
                            color: _error == null
                                ? palette.border
                                : palette.danger,
                          ),
                        ),
                      ),
                      SizedBox(
                        height: 30,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            _error ?? '',
                            style: CaeloTheme.caption(
                              palette,
                            ).copyWith(color: palette.danger),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: double.infinity,
                        child: CupertinoButton.filled(
                          onPressed: _busy ? null : _submitInvitation,
                          borderRadius: CaeloRadius.controlAll,
                          child: _busy
                              ? const CupertinoActivityIndicator()
                              : Text(l10n.continueAction),
                        ),
                      ),
                      const SizedBox(height: CaeloSpace.sm),
                      CupertinoButton(
                        onPressed: _busy ? null : _signInWithQr,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(CupertinoIcons.qrcode_viewfinder),
                            const SizedBox(width: CaeloSpace.sm),
                            Text(l10n.qrLogin),
                          ],
                        ),
                      ),
                      const SizedBox(height: CaeloSpace.lg),
                      Text(
                        l10n.mockBackendNotice,
                        textAlign: TextAlign.center,
                        style: CaeloTheme.caption(
                          palette,
                        ).copyWith(color: palette.dim),
                      ),
                      CupertinoButton(
                        padding: const EdgeInsets.symmetric(
                          horizontal: CaeloSpace.sm,
                          vertical: CaeloSpace.xs,
                        ),
                        onPressed: _busy ? null : _importConfiguration,
                        child: Text(
                          l10n.importOwnConfiguration,
                          style: CaeloTheme.caption(
                            palette,
                          ).copyWith(color: palette.dim),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
