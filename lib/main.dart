import 'package:flutter/cupertino.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/stub_tunnel_client.dart';
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
  // The only place the stub is named. Swapping in the gRPC client against
  // caelo-core is a one-line change here and nothing else moves.
  late final TunnelController _controller = TunnelController(
    StubTunnelClient(),
  );

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
