import 'package:flutter/cupertino.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/core_tunnel_client.dart';
import 'core/helper_client.dart';
import 'core/system_tunnel_client.dart';
import 'core/tunnel.dart';
import 'core/tunnel_controller.dart';
import 'l10n/generated/app_localizations.dart';
import 'theme/app_theme.dart';
import 'ui/home_screen.dart';

void main() {
  runApp(const CaeloApp());
}

class CaeloApp extends StatefulWidget {
  const CaeloApp({super.key});

  @override
  State<CaeloApp> createState() => _CaeloAppState();
}

class _CaeloAppState extends State<CaeloApp> {
  // The only place a TunnelClient implementation is named.
  late final TunnelController _controller = TunnelController(_pickClient());

  /// Prefers the privileged helper, which routes the whole machine, and falls
  /// back to the in-process tunnel when it is not installed.
  ///
  /// Chosen once at launch rather than per connection. A button whose meaning
  /// changes underneath someone — this process now, the whole machine in a
  /// minute — is worse than one that is consistently the lesser thing and says
  /// so.
  static TunnelClient _pickClient() {
    if (HelperClient.isRunning) return SystemTunnelClient();
    return CoreTunnelClient();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TunnelScope(
      notifier: _controller,
      child: CupertinoApp(
        onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
        theme: CaeloTheme.data,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: const HomeScreen(),
      ),
    );
  }
}
