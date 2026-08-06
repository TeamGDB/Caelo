import 'package:caelo/core/tunnel.dart';
import 'package:caelo/core/tunnel_controller.dart';
import 'package:caelo/l10n/generated/app_localizations.dart';
import 'package:caelo/theme/app_theme.dart';
import 'package:caelo/ui/home_screen.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_tunnel_client.dart';

void main() {
  late FakeTunnelClient client;
  late TunnelController controller;

  setUp(() {
    client = FakeTunnelClient();
    controller = TunnelController(client);
  });

  tearDown(() => controller.dispose());

  Future<void> pumpHome(WidgetTester tester, {Locale? locale}) async {
    await tester.pumpWidget(
      TunnelScope(
        notifier: controller,
        child: CupertinoApp(
          locale: locale,
          theme: CaeloTheme.data,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const HomeScreen(),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('says so when nothing is configured', (
    tester,
  ) async {
    await pumpHome(tester, locale: const Locale('en'));

    expect(find.text('Not connected'), findsOneWidget);
    expect(find.text('No configuration yet'), findsOneWidget);
  });

  testWidgets('names the node and protocol once connected', (tester) async {
    await pumpHome(tester, locale: const Locale('en'));

    client.emit(
      const TunnelStatus(
        phase: TunnelPhase.connected,
        node: 'Frankfurt 3',
        protocol: TunnelProtocol.amneziaWg,
        pingMs: 42,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Connected'), findsOneWidget);
    expect(find.textContaining('Frankfurt 3'), findsOneWidget);
    expect(find.textContaining('AmneziaWG'), findsOneWidget);
    expect(find.textContaining('42'), findsOneWidget);
  });

  testWidgets('says so when an attempt fails', (tester) async {
    await pumpHome(tester, locale: const Locale('en'));

    client.emit(const TunnelStatus(phase: TunnelPhase.failed));
    await tester.pumpAndSettle();

    expect(find.text('Could not connect'), findsOneWidget);
    // A failure is not the same as being idle, and must not read as such.
    expect(find.text('Not connected'), findsNothing);
  });

  testWidgets('translates into Russian', (tester) async {
    await pumpHome(tester, locale: const Locale('ru'));

    expect(find.text('Отключено'), findsOneWidget);
    expect(find.text('Конфиг не добавлен'), findsOneWidget);
  });

  testWidgets('the button asks the core to connect', (tester) async {
    await pumpHome(tester, locale: const Locale('en'));

    await tester.tap(find.byType(GestureDetector).first);
    await tester.pump();

    expect(client.calls, contains('connect'));
  });
}
