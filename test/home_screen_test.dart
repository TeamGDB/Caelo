import 'package:caelo/core/tunnel.dart';
import 'package:caelo/core/tunnel_controller.dart';
import 'package:caelo/core/server_catalog.dart';
import 'package:caelo/l10n/generated/app_localizations.dart';
import 'package:caelo/theme/app_theme.dart';
import 'package:caelo/theme/palette.dart';
import 'package:caelo/ui/home_screen.dart';
import 'package:caelo/ui/server_picker_sheet.dart';
import 'package:caelo/ui/widgets/caelo_surface.dart';
import 'package:caelo/ui/widgets/power_button.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_tunnel_client.dart';

void main() {
  late FakeTunnelClient client;
  late TunnelController controller;
  late ServerSelectionController serverController;
  late bool configured;

  setUp(() {
    configured = false;
    client = FakeTunnelClient();
    controller = TunnelController(client, isConfigured: () async => configured);
    serverController = ServerSelectionController(const MockServerCatalog());
    serverController.servers = MockServerCatalog.servers;
    serverController.selected = serverController.servers.first;
  });

  tearDown(() {
    controller.dispose();
    serverController.dispose();
  });

  Future<void> pumpHome(WidgetTester tester, {Locale? locale}) async {
    await tester.pumpWidget(
      CaeloColors(
        palette: CaeloPalette.dark,
        child: ServerSelectionScope(
          controller: serverController,
          child: TunnelScope(
            notifier: controller,
            child: CupertinoApp(
              locale: locale,
              theme: CaeloTheme.data(CaeloPalette.dark),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: const HomeScreen(),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('keeps the area under the power button clear', (tester) async {
    await pumpHome(tester, locale: const Locale('en'));

    expect(find.text('Connect'), findsOneWidget);
    expect(find.text('No configuration yet'), findsNothing);
    expect(find.text('Selected server'), findsOneWidget);
  });

  // Being idle is not the same as having nothing to dial. Saying the second
  // when only the first is true sends someone looking for a configuration they
  // have already added.
  testWidgets('stays quiet when idle with a configuration', (tester) async {
    configured = true;
    // The controller read this once while being built, before the test set it.
    // Re-reading is what the main screen does on the way back from settings.
    await controller.refreshConfiguration();

    await pumpHome(tester, locale: const Locale('en'));
    await tester.pumpAndSettle();

    expect(find.text('Connect'), findsOneWidget);
    expect(find.text('No configuration yet'), findsNothing);
  });

  testWidgets('keeps the selected server when the core connects', (
    tester,
  ) async {
    await pumpHome(tester, locale: const Locale('en'));

    client.emit(
      const TunnelStatus(
        phase: TunnelPhase.connected,
        node: 'Frankfurt 3',
        protocol: TunnelProtocol.amneziaWg,
        pingMs: 42,
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Connected'), findsOneWidget);
    expect(find.text('Selected server'), findsOneWidget);
    expect(find.text('Helsinki'), findsOneWidget);
    expect(find.text('Frankfurt 3'), findsNothing);
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

    expect(find.text('Подключить'), findsOneWidget);
    expect(find.text('Выбранный сервер'), findsOneWidget);
  });

  // The most harmful thing this screen could do is imply the machine is
  // covered when only this process is.
  group('scope of the tunnel', () {
    const connected = TunnelStatus(
      phase: TunnelPhase.connected,
      node: '203.0.113.10:51820',
      protocol: TunnelProtocol.amneziaWg,
    );
    final caveat = find.textContaining('other apps are not routed');

    testWidgets('is spelled out when only this process is routed', (
      tester,
    ) async {
      client.coversWholeMachine = false;
      await pumpHome(tester, locale: const Locale('en'));

      client.emit(connected);
      await tester.pump(const Duration(milliseconds: 300));

      expect(caveat, findsOneWidget);
    });

    testWidgets('goes unsaid when the whole machine is routed', (tester) async {
      client.coversWholeMachine = true;
      await pumpHome(tester, locale: const Locale('en'));

      client.emit(connected);
      await tester.pump(const Duration(milliseconds: 300));

      expect(caveat, findsNothing);
    });
  });

  testWidgets('the button asks the core to connect', (tester) async {
    await pumpHome(tester, locale: const Locale('en'));

    await tester.tap(find.byType(GestureDetector).first);
    await tester.pump();

    expect(client.calls, contains('connect'));
  });

  testWidgets('keeps servers on Home and expands them only by swiping', (
    tester,
  ) async {
    await pumpHome(tester, locale: const Locale('en'));

    final surface = find.byKey(const ValueKey('server-sheet-surface'));
    final beforeTap = tester.getTopLeft(surface).dy;
    await tester.tap(find.text('Helsinki'));
    await tester.pumpAndSettle();

    expect(find.byType(ServerDrawer), findsOneWidget);
    expect(find.byType(CupertinoActionSheet), findsNothing);
    expect(tester.getTopLeft(surface).dy, beforeTap);

    await tester.drag(
      find.byKey(const ValueKey('server-drag-handle')),
      const Offset(0, -360),
    );
    await tester.pumpAndSettle();

    expect(tester.getTopLeft(surface).dy, lessThan(beforeTap - 200));
    expect(find.text('Choose server'), findsOneWidget);
  });

  testWidgets('makes the power control visually dominant', (tester) async {
    await pumpHome(tester, locale: const Locale('en'));

    expect(tester.getSize(find.byType(PowerButton)).width, greaterThan(240));
    expect(tester.getCenter(find.byType(PowerButton)).dy, greaterThan(300));
  });

  testWidgets('keeps the server section collapsed while connecting', (
    tester,
  ) async {
    await pumpHome(tester, locale: const Locale('en'));
    client.emit(const TunnelStatus(phase: TunnelPhase.connecting));
    await tester.pump(const Duration(milliseconds: 300));

    final surface = find.byKey(const ValueKey('server-sheet-surface'));
    final before = tester.getTopLeft(surface).dy;
    await tester.drag(
      find.byKey(const ValueKey('server-drag-handle')),
      const Offset(0, -360),
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(tester.getTopLeft(surface).dy, before);
  });

  testWidgets('places Settings in the upper-right safe area', (tester) async {
    await pumpHome(tester, locale: const Locale('en'));

    final button = find.byType(CaeloIconButton);
    expect(button, findsOneWidget);
    expect(tester.getTopRight(button).dx, greaterThan(700));
    expect(tester.getTopRight(button).dy, lessThan(100));
  });

  testWidgets('reserves transparent title-bar space on macOS', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      await pumpHome(tester, locale: const Locale('en'));
      expect(tester.getTopRight(find.byType(CaeloIconButton)).dy, 36);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('shows the selected mock server before the core chooses a node', (
    tester,
  ) async {
    await pumpHome(tester, locale: const Locale('en'));

    client.emit(const TunnelStatus(phase: TunnelPhase.connecting));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Connecting'), findsOneWidget);
    expect(find.text('Selected server'), findsOneWidget);
    expect(find.text('Helsinki'), findsOneWidget);
  });

  testWidgets('shows the real disconnecting phase inside the button', (
    tester,
  ) async {
    await pumpHome(tester, locale: const Locale('en'));

    client.emit(const TunnelStatus(phase: TunnelPhase.disconnecting));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Disconnecting'), findsOneWidget);
  });

  testWidgets('does not move the power button when tunnel phase changes', (
    tester,
  ) async {
    await pumpHome(tester, locale: const Locale('en'));
    final power = find.text('Connect');
    final before = tester.getCenter(power);

    client.emit(
      const TunnelStatus(phase: TunnelPhase.connected, node: 'Helsinki 1'),
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(tester.getCenter(find.text('Connected')), before);
  });

  testWidgets('fits the compact reference viewport in Russian', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await pumpHome(tester, locale: const Locale('ru'));

    expect(find.text('Подключить'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
