import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/android_tunnel_client.dart';
import 'core/account_gateway.dart';
import 'core/core_tunnel_client.dart';
import 'core/service_client.dart';
import 'core/service_tunnel_client.dart';
import 'core/diagnostics.dart';
import 'core/apple_tunnel_client.dart';
import 'core/settings_store.dart';
import 'core/server_catalog.dart';
import 'core/tunnel.dart';
import 'core/tunnel_controller.dart';
import 'l10n/generated/app_localizations.dart';
import 'theme/app_theme.dart';
import 'theme/palette.dart';
import 'ui/home_screen.dart';
import 'ui/welcome_screen.dart';
import 'ui/window_chrome.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Before the first frame, so that a connection attempted immediately after
  // launch is recorded. Failing to read the preference is not a reason to
  // refuse to start.
  await Diagnostics.load().catchError((_) {});

  // Resolve appearance before the first frame. A saved dark scheme or Russian
  // locale should not briefly render as the system default on every launch.
  var themeMode = CaeloThemeMode.system;
  var localeMode = CaeloLocaleMode.system;
  var accessGranted = false;
  try {
    themeMode = await SettingsStore.themeMode();
  } on Object {
    // Defaults are usable even if the settings directory is unavailable.
  }
  try {
    localeMode = await SettingsStore.localeMode();
  } on Object {
    // Locale failure is independent of theme failure and falls back to the OS.
  }
  try {
    accessGranted = await SettingsStore.accessGranted();
  } on Object {
    // A missing or unreadable setting means onboarding has not completed.
  }

  runApp(
    CaeloApp(
      themeMode: themeMode,
      localeMode: localeMode,
      accessGranted: accessGranted,
    ),
  );
}

class CaeloApp extends StatefulWidget {
  const CaeloApp({
    this.themeMode = CaeloThemeMode.system,
    this.localeMode = CaeloLocaleMode.system,
    this.accessGranted = false,
    this.accountGateway = const MockAccountGateway(),
    super.key,
  });

  final CaeloThemeMode themeMode;
  final CaeloLocaleMode localeMode;
  final bool accessGranted;
  final AccountGateway accountGateway;

  @override
  State<CaeloApp> createState() => _CaeloAppState();
}

class _CaeloAppState extends State<CaeloApp> with WidgetsBindingObserver {
  // The only place a TunnelClient implementation is named.
  late final TunnelController _controller = TunnelController(_pickClient());

  late CaeloThemeMode _themeMode = widget.themeMode;
  late CaeloLocaleMode _localeMode = widget.localeMode;
  late bool _accessGranted = widget.accessGranted;
  late final ServerSelectionController _servers = ServerSelectionController(
    const DevelopmentServerCatalog(),
  );

  /// The system tunnel wherever there is one, and the in-process tunnel where
  /// there is not.
  ///
  /// Android, iOS and macOS have a platform arrangement and it is the only path
  /// that can route the machine. On Linux the privileged service does the same
  /// job, and its absence is an ordinary state rather than a fault: someone
  /// running from an AppImage, or on a machine where they cannot install
  /// anything, still gets a working tunnel for this process — and the interface
  /// says which of the two they have.
  ///
  /// Chosen once at launch rather than per connection. A button whose meaning
  /// changes underneath someone — this process now, the whole machine in a
  /// minute — is worse than one that is consistently the lesser thing and says
  /// so.
  static TunnelClient _pickClient() {
    if (Platform.isAndroid) return AndroidTunnelClient();
    if (AppleTunnelClient.isSupported) return AppleTunnelClient();
    if (ServiceClient.isInstalled) return ServiceTunnelClient();
    return CoreTunnelClient();
  }

  @override
  void initState() {
    super.initState();
    // The system scheme can change while the app is open, and the palette is
    // resolved from it.
    WidgetsBinding.instance.addObserver(this);
    _servers.load();
  }

  Future<void> setThemeMode(CaeloThemeMode mode) async {
    setState(() => _themeMode = mode);
    await SettingsStore.setThemeMode(mode);
  }

  Future<void> setLocaleMode(CaeloLocaleMode mode) async {
    setState(() => _localeMode = mode);
    await SettingsStore.setLocaleMode(mode);
  }

  Future<void> setAccessGranted(bool granted) async {
    setState(() => _accessGranted = granted);
    await SettingsStore.setAccessGranted(granted);
  }

  @override
  void didChangePlatformBrightness() => setState(() {});

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    _servers.dispose();
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
      child: LocaleModeScope(
        mode: _localeMode,
        onChanged: setLocaleMode,
        child: ServerSelectionScope(
          controller: _servers,
          child: AccessScope(
            accessGranted: _accessGranted,
            onChanged: setAccessGranted,
            child: CaeloColors(
              palette: palette,
              child: TunnelScope(
                notifier: _controller,
                child: CupertinoApp(
                  locale: _localeMode.locale,
                  onGenerateTitle: (context) =>
                      AppLocalizations.of(context).appTitle,
                  theme: CaeloTheme.data(palette),
                  localizationsDelegates: const [
                    AppLocalizations.delegate,
                    GlobalCupertinoLocalizations.delegate,
                    GlobalWidgetsLocalizations.delegate,
                  ],
                  supportedLocales: AppLocalizations.supportedLocales,
                  home: _accessGranted
                      ? const HomeScreen()
                      : WelcomeScreen(
                          gateway: widget.accountGateway,
                          onGranted: () => setAccessGranted(true),
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

class AccessScope extends InheritedWidget {
  const AccessScope({
    required this.accessGranted,
    required this.onChanged,
    required super.child,
    super.key,
  });

  final bool accessGranted;
  final Future<void> Function(bool) onChanged;

  static AccessScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AccessScope>();

  @override
  bool updateShouldNotify(AccessScope oldWidget) =>
      accessGranted != oldWidget.accessGranted;
}

/// The saved locale preference. Null locale in [CaeloLocaleMode.system] lets
/// Flutter resolve the operating system locale in the ordinary way.
class LocaleModeScope extends InheritedWidget {
  const LocaleModeScope({
    required this.mode,
    required this.onChanged,
    required super.child,
    super.key,
  });

  final CaeloLocaleMode mode;
  final Future<void> Function(CaeloLocaleMode) onChanged;

  static LocaleModeScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<LocaleModeScope>();

  @override
  bool updateShouldNotify(LocaleModeScope oldWidget) => mode != oldWidget.mode;
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
