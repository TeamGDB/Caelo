// Whole-app scenarios, driven the way a person drives the app: by tapping.
//
// Everything below the interface is real — the stores write files, the server
// list is the subscription-backed one, the tunnel controller makes its own
// decisions. Only the network and the tunnel are stand-ins: a subscription that
// answers with a fixed node list, a probe that answers by endpoint, and a
// tunnel that "connects" to whatever configuration is active and reports what
// it dialled.

import 'dart:async';
import 'dart:io';

import 'package:caelo/core/account_gateway.dart';
import 'package:caelo/core/app_storage.dart';
import 'package:caelo/core/config_store.dart';
import 'package:caelo/core/server_catalog.dart';
import 'package:caelo/core/settings_store.dart';
import 'package:caelo/core/subscription.dart';
import 'package:caelo/core/subscription_store.dart';
import 'package:caelo/core/tunnel.dart';
import 'package:caelo/main.dart';
import 'package:caelo/ui/settings_screen.dart';
import 'package:caelo/ui/widgets/power_button.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';

const _helsinki = '{"type":"amneziawg","tag":"Helsinki"}';
const _stockholm = '{"type":"amneziawg","tag":"Stockholm"}';
const _frankfurt = '{"type":"amneziawg","tag":"Frankfurt"}';

const _nodes = [
  SubscriptionNode(
    id: 'hel',
    tag: 'Helsinki',
    endpoint: _helsinki,
    position: 0,
    country: 'FI',
  ),
  SubscriptionNode(
    id: 'sto',
    tag: 'Stockholm',
    endpoint: _stockholm,
    position: 1,
    country: 'SE',
  ),
  SubscriptionNode(
    id: 'fra',
    tag: 'Frankfurt',
    endpoint: _frankfurt,
    position: 2,
    country: 'DE',
  ),
];

const _invitation = 'https://sub.example.invalid/s/token';

/// A tunnel that dials whatever configuration is active.
class _DeviceTunnel implements TunnelClient {
  final _changes = StreamController<TunnelStatus>.broadcast();

  /// Every configuration it was asked to dial, in order.
  final dialled = <String?>[];

  /// Endpoints whose handshake never completes.
  final silent = <String>{};

  /// Held open to observe the "disconnecting" state.
  Completer<void>? holdDisconnect;

  @override
  TunnelStatus current = const TunnelStatus.disconnected();

  @override
  Stream<TunnelStatus> get changes => _changes.stream;

  @override
  bool get coversWholeMachine => true;

  void _emit(TunnelStatus status) {
    current = status;
    _changes.add(status);
  }

  @override
  Future<void> connect() async {
    _emit(const TunnelStatus(phase: TunnelPhase.connecting));
    final config = await ConfigStore.read();
    dialled.add(config);
    if (config == null) {
      _emit(const TunnelStatus.disconnected());
      return;
    }
    if (silent.contains(config)) {
      _emit(const TunnelStatus(phase: TunnelPhase.failed));
      return;
    }
    _emit(const TunnelStatus(phase: TunnelPhase.connected));
  }

  @override
  Future<void> disconnect() async {
    _emit(const TunnelStatus(phase: TunnelPhase.disconnecting));
    await holdDisconnect?.future;
    _emit(const TunnelStatus.disconnected());
  }

  @override
  Future<void> reconnectDifferently() async {}

  @override
  Future<void> dispose() => _changes.close();
}

