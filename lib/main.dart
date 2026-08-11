import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/core_tunnel_client.dart';
import 'core/helper_client.dart';
import 'core/settings_store.dart';
import 'core/system_tunnel_client.dart';
import 'core/tunnel.dart';
import 'core/tunnel_controller.dart';
import 'l10n/generated/app_localizations.dart';
import 'theme/app_theme.dart';
import 'theme/palette.dart';
import 'ui/home_screen.dart';
import 'ui/window_chrome.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const CaeloApp());
}

class CaeloApp extends StatefulWidget {
  const CaeloApp({super.key});

  @override
  State<CaeloApp> createState() => _CaeloAppState();
}

class _CaeloAppState extends State<CaeloApp> with WidgetsBindingObserver {
  // The only place a TunnelClient implementation is named.
  late final TunnelController _controller = TunnelController(_pickClient());

  CaeloThemeMode _themeMode = CaeloThemeMode.system;

  /// Prefers the privileged helper, which routes the whole machine, and falls
  /// back to the in-process tunnel when it is not installed.
  ///
  /// Chosen once at launch rather than per connection. A button whose meaning
  /// changes underneath someone — this process now, the whole machine in a
  /// minute — is worse than one that is consistently the lesser thing and says
  /// so.
  ///
  /// On Android neither applies yet: the tunnel there is a VpnService, which
  /// does not exist. The in-process client is chosen so the failure is an
  /// honest "the core is not there" rather than a crash.
  static TunnelClient _pickClient() {
    if (Platform.isMacOS && HelperClient.isRunning) return SystemTunnelClient();
    return CoreTunnelClient();
  }

  @override
  void initState() {
    super.initState();
    // The system scheme can change while the app is open, and the palette is
    // resolved from it.
    WidgetsBinding.instance.addObserver(this);
    _loadThemeMode();
  }

  Future<void> _loadThemeMode() async {
    final mode = await SettingsStore.themeMode();
    if (mounted) setState(() => _themeMode = mode);
  }

  Future<void> setThemeMode(CaeloThemeMode mode) async {
    setState(() => _themeMode = mode);
    await SettingsStore.setThemeMode(mode);
  }

  @override
  void didChangePlatformBrightness() => setState(() {});

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = _themeMode.resolve(
      WidgetsBinding.instance.platformDispatcher.platformBrightness,
    );
    WindowChrome.setBrightness(palette.brightness);

    return ThemeModeScope(
      mode: _themeMode,
      onChanged: setThemeMode,
      child: CaeloColors(
        palette: palette,
        child: TunnelScope(
          notifier: _controller,
          child: CupertinoApp(
            onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
            theme: CaeloTheme.data(palette),
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            home: const HomeScreen(),
          ),
        ),
      ),
    );
  }
}

/// Lets the settings screen read and change the scheme without being handed a
/// callback through every widget between here and there.
class ThemeModeScope extends InheritedWidget {
  const ThemeModeScope({
    required this.mode,
    required this.onChanged,
    required super.child,
    super.key,
  });

  final CaeloThemeMode mode;
  final Future<void> Function(CaeloThemeMode) onChanged;

  static ThemeModeScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ThemeModeScope>();

  @override
  bool updateShouldNotify(ThemeModeScope oldWidget) => mode != oldWidget.mode;
}
