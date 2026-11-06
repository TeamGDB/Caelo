import 'dart:async';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/android_tunnel_client.dart';
import 'core/account_data.dart';
import 'core/account_gateway.dart';
import 'core/core_tunnel_client.dart';
import 'core/desktop_updater.dart';
import 'core/update_download.dart';
import 'core/service_client.dart';
import 'core/service_tunnel_client.dart';
import 'core/diagnostics.dart';
import 'core/apple_tunnel_client.dart';
import 'core/settings_store.dart';
import 'core/server_catalog.dart';
import 'core/subscription_fetcher.dart';
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
    await SettingsStore.migrateSelection();
  } on Object {
    // A choice that stays manual is not worth refusing to start over.
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
    this.accountGateway = const SubscriptionAccountGateway(),
    this.tunnelClient,
    this.serverCatalog,
    super.key,
  });

  /// Replaces the platform's tunnel and the subscription-backed server list.
  /// Seams for driving the whole app in a test; null in the product.
  final TunnelClient? tunnelClient;
  final ServerCatalog? serverCatalog;

  final CaeloThemeMode themeMode;
  final CaeloLocaleMode localeMode;
  final bool accessGranted;
  final AccountGateway accountGateway;

  @override
  State<CaeloApp> createState() => _CaeloAppState();
}

class _CaeloAppState extends State<CaeloApp> with WidgetsBindingObserver {
  late CaeloThemeMode _themeMode = widget.themeMode;
  late CaeloLocaleMode _localeMode = widget.localeMode;
  late bool _accessGranted = widget.accessGranted;
  late final ServerSelectionController _servers = ServerSelectionController(
    widget.serverCatalog ?? SubscriptionServerCatalog(),
  );

  // The only place a TunnelClient implementation is named. What it dials is
  // decided by the server list right before each connection, so the server the
  // screen shows and the one the tunnel uses cannot drift apart (#101).
  late final TunnelController _controller = TunnelController(
    widget.tunnelClient ?? _pickClient(),
    prepare: _servers.prepareConnection,
  );

  /// When subscriptions were last looked at. Coming back to the app is a good
  /// moment to see whether they changed, but not every few seconds.
  DateTime _lastRefresh = DateTime.now();
  static const _refreshOnResumeAfter = Duration(minutes: 15);
  Timer? _periodicRefresh;

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
    // The server in use was removed from the subscription: move the tunnel
    // somewhere that still exists rather than leave it on a peer about to
    // vanish (#111).
    _servers.onActiveRemoved = (_) => unawaited(_controller.reconnect());
    // Somebody who keeps the app on screen should see servers come and go as
    // well as somebody who reopens it (#111).
    _periodicRefresh = Timer.periodic(_refreshOnResumeAfter, (_) {
      final state = WidgetsBinding.instance.lifecycleState;
      if (_accessGranted && state == AppLifecycleState.resumed) {
        unawaited(_loadServers());
      }
    });
    _controller.addListener(_onTunnelChanged);
    unawaited(_loadServers());
    // After the setting has been read, not before: the updater is handed the
    // answer rather than starting and being corrected.
    unawaited(DesktopUpdater.start());
    // Whatever the last update attempt left behind, now that the installer is
    // certainly finished with it.
    unawaited(UpdateDownload.discardLeftovers());
  }

  void _onTunnelChanged() {
    final phase = _controller.value.phase;
    _servers.tunnelActive =
        phase != TunnelPhase.disconnected && phase != TunnelPhase.failed;
    if (phase == TunnelPhase.connected) unawaited(_servers.rememberActive());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || !_accessGranted) return;
    if (DateTime.now().difference(_lastRefresh) < _refreshOnResumeAfter) return;
    unawaited(_loadServers());
  }

  Future<void> _loadServers() async {
    _lastRefresh = DateTime.now();
    // Cached nodes make Home useful immediately, including while offline.
    await _servers.load();
    try {
      await SubscriptionFetcher.refreshDue();
      await _servers.load();
      await _provisionAll();
    } on Object catch (error) {
      Diagnostics.record('subscription startup refresh failed', error: error);
    }
  }

  Future<void> _completeOnboarding() async {
    // The gateway has stored the freshly fetched subscription. Reload before
    // exposing Home so its first frame already contains the real node list.
    await _servers.load();
    await setAccessGranted(true);
    // Keys for every other server, behind Home rather than before it (#110).
    unawaited(_provisionAll());
  }

  /// Asks for keys on every server the subscriptions offer and this device
  /// has none for, then shows them.
  Future<void> _provisionAll() async {
    try {
      final refusedBefore = SubscriptionFetcher.refused.length;
      final granted = await SubscriptionFetcher.enableAll();
      // New keys add servers; a refusal takes one out (#110).
      if (granted > 0 || SubscriptionFetcher.refused.length != refusedBefore) {
        await _servers.load();
      }
    } on Object catch (error) {
      Diagnostics.record('asking for keys failed', error: error);
    }
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
    if (!granted) {
      // Forgetting the account forgets what came with it. Leaving the
      // subscriptions and configurations behind is how a second onboarding
      // ended up with two copies of every server (#103).
      if (_controller.value.phase != TunnelPhase.disconnected &&
          _controller.value.phase != TunnelPhase.failed) {
        await _controller.toggle().catchError((_) {});
      }
      await AccountData.forget().catchError((Object error) {
        Diagnostics.record('forgetting account data failed', error: error);
      });
      _servers.clear();
      await _controller.refreshConfiguration();
    }
    setState(() => _accessGranted = granted);
    await SettingsStore.setAccessGranted(granted);
  }

  @override
  void didChangePlatformBrightness() => setState(() {});

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _periodicRefresh?.cancel();
    _controller.removeListener(_onTunnelChanged);
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
                          onGranted: _completeOnboarding,
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
