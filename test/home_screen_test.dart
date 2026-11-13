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
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_tunnel_client.dart';
import 'fake_server_catalog.dart';

void main() {
  late FakeTunnelClient client;
  late TunnelController controller;
  late ServerSelectionController serverController;
  late bool configured;

  setUp(() {
    configured = false;
    client = FakeTunnelClient();
    controller = TunnelController(client, isConfigured: () async => configured);
    serverController = ServerSelectionController(
      const FakeServerCatalog(),
      readSelected: () async => null,
      writeSelected: (_) async {},
      activateConfiguration: (_) async {},
      activateNode: (_, _) async {},
      // These tests set the list's figures themselves. Opening the list
      // measures it (#156), which has its own tests below.
      backgroundMeasurement: false,
    );
    serverController.servers = FakeServerCatalog.servers;
    serverController.selected = serverController.servers.first;
  });

  tearDown(() {
    controller.dispose();
    serverController.dispose();
  });

  Future<void> pumpHome(
    WidgetTester tester, {
    Locale? locale,
    CaeloPalette palette = CaeloPalette.dark,
    double bottomInset = 0,
  }) async {
    final home = bottomInset == 0
        ? const HomeScreen()
        : MediaQuery(
            data: MediaQueryData(
              size: const Size(800, 600),
              padding: EdgeInsets.only(bottom: bottomInset),
            ),
            child: const HomeScreen(),
          );
    await tester.pumpWidget(
      CaeloColors(
        palette: palette,
        child: ServerSelectionScope(
          controller: serverController,
          child: TunnelScope(
            notifier: controller,
            child: CupertinoApp(
              locale: locale,
              theme: CaeloTheme.data(palette),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: home,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('the open list says what it cannot show (#172)', (tester) async {
    serverController.notes = const [
      SubscriptionNote.empty(title: 'Home'),
      SubscriptionNote.skipped(['vmess', 'vmess']),
    ];
    await pumpHome(tester, locale: const Locale('en'));
    await tester.tap(find.byKey(const ValueKey('server-drag-handle')));
    await tester.pumpAndSettle();
    // Below the servers: scrolled to, as a person would.
    await tester.drag(
      find.byKey(const ValueKey('server-list-scroll')),
      const Offset(0, -2000),
    );
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Home: The subscription has no servers yet. Ask whoever gave you the link.',
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        '2 servers are not shown: this version of Caelo cannot run them (vmess).',
      ),
      findsOneWidget,
    );
  });

  testWidgets('keeps the area under the power button clear', (tester) async {
    await pumpHome(tester, locale: const Locale('en'));

    expect(find.text('Connect'), findsOneWidget);
    expect(find.text('No configuration yet'), findsNothing);
    expect(find.text('Current server'), findsOneWidget);
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
    expect(find.text('Current server'), findsOneWidget);
    expect(find.text('Helsinki'), findsOneWidget);
    expect(find.text('Frankfurt 3'), findsNothing);
  });

  testWidgets('shows a measured ping for the selected custom server only', (
    tester,
  ) async {
    const custom = ServerOption(
      id: 'user-office',
      name: 'Office',
      description: 'Work network',
      flag: '🏢',
      configId: 'office',
    );
    serverController.servers = const [custom];
    serverController.selected = custom;
    await pumpHome(tester, locale: const Locale('en'));

    expect(find.text('42 ms'), findsNothing);

    client.emit(
      const TunnelStatus(
        phase: TunnelPhase.connected,
        node: 'Office',
        pingMs: 42,
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('42 ms'), findsOneWidget);

    client.emit(const TunnelStatus.disconnected());
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('42 ms'), findsNothing);
  });

  group('live ping (#156)', () {
    const custom = ServerOption(
      id: 'user-office',
      name: 'Office',
      description: 'Work network',
      flag: '🏢',
      configId: 'office',
    );
    const connected = TunnelStatus(
      phase: TunnelPhase.connected,
      node: 'Office',
      pingMs: 42,
    );

    setUp(() {
      serverController.servers = const [custom];
      serverController.selected = custom;
    });

    testWidgets('replaces the probe figure while connected, and goes with '
        'the tunnel', (tester) async {
      client.latencyAnswer = () async => 37;
      await pumpHome(tester, locale: const Locale('en'));

      client.emit(connected);
      await tester.pump(const Duration(milliseconds: 300));
      // The fake answers outside the test's clock; let it.
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
      expect(find.text('37 ms'), findsOneWidget);
      expect(find.text('42 ms'), findsNothing);

      client.latencyAnswer = () async => 33;
      await tester.runAsync(controller.askLatency);
      await tester.pump();
      expect(find.text('33 ms'), findsOneWidget);

      client.emit(const TunnelStatus.disconnected());
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('33 ms'), findsNothing);
      expect(find.text('42 ms'), findsNothing);
    });

    testWidgets('until there is one, the probe figure stays', (tester) async {
      await pumpHome(tester, locale: const Locale('en'));
      client.emit(connected);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('42 ms'), findsOneWidget);
    });
  });

  group('opening the list (#156)', () {
    testWidgets('tells it it is open, and closing it says so', (tester) async {
      await pumpHome(tester, locale: const Locale('en'));
      expect(serverController.listOpen, isFalse, reason: 'only peeking');

      await tester.tap(find.byKey(const ValueKey('server-drag-handle')));
      await tester.pumpAndSettle();
      expect(serverController.listOpen, isTrue);

      await tester.tap(find.byKey(const ValueKey('server-drag-handle')));
      await tester.pumpAndSettle();
      expect(serverController.listOpen, isFalse);
    });

    testWidgets('connecting closes it', (tester) async {
      await pumpHome(tester, locale: const Locale('en'));
      await tester.tap(find.byKey(const ValueKey('server-drag-handle')));
      await tester.pumpAndSettle();
      expect(serverController.listOpen, isTrue);

      client.emit(const TunnelStatus(phase: TunnelPhase.connecting));
      await tester.pump(const Duration(milliseconds: 300));
      expect(serverController.listOpen, isFalse);
    });

    testWidgets('leaving the screen closes it', (tester) async {
      await pumpHome(tester, locale: const Locale('en'));
      await tester.tap(find.byKey(const ValueKey('server-drag-handle')));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
      expect(serverController.listOpen, isFalse);
    });

    testWidgets('measures the servers in it', (tester) async {
      final probed = <String>[];
      final measuring = ServerSelectionController(
        _CountingCatalog(probed),
        readSelected: () async => null,
        writeSelected: (_) async {},
        activateConfiguration: (_) async {},
        activateNode: (_, _) async {},
        latencyRefreshInterval: null,
      );
      // tearDown disposes whichever is current; the one from setUp is ours.
      addTearDown(serverController.dispose);
      serverController = measuring;
      await tester.runAsync(measuring.load);
      await pumpHome(tester, locale: const Locale('en'));
      expect(probed, isEmpty, reason: 'nobody opened it yet');

      await tester.tap(find.byKey(const ValueKey('server-drag-handle')));
      await tester.pumpAndSettle();
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();

      expect(probed, isNotEmpty);
      expect(find.text('64 ms'), findsWidgets);
    });
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
    expect(find.text('Текущий сервер'), findsOneWidget);
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

  testWidgets('keeps servers on Home and expands on the selected server tap', (
    tester,
  ) async {
    await pumpHome(tester, locale: const Locale('en'));

    final surface = find.byKey(const ValueKey('server-sheet-surface'));
    final beforeTap = tester.getTopLeft(surface).dy;
    await tester.tap(find.text('Helsinki'));
    await tester.pumpAndSettle();

    expect(find.byType(ServerDrawer), findsOneWidget);
    expect(find.byType(CupertinoActionSheet), findsNothing);
    await tester.pumpAndSettle();

    expect(tester.getTopLeft(surface).dy, lessThan(beforeTap - 200));
    expect(find.text('Choose server'), findsOneWidget);
    expect(
      find.text('Preview servers until your account backend is connected'),
      findsNothing,
    );
    expect(find.text('Main'), findsNothing);
    expect(find.text('Stable'), findsNothing);
    expect(find.text('Testing'), findsNothing);
    expect(find.byType(CupertinoScrollbar), findsOneWidget);
    expect(
      tester.getTopLeft(find.byType(CupertinoScrollbar)).dy,
      tester.getTopLeft(find.byKey(const ValueKey('server-list-scroll'))).dy,
    );
    expect(
      tester.getTopLeft(find.byType(CupertinoScrollbar)).dy,
      greaterThan(tester.getBottomLeft(find.text('Choose server')).dy),
    );

    final unselected = tester.widget<Container>(
      find.byKey(const ValueKey('server-row-test-stockholm')),
    );
    final decoration = unselected.decoration! as BoxDecoration;
    expect(decoration.color, const Color(0x00000000));
    expect(decoration.border, isNull);
  });

  group('flags (#168)', () {
    // Every flag on screen: the selected server's and each row's.
    List<Text> flags(WidgetTester tester) => tester
        .widgetList<Text>(find.byType(Text))
        .where((text) => const ['🇫🇮', '🇸🇪', '🇩🇪'].contains(text.data))
        .toList();

    Future<void> openList(WidgetTester tester) async {
      await pumpHome(tester, locale: const Locale('en'));
      await tester.tap(find.text('Helsinki'));
      await tester.pumpAndSettle();
    }

    testWidgets('come from the bundled font on Windows, which has none', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      try {
        await openList(tester);
        final shown = flags(tester);
        // The header and the three rows.
        expect(shown, hasLength(4));
        for (final flag in shown) {
          expect(flag.style?.fontFamily, CaeloTheme.flagFontFamily);
        }
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('stay the system emoji everywhere else', (tester) async {
      for (final platform in [
        TargetPlatform.macOS,
        TargetPlatform.linux,
        TargetPlatform.android,
        TargetPlatform.iOS,
      ]) {
        debugDefaultTargetPlatformOverride = platform;
        try {
          await openList(tester);
          final shown = flags(tester);
          expect(shown, isNotEmpty, reason: '$platform');
          for (final flag in shown) {
            expect(flag.style?.fontFamily, isNull, reason: '$platform');
          }
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
        await tester.pumpWidget(const SizedBox());
      }
    });
  });

  testWidgets('tapping the current server toggles the section closed', (
    tester,
  ) async {
    await pumpHome(tester, locale: const Locale('en'));
    final surface = find.byKey(const ValueKey('server-sheet-surface'));
    final collapsedTop = tester.getTopLeft(surface).dy;

    await tester.tap(find.text('Helsinki'));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(surface).dy, lessThan(collapsedTop - 200));

    await tester.tap(find.text('Helsinki').first);
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(surface).dy, collapsedTop);
  });

  testWidgets('selecting a row closes the server section', (tester) async {
    await pumpHome(tester, locale: const Locale('en'));
    final surface = find.byKey(const ValueKey('server-sheet-surface'));
    final collapsedTop = tester.getTopLeft(surface).dy;

    await tester.tap(find.text('Helsinki'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('server-row-test-stockholm')),
        matching: find.text('Stockholm'),
      ),
    );
    await tester.pumpAndSettle();

    expect(serverController.selected?.name, 'Stockholm');
    expect(tester.getTopLeft(surface).dy, collapsedTop);
  });

  testWidgets('keeps every list latency in the same column', (tester) async {
    await pumpHome(tester, locale: const Locale('en'));
    await tester.tap(find.text('Helsinki'));
    await tester.pumpAndSettle();

    final first = find.byKey(const ValueKey('server-latency-test-helsinki'));
    final second = find.byKey(const ValueKey('server-latency-test-stockholm'));
    expect(tester.getTopRight(first).dx, tester.getTopRight(second).dx);
  });

  group('the list (#109)', () {
    const measured = ServerOption(
      id: 'a',
      name: 'Amber',
      description: 'Every day',
      flag: '🇱🇻',
      latencyMs: 30,
      nodeId: 'a',
      subscriptionId: 's',
    );
    const unmeasured = ServerOption(
      id: 'b',
      name: 'Buran',
      description: 'For things in Russia',
      flag: '🇷🇺',
      nodeId: 'b',
      subscriptionId: 's',
    );

    Future<void> open(WidgetTester tester) async {
      await pumpHome(tester, locale: const Locale('en'));
      await tester.tap(find.byKey(const ValueKey('server-drag-handle')));
      await tester.pumpAndSettle();
    }

    testWidgets('a server that did not answer shows a dash, and the rest '
        'their latency', (tester) async {
      serverController.servers = [
        const ServerOption.automatic(),
        measured,
        unmeasured.withUnreachable(),
      ];
      serverController.selected = serverController.servers.first;
      await open(tester);

      expect(find.text('30 ms'), findsOneWidget);
      final dash = tester.widget<Text>(
        find.byKey(const ValueKey('server-latency-b')),
      );
      expect(dash.data, '—');
    });

    testWidgets('shows no latency while any server is still unmeasured', (
      tester,
    ) async {
      serverController.servers = const [
        ServerOption.automatic(),
        measured,
        unmeasured,
      ];
      serverController.selected = serverController.servers.first;
      await open(tester);

      expect(find.byKey(const ValueKey('server-latency-a')), findsNothing);
      expect(find.text('30 ms'), findsNothing);
    });

    testWidgets('shows it for every server once all have one', (tester) async {
      serverController.servers = [
        const ServerOption.automatic(),
        measured,
        unmeasured.withLatency(55),
      ];
      serverController.selected = serverController.servers.first;
      await open(tester);

      expect(find.byKey(const ValueKey('server-latency-a')), findsOneWidget);
      expect(find.byKey(const ValueKey('server-latency-b')), findsOneWidget);
    });

    testWidgets('a server without keys does not hide everyone else\'s', (
      tester,
    ) async {
      serverController.servers = const [
        ServerOption.automatic(),
        measured,
        ServerOption(
          id: 'offer',
          name: 'Truffle',
          description: 'Every day',
          flag: '🇫🇷',
          subscriptionId: 's',
          serverId: 'truffle',
        ),
      ];
      serverController.selected = serverController.servers.first;
      await open(tester);

      expect(find.byKey(const ValueKey('server-latency-a')), findsOneWidget);
      expect(find.byKey(const ValueKey('server-latency-offer')), findsNothing);
    });

    testWidgets('automatic is the default and needs no latency of its own', (
      tester,
    ) async {
      serverController.servers = [
        const ServerOption.automatic(),
        measured,
        unmeasured.withLatency(55),
      ];
      serverController.selected = serverController.servers.first;
      await open(tester);

      expect(find.byKey(const ValueKey('server-latency-auto')), findsNothing);
      expect(find.text('Automatic'), findsWidgets);
    });

    testWidgets('a long description wraps instead of being cut off', (
      tester,
    ) async {
      const wordy = ServerOption(
        id: 'k',
        name: 'Kazy',
        description:
            'A long description that will not fit on one line of the list',
        flag: '🇰🇿',
        latencyMs: 238,
        nodeId: 'k',
        subscriptionId: 's',
      );
      serverController.servers = const [ServerOption.automatic(), wordy];
      serverController.selected = serverController.servers.first;
      await open(tester);

      final text = tester.widget<Text>(
        find.byKey(const ValueKey('server-description-k')),
      );
      expect(text.maxLines, isNull);
      expect(text.overflow, isNot(TextOverflow.ellipsis));
      final paragraph = tester.renderObject<RenderParagraph>(
        find.byKey(const ValueKey('server-description-k')),
      );
      expect(paragraph.didExceedMaxLines, isFalse);
      expect(
        tester
            .getSize(find.byKey(const ValueKey('server-description-k')))
            .height,
        greaterThan(30),
        reason: 'it should take more than one line',
      );
    });
  });

  testWidgets('scrolling the server list cannot close the section', (
    tester,
  ) async {
    await pumpHome(tester, locale: const Locale('en'));
    final surface = find.byKey(const ValueKey('server-sheet-surface'));

    await tester.drag(
      find.byKey(const ValueKey('server-drag-handle')),
      const Offset(0, -360),
    );
    await tester.pumpAndSettle();
    final expandedTop = tester.getTopLeft(surface).dy;
    final headingTop = tester.getTopLeft(find.text('Choose server')).dy;

    await tester.drag(
      find.byKey(const ValueKey('server-list-scroll')),
      const Offset(0, -220),
    );
    await tester.pumpAndSettle();

    expect(tester.getTopLeft(find.text('Choose server')).dy, headingTop);

    await tester.drag(
      find.byKey(const ValueKey('server-list-scroll')),
      const Offset(0, 220),
    );
    await tester.pumpAndSettle();

    expect(tester.getTopLeft(surface).dy, expandedTop);
  });

  testWidgets('makes the power control visually dominant', (tester) async {
    await pumpHome(tester, locale: const Locale('en'));

    expect(tester.getSize(find.byType(PowerButton)).width, greaterThan(280));
    expect(
      tester.getCenter(find.byType(PowerButton)).dy,
      greaterThanOrEqualTo(290),
    );
    expect(tester.getCenter(find.byType(PowerButton)).dy, lessThan(315));
  });

  testWidgets('uses a dark idle label in the light theme', (tester) async {
    await pumpHome(
      tester,
      locale: const Locale('en'),
      palette: CaeloPalette.light,
    );

    final label = tester.widget<Text>(find.text('Connect'));
    expect(label.style?.color, const Color(0xFF101414));
  });

  testWidgets('server surface covers the bottom safe-area background', (
    tester,
  ) async {
    await pumpHome(tester, locale: const Locale('en'), bottomInset: 24);

    expect(
      tester
          .getBottomLeft(find.byKey(const ValueKey('server-sheet-surface')))
          .dy,
      600,
    );
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
    expect(find.text('Current server'), findsOneWidget);
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

  // A failure the person can act on has to say so where they are looking. Left
  // as a bare "could not connect" they would press the button again, which for
  // a version mismatch is the one thing guaranteed not to work.
  testWidgets('names the half that is out of date', (tester) async {
    await pumpHome(tester, locale: const Locale('en'));

    client.emit(
      const TunnelStatus(
        phase: TunnelPhase.failed,
        failure: TunnelFailure.serviceOlderThanApp,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Reinstall Caelo'), findsOneWidget);
  });

  testWidgets('says the opposite thing when the app is the old half', (
    tester,
  ) async {
    await pumpHome(tester, locale: const Locale('en'));

    client.emit(
      const TunnelStatus(
        phase: TunnelPhase.failed,
        failure: TunnelFailure.appOlderThanService,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Update Caelo'), findsOneWidget);
  });

  // On Linux the socket refuses whoever is not in the caelo group, and the two
  // remedies differ: a new login, or being added first (#116).
  testWidgets('says how to get access to the service', (tester) async {
    await pumpHome(tester, locale: const Locale('en'));

    client.emit(
      const TunnelStatus(
        phase: TunnelPhase.failed,
        failure: TunnelFailure.serviceNeedsGroup,
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.textContaining('sudo usermod -aG caelo \$USER'),
      findsOneWidget,
    );

    client.emit(
      const TunnelStatus(
        phase: TunnelPhase.failed,
        failure: TunnelFailure.serviceNeedsRelogin,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Log out and back in'), findsOneWidget);
    expect(find.textContaining('usermod'), findsNothing);
  });

  // Most failures are worth retrying and have nothing useful to add. An
  // explanation under every one of them would train people to ignore the place
  // the useful ones appear.
  testWidgets('stays quiet about failures it cannot explain', (tester) async {
    await pumpHome(tester, locale: const Locale('en'));
    final resting = tester.getCenter(find.text('Connect'));

    client.emit(const TunnelStatus(phase: TunnelPhase.failed));
    await tester.pumpAndSettle();

    expect(find.text('Could not connect'), findsOneWidget);
    expect(find.textContaining('Reinstall'), findsNothing);
    expect(find.textContaining('Update'), findsNothing);
    // And with nothing to say, the button stays exactly where it was.
    expect(tester.getCenter(find.text('Could not connect')), resting);
  });

  // The clients that raise these run below the interface and have no locale, so
  // this is the join that would silently leave English in a Russian window.
  testWidgets('explains itself in the chosen language', (tester) async {
    await pumpHome(tester, locale: const Locale('ru'));

    client.emit(
      const TunnelStatus(
        phase: TunnelPhase.failed,
        failure: TunnelFailure.serviceOlderThanApp,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Переустановите Caelo'), findsOneWidget);
  });
}

/// The fake catalog, counting what is measured and answering 64 ms.
class _CountingCatalog extends FakeServerCatalog {
  _CountingCatalog(this.probed);
  final List<String> probed;

  @override
  Future<int?> measureLatency(ServerOption server) async {
    probed.add(server.id);
    return 64;
  }
}