void main() {
  late Directory directory;
  late _DeviceTunnel tunnel;

  /// Probe answers by endpoint: a latency, or absent for "did not answer".
  late Map<String, int> answers;
  late List<String> probed;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('caelo-flow-test-');
    AppStorage.testDirectory = directory;
    ConfigStore.directory = () async => directory;
    SubscriptionStore.forget();
    tunnel = _DeviceTunnel();
    answers = {_helsinki: 40, _stockholm: 30, _frankfurt: 90};
    probed = [];
  });

  tearDown(() async {
    AppStorage.testDirectory = null;
    ConfigStore.directory = AppStorage.directory;
    SubscriptionStore.forget();
    await directory.delete(recursive: true);
  });

  ServerCatalog catalog() => SubscriptionServerCatalog(
    probeConfiguration: (endpoint) async {
      probed.add(endpoint);
      final latency = answers[endpoint];
      if (latency == null) throw StateError('no answer');
      return {'latency_ms': latency};
    },
  );

  final gateway = SubscriptionAccountGateway(
    refreshSubscription: (subscription) async {
      final updated = subscription.copyWith(
        nodes: _nodes,
        lastFetched: DateTime.now(),
        updateInterval: const Duration(hours: 12),
      );
      await SubscriptionStore.save(updated);
      return updated;
    },
  );

  /// Lets real file I/O finish between frames. Widget tests run on a fake
  /// clock, and a file write completes on the real one.
  Future<void> settle(WidgetTester tester, {int rounds = 60}) async {
    for (var i = 0; i < rounds; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> launch(WidgetTester tester, {bool accessGranted = false}) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      CaeloApp(
        localeMode: CaeloLocaleMode.russian,
        accessGranted: accessGranted,
        accountGateway: gateway,
        tunnelClient: tunnel,
        serverCatalog: catalog(),
      ),
    );
    await settle(tester);
  }

  Future<void> onboard(WidgetTester tester) async {
    await tester.enterText(find.byType(CupertinoTextField), _invitation);
    await tester.tap(find.text('Продолжить'));
    await settle(tester);
  }

  Future<void> pressPower(WidgetTester tester) async {
    await tester.tap(find.byType(PowerButton));
    await settle(tester);
  }

  String headerName(WidgetTester tester) => tester
      .widget<Text>(find.byKey(const ValueKey('selected-server-name')))
      .data!;

  Future<void> openServers(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('server-drag-handle')));
    await settle(tester, rounds: 10);
  }

  Finder row(String suffix) => find.byWidgetPredicate(
    (widget) =>
        widget.key is ValueKey<String> &&
        (widget.key! as ValueKey<String>).value.startsWith('server-row-') &&
        (widget.key! as ValueKey<String>).value.endsWith(suffix),
  );

  PowerButton power(WidgetTester tester) =>
      tester.widget<PowerButton>(find.byType(PowerButton));

  testWidgets('paste the link, press the button, connected', (tester) async {
    await launch(tester);
    expect(find.text('Добро пожаловать'), findsOneWidget);

    await onboard(tester);

    // Home, with nothing to choose: automatic is already the choice.
    expect(find.byType(PowerButton), findsOneWidget);
    expect(headerName(tester), 'Автоматически');

    await pressPower(tester);

    expect(power(tester).phase, TunnelPhase.connected);
    // The first server in the subscription's order that answered.
    expect(tunnel.dialled, [_helsinki]);
    expect(headerName(tester), 'Helsinki');
    expect(find.text('Выбран автоматически'), findsOneWidget);
    // Nothing was added to the person's own configurations.
    expect(await tester.runAsync(ConfigStore.list), isEmpty);
  });

  testWidgets('a server that does not answer is skipped', (tester) async {
    answers.remove(_helsinki);
    await launch(tester);
    await onboard(tester);
    await pressPower(tester);

    expect(power(tester).phase, TunnelPhase.connected);
    expect(tunnel.dialled, [_stockholm]);
    expect(headerName(tester), 'Stockholm');
  });

  testWidgets('a server that answers a probe but not the tunnel is left '
      'for the next', (tester) async {
    tunnel.silent.add(_helsinki);
    await launch(tester);
    await onboard(tester);
    await pressPower(tester);

    expect(power(tester).phase, TunnelPhase.connected);
    expect(tunnel.dialled, [_helsinki, _stockholm]);
    expect(headerName(tester), 'Stockholm');
  });

  testWidgets('nothing answers: says so, and the list can still be opened '
      '(#104)', (tester) async {
    answers.clear();
    await launch(tester);
    await onboard(tester);
    await pressPower(tester);

    expect(power(tester).phase, TunnelPhase.failed);
    expect(tunnel.dialled, isEmpty);
    expect(
      find.text(
        'Ни один сервер не ответил. Проверьте интернет и попробуйте ещё раз.',
      ),
      findsOneWidget,
    );

    await openServers(tester);
    expect(find.text('Выберите сервер'), findsOneWidget);
    expect(row(':sto'), findsOneWidget);
  });

  testWidgets('picking a server by hand connects through exactly that one', (
    tester,
  ) async {
    await launch(tester);
    await onboard(tester);

    await openServers(tester);
    await tester.tap(row(':fra'));
    await settle(tester);

    expect(headerName(tester), 'Frankfurt');
    await pressPower(tester);

    expect(power(tester).phase, TunnelPhase.connected);
    expect(tunnel.dialled, [_frankfurt]);
    expect(find.text('Выбран автоматически'), findsNothing);
  });

  testWidgets('the choice survives a restart', (tester) async {
    await launch(tester);
    await onboard(tester);
    await openServers(tester);
    await tester.tap(row(':sto'));
    await settle(tester);

    await tester.pumpWidget(const SizedBox());
    SubscriptionStore.forget();
    await launch(tester, accessGranted: true);

    expect(headerName(tester), 'Stockholm');
  });

  testWidgets('a hand-picked server that is down says so', (tester) async {
    tunnel.silent.add(_frankfurt);
    await launch(tester);
    await onboard(tester);
    await openServers(tester);
    await tester.tap(row(':fra'));
    await settle(tester);
    await pressPower(tester);

    expect(power(tester).phase, TunnelPhase.failed);
    // Did not go elsewhere behind the person's back.
    expect(tunnel.dialled, [_frankfurt]);
  });

  testWidgets('the list cannot be changed while connected', (tester) async {
    await launch(tester);
    await onboard(tester);
    await pressPower(tester);

    await openServers(tester);
    expect(find.text('Выберите сервер'), findsNothing);
  });

  testWidgets('the button does nothing while disconnecting (#11)', (
    tester,
  ) async {
    await launch(tester);
    await onboard(tester);
    await pressPower(tester);

    tunnel.holdDisconnect = Completer<void>();
    await pressPower(tester);
    expect(power(tester).phase, TunnelPhase.disconnecting);
    expect(power(tester).onPressed, isNull);

    await tester.tap(find.byType(PowerButton), warnIfMissed: false);
    await settle(tester, rounds: 5);
    tunnel.holdDisconnect!.complete();
    await settle(tester);

    expect(power(tester).phase, TunnelPhase.disconnected);
    expect(tunnel.dialled, [_helsinki]);
  });

  testWidgets('pressing again while choosing stops the attempt', (
    tester,
  ) async {
    await launch(tester);
    await onboard(tester);

    await tester.tap(find.byType(PowerButton));
    await tester.pump();
    expect(power(tester).phase, TunnelPhase.connecting);
    await tester.tap(find.byType(PowerButton));
    await settle(tester);

    expect(power(tester).phase, TunnelPhase.disconnected);
    expect(tunnel.dialled, isEmpty);
  });

  testWidgets('connect, disconnect, connect again', (tester) async {
    await launch(tester);
    await onboard(tester);

    await pressPower(tester);
    expect(power(tester).phase, TunnelPhase.connected);
    await pressPower(tester);
    expect(power(tester).phase, TunnelPhase.disconnected);
    await pressPower(tester);
    expect(power(tester).phase, TunnelPhase.connected);

    expect(tunnel.dialled, [_helsinki, _helsinki]);
    expect(await tester.runAsync(ConfigStore.list), isEmpty);
  });

  group('forgetting the account', () {
    Future<void> openForget(WidgetTester tester) async {
      await tester.tap(find.bySemanticsLabel('Настройки'));
      await settle(tester, rounds: 10);
      expect(find.byType(SettingsScreen), findsOneWidget);
      await tester.tap(find.text('Отключить аккаунт'));
      await settle(tester, rounds: 10);
    }

    Finder inDialog(String text) => find.descendant(
      of: find.byType(CupertinoAlertDialog),
      matching: find.text(text),
    );

    testWidgets('asks first, and cancelling changes nothing', (tester) async {
      await launch(tester);
      await onboard(tester);
      await openForget(tester);

      expect(find.text('Отключить аккаунт?'), findsOneWidget);
      await tester.tap(inDialog('Отмена'));
      await settle(tester);

      expect(find.byType(SettingsScreen), findsOneWidget);
      expect(await tester.runAsync(SubscriptionStore.all), hasLength(1));
    });

    testWidgets('removes everything, and onboarding again does not '
        'duplicate (#103)', (tester) async {
      await launch(tester);
      await onboard(tester);
      await pressPower(tester);

      await openForget(tester);
      await tester.tap(inDialog('Отключить'));
      await settle(tester);

      expect(find.text('Добро пожаловать'), findsOneWidget);
      expect(tunnel.current.phase, TunnelPhase.disconnected);
      expect(await tester.runAsync(SubscriptionStore.all), isEmpty);
      expect(await tester.runAsync(ConfigStore.read), isNull);
      expect(await tester.runAsync(SettingsStore.accessGranted), isFalse);

      await onboard(tester);
      await openServers(tester);
      expect(row(':hel'), findsOneWidget);
      expect(row(':sto'), findsOneWidget);
      expect(row(':fra'), findsOneWidget);
    });
  });
}
