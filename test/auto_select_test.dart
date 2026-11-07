import 'package:caelo/core/server_catalog.dart';
import 'package:caelo/core/subscription.dart';
import 'package:caelo/core/tunnel.dart';
import 'package:flutter_test/flutter_test.dart';

/// A catalog whose servers answer, or do not, the way a test says.
class _ScriptedCatalog implements ServerCatalog {
  _ScriptedCatalog(this.list, {Map<String, int?>? answers})
    : answers = answers ?? {};

  List<ServerOption> list;

  /// Latency by server id; a missing or null entry does not answer.
  Map<String, int?> answers;

  /// Delay before a server answers, by id.
  final delays = <String, Duration>{};
  final probed = <String>[];
  final activated = <String>[];
  int inFlight = 0;
  int maxInFlight = 0;

  @override
  Future<List<ServerOption>> load() async => list;

  @override
  Future<int?> measureLatency(ServerOption server) async {
    probed.add(server.id);
    inFlight++;
    if (inFlight > maxInFlight) maxInFlight = inFlight;
    try {
      await Future<void>.delayed(delays[server.id] ?? Duration.zero);
      return answers[server.id];
    } finally {
      inFlight--;
    }
  }

  @override
  Future<void> activate(ServerOption server) async => activated.add(server.id);
}

ServerOption _node(String id, {bool maintenance = false}) => ServerOption(
  id: id,
  name: id,
  description: '',
  flag: '🌐',
  subscriptionId: 'sub',
  nodeId: id,
  available: !maintenance,
);

ServerOption _offer(String id) => ServerOption(
  id: id,
  name: id,
  description: '',
  flag: '🌐',
  subscriptionId: 'sub',
  serverId: id,
);

ServerOption _config(String id) =>
    ServerOption(id: id, name: id, description: '', flag: '📄', configId: id);

void main() {
  late _ScriptedCatalog catalog;
  late ServerSelectionController servers;
  late int refreshes;
  String? saved;
  String? last;
  void Function()? panelChange;
  int Function() provisioned = () => 0;

  ServerSelectionController build({
    Future<bool> Function()? refresh,
    Future<Subscription?> Function(Subscription, String)? grant,
  }) {
    final controller = ServerSelectionController(
      catalog,
      readSubscription: (id) async => Subscription(id: id, url: 'https://x'),
      readLastConnected: () async => last,
      writeLastConnected: (id) async => last = id,
      fastestGrace: const Duration(milliseconds: 30),
      grantServer: grant ?? (_, _) async => null,
      readSelected: () async => saved,
      writeSelected: (id) async => saved = id,
      activateConfiguration: (_) async {},
      activateNode: (_, _) async {},
      backgroundMeasurement: false,
      provisionOffers: () async => provisioned(),
      checkSubscriptions: () async {
        if (panelChange == null) return false;
        panelChange!();
        panelChange = null;
        return true;
      },
      refreshSubscriptions:
          refresh ??
          () async {
            refreshes++;
            return false;
          },
      latencyRefreshInterval: null,
    );
    // Measurement runs on load; the tests are about choosing, so keep it out
    // of the way.
    controller.tunnelActive = true;
    return controller;
  }

  bool never() => false;

  setUp(() {
    saved = null;
    last = null;
    panelChange = null;
    provisioned = () => 0;
    refreshes = 0;
  });

  tearDown(() => servers.dispose());

  test('automatic is offered first and chosen by default', () async {
    catalog = _ScriptedCatalog([_node('a'), _node('b')]);
    servers = build();
    await servers.load();

    expect(servers.servers.first.automatic, isTrue);
    expect(servers.selected?.automatic, isTrue);
    expect(servers.isAutomatic, isTrue);
  });

  test('a remembered server is restored instead', () async {
    saved = 'b';
    catalog = _ScriptedCatalog([_node('a'), _node('b')]);
    servers = build();
    await servers.load();

    expect(servers.selected?.id, 'b');
  });

  test('no servers means no automatic entry either', () async {
    catalog = _ScriptedCatalog([]);
    servers = build();
    await servers.load();

    expect(servers.servers, isEmpty);
  });

  group('the fastest, with the last one first (#112)', () {
    test('takes the fastest of those that answer', () async {
      catalog = _ScriptedCatalog(
        [_node('a'), _node('b'), _node('c')],
        answers: {'b': 40, 'c': 10},
      );
      servers = build();
      await servers.load();

      final prepared = await servers.prepareConnection({}, never);

      expect(prepared.id, 'c');
      expect(prepared.retryable, isTrue);
      expect(prepared.latencyMs, 10);
      expect(catalog.activated, ['c']);
      expect(servers.active?.id, 'c');
      // Automatic stays the choice; only what it picked changed.
      expect(servers.selected?.automatic, isTrue);
    });

    test('a tie goes to the subscription\'s order', () async {
      catalog = _ScriptedCatalog(
        [_node('a'), _node('b')],
        answers: {'a': 20, 'b': 20},
      );
      servers = build();
      await servers.load();

      expect((await servers.prepareConnection({}, never)).id, 'a');
    });

    test('does not wait for a slow server to finish', () async {
      catalog = _ScriptedCatalog(
        [_node('slow'), _node('fast')],
        answers: {'slow': 1, 'fast': 50},
      );
      catalog.delays['slow'] = const Duration(seconds: 2);
      servers = build();
      await servers.load();

      final watch = Stopwatch()..start();
      final prepared = await servers.prepareConnection({}, never);
      expect(prepared.id, 'fast');
      expect(watch.elapsed, lessThan(const Duration(seconds: 1)));
    });

    test('asks every candidate at once, up to eight', () async {
      catalog = _ScriptedCatalog(
        [for (var i = 0; i < 10; i++) _node('n$i')],
        answers: {'n9': 20},
      );
      for (var i = 0; i < 10; i++) {
        catalog.delays['n$i'] = const Duration(milliseconds: 5);
      }
      servers = build();
      await servers.load();

      final prepared = await servers.prepareConnection({}, never);
      expect(prepared.id, 'n9');
      expect(catalog.maxInFlight, 8);
    });

    test('every press compares the servers, even with one remembered '
        '(#123)', () async {
      last = 'b';
      catalog = _ScriptedCatalog(
        [_node('a'), _node('b')],
        answers: {'a': 5, 'b': 80},
      );
      servers = build();
      await servers.load();

      final prepared = await servers.prepareConnection({}, never);
      expect(prepared.id, 'a');
      expect(catalog.probed.toSet(), {'a', 'b'});
    });

    test('the remembered server wins a near tie', () async {
      last = 'b';
      catalog = _ScriptedCatalog(
        [_node('a'), _node('b')],
        answers: {'a': 100, 'b': 110},
      );
      servers = build();
      await servers.load();

      expect((await servers.prepareConnection({}, never)).id, 'b');
    });

    test('when the last one does not come up, the rest are compared', () async {
      last = 'b';
      catalog = _ScriptedCatalog(
        [_node('a'), _node('b'), _node('c')],
        answers: {'a': 30, 'b': 1, 'c': 10},
      );
      servers = build();
      await servers.load();

      // The controller asks again with the failed one in [tried].
      final prepared = await servers.prepareConnection({'b'}, never);
      expect(prepared.id, 'c');
      expect(catalog.probed, isNot(contains('b')));
    });

    test('a measurement in flight is waited for, not doubled', () async {
      catalog = _ScriptedCatalog([_node('a')], answers: {'a': 42});
      catalog.delays['a'] = const Duration(milliseconds: 40);
      servers = ServerSelectionController(
        catalog,
        readSelected: () async => null,
        writeSelected: (_) async {},
        activateConfiguration: (_) async {},
        activateNode: (_, _) async {},
        readLastConnected: () async => null,
        writeLastConnected: (_) async {},
        latencyRefreshInterval: null,
        fastestGrace: const Duration(milliseconds: 10),
      );
      // Measuring starts on load, and is still going when connecting begins.
      await servers.load();
      await Future<void>.delayed(const Duration(milliseconds: 5));

      final prepared = await servers.prepareConnection({}, never);
      expect(prepared.id, 'a');
      expect(catalog.probed, ['a'], reason: 'one probe, shared');
    });

    test(
      'the last one is passed over when another measured clearly faster',
      () async {
        last = 'b';
        catalog = _ScriptedCatalog(
          [_node('a'), _node('b')],
          answers: {'a': 20, 'b': 200},
        );
        servers = build();
        await servers.load();
        servers.servers = [
          for (final s in servers.servers)
            s.id == 'a'
                ? s.withLatency(20)
                : s.id == 'b'
                ? s.withLatency(200)
                : s,
        ];

        final prepared = await servers.prepareConnection({}, never);
        expect(prepared.id, 'a');
      },
    );

    test('remembers the server once connected', () async {
      catalog = _ScriptedCatalog([_node('a')], answers: {'a': 5});
      servers = build();
      await servers.load();
      await servers.prepareConnection({}, never);

      await servers.rememberActive();
      expect(last, 'a');
    });
  });

  test('skips maintenance, offers without keys, and what was tried', () async {
    catalog = _ScriptedCatalog(
      [
        _node('down', maintenance: true),
        _offer('offer'),
        _node('a'),
        _node('b'),
      ],
      answers: {'down': 1, 'offer': 1, 'a': 30, 'b': 30},
    );
    servers = build();
    await servers.load();

    final prepared = await servers.prepareConnection({'a'}, never);

    expect(prepared.id, 'b');
    expect(catalog.probed, isNot(contains('down')));
    expect(catalog.probed, isNot(contains('offer')));
    expect(catalog.probed, isNot(contains('a')));
  });

  test('falls back to the person\'s own configurations', () async {
    catalog = _ScriptedCatalog(
      [_node('a'), _config('mine')],
      answers: {'mine': 55},
    );
    servers = build();
    await servers.load();

    final prepared = await servers.prepareConnection({}, never);
    expect(prepared.id, 'mine');
  });

  test('refreshes subscriptions once when nothing answers', () async {
    catalog = _ScriptedCatalog([_node('a')]);
    servers = build(
      refresh: () async {
        refreshes++;
        // The refresh brought rotated keys, and now the node answers.
        catalog.answers = {'a': 70};
        return false;
      },
    );
    await servers.load();

    final prepared = await servers.prepareConnection({}, never);
    expect(refreshes, 1);
    expect(prepared.id, 'a');
  });

  test('says no server is reachable when refreshing did not help', () async {
    catalog = _ScriptedCatalog([_node('a'), _node('b')]);
    servers = build();
    await servers.load();

    final prepared = await servers.prepareConnection({}, never);
    expect(refreshes, 1);
    expect(prepared.failure, TunnelFailure.noServerReachable);
    expect(catalog.activated, isEmpty);
  });

  test(
    'says the subscription is gone when its server disowns it (#106)',
    () async {
      catalog = _ScriptedCatalog([_node('a')]);
      servers = build(refresh: () async => true);
      await servers.load();

      final prepared = await servers.prepareConnection({}, never);
      expect(prepared.failure, TunnelFailure.subscriptionGone);
    },
  );

  test('a configuration of the person\'s own still wins over a gone '
      'subscription', () async {
    catalog = _ScriptedCatalog([_node('a'), _config('mine')]);
    servers = build(
      refresh: () async {
        catalog.answers = {'mine': 9};
        return true;
      },
    );
    await servers.load();

    final prepared = await servers.prepareConnection({}, never);
    expect(prepared.id, 'mine');
  });

  test('does not refresh again on a retry within one connection', () async {
    catalog = _ScriptedCatalog([_node('a'), _node('b')], answers: {'a': 1});
    servers = build();
    await servers.load();

    final prepared = await servers.prepareConnection({'a'}, never);
    expect(refreshes, 0);
    expect(prepared.failure, TunnelFailure.noServerReachable);
  });

  test('says there are no servers when there is nothing at all', () async {
    catalog = _ScriptedCatalog([]);
    servers = build();
    await servers.load();

    final prepared = await servers.prepareConnection({}, never);
    expect(prepared.failure, TunnelFailure.noServers);
  });

  group('servers offered without keys (#107)', () {
    test('asks for keys on the next one when nothing else answers', () async {
      final asked = <String>[];
      catalog = _ScriptedCatalog([_node('a'), _offer('b'), _offer('c')]);
      servers = build(
        grant: (subscription, serverId) async {
          asked.add(serverId);
          // The server issued keys: the offer is a node now, and answers.
          catalog.list = [
            _node('a'),
            for (final id in ['b', 'c'])
              if (asked.contains(id)) _node(id) else _offer(id),
          ];
          if (serverId == 'b') catalog.answers['b'] = 50;
          return subscription;
        },
      );
      await servers.load();

      final prepared = await servers.prepareConnection({}, never);

      expect(asked, ['b']);
      expect(prepared.id, 'b');
      expect(catalog.activated, ['b']);
      expect(servers.preparing, isNull);
    });

    test('moves to the next offer when one is refused', () async {
      final asked = <String>[];
      catalog = _ScriptedCatalog([_offer('b'), _offer('c')]);
      servers = build(
        grant: (subscription, serverId) async {
          asked.add(serverId);
          if (serverId == 'b') return null;
          catalog.list = [_offer('b'), _node('c')];
          catalog.answers['c'] = 20;
          return subscription;
        },
      );
      await servers.load();

      final prepared = await servers.prepareConnection({}, never);
      expect(asked, ['b', 'c']);
      expect(prepared.id, 'c');
    });

    test('asks for at most three in one connection', () async {
      final asked = <String>[];
      catalog = _ScriptedCatalog([for (var i = 0; i < 6; i++) _offer('o$i')]);
      servers = build(
        grant: (subscription, serverId) async {
          asked.add(serverId);
          return null;
        },
      );
      await servers.load();

      final prepared = await servers.prepareConnection({}, never);
      expect(
        asked,
        hasLength(ServerSelectionController.maxProvisionPerConnection),
      );
      expect(prepared.failure, isNotNull);
    });

    test('a gone subscription is not asked for anything', () async {
      var asked = 0;
      catalog = _ScriptedCatalog([_node('a'), _offer('b')]);
      servers = build(
        refresh: () async => true,
        grant: (_, _) async {
          asked++;
          return null;
        },
      );
      await servers.load();

      final prepared = await servers.prepareConnection({}, never);
      expect(asked, 0);
      expect(prepared.failure, TunnelFailure.subscriptionGone);
    });

    test('nodes that already have keys are tried first', () async {
      var asked = 0;
      catalog = _ScriptedCatalog([_offer('b'), _node('a')], answers: {'a': 5});
      servers = build(
        grant: (_, _) async {
          asked++;
          return null;
        },
      );
      await servers.load();

      final prepared = await servers.prepareConnection({}, never);
      expect(asked, 0);
      expect(prepared.id, 'a');
    });
  });

  test(
    'a server picked by hand is checked first, and only it (#123)',
    () async {
      catalog = _ScriptedCatalog([_node('a'), _node('b')], answers: {'b': 60});
      servers = build();
      await servers.load();
      await servers.select(servers.servers.firstWhere((s) => s.id == 'b'));

      final prepared = await servers.prepareConnection({}, never);

      expect(prepared.id, 'b');
      expect(prepared.retryable, isFalse);
      expect(prepared.latencyMs, 60);
      expect(catalog.probed, ['b']);
      expect(catalog.activated, ['b']);
    },
  );

  test(
    'a server picked by hand that does not answer is not dialled (#123)',
    () async {
      catalog = _ScriptedCatalog([_node('a'), _node('b')], answers: {'a': 5});
      servers = build();
      await servers.load();
      await servers.select(servers.servers.firstWhere((s) => s.id == 'b'));

      final prepared = await servers.prepareConnection({}, never);

      expect(prepared.failure, TunnelFailure.chosenServerUnreachable);
      expect(catalog.activated, isEmpty, reason: 'no silent switch either');
    },
  );

  test('a hand-picked server that failed is not tried again', () async {
    catalog = _ScriptedCatalog([_node('a')]);
    servers = build();
    await servers.load();
    await servers.select(servers.servers.firstWhere((s) => s.id == 'a'));

    final prepared = await servers.prepareConnection({'a'}, never);
    expect(prepared.failure, TunnelFailure.chosenServerUnreachable);
  });

  test('stops when the person cancels', () async {
    catalog = _ScriptedCatalog([_node('a')], answers: {'a': 5});
    catalog.delays['a'] = const Duration(milliseconds: 20);
    servers = build();
    await servers.load();

    var cancelled = false;
    final pending = servers.prepareConnection({}, () => cancelled);
    cancelled = true;
    final prepared = await pending;

    expect(prepared.id, isNull);
    expect(prepared.failure, isNull);
    expect(catalog.activated, isEmpty);
  });

  group('measuring', () {
    test(
      'does not measure the server in use while the tunnel is up (#102)',
      () async {
        catalog = _ScriptedCatalog([_node('a')], answers: {'a': 5});
        servers = ServerSelectionController(
          catalog,
          readSelected: () async => null,
          writeSelected: (_) async {},
          activateConfiguration: (_) async {},
          activateNode: (_, _) async {},
          readLastConnected: () async => null,
          writeLastConnected: (_) async {},
          checkSubscriptions: () async => false,
          backgroundMeasurement: false,
          latencyRefreshInterval: null,
          fastestGrace: const Duration(milliseconds: 10),
        );
        await servers.load();
        await servers.prepareConnection({}, () => false);
        catalog.probed.clear();
        servers.tunnelActive = true;
        await servers.load();
        await Future<void>.delayed(const Duration(milliseconds: 10));

        expect(catalog.probed, isEmpty);
      },
    );

    test('measures once the tunnel is down again', () async {
      catalog = _ScriptedCatalog([_node('a')], answers: {'a': 5});
      servers = ServerSelectionController(
        catalog,
        readSelected: () async => null,
        writeSelected: (_) async {},
        latencyRefreshInterval: null,
      );
      // Measured because somebody opened the list (#156).
      servers.listOpen = true;
      await servers.load();
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(catalog.probed, ['a']);
      expect(servers.servers.last.latencyMs, 5);
    });

    test('marks a server that did not answer, so the list has a verdict '
        'for every one', () async {
      catalog = _ScriptedCatalog([_node('a'), _node('b')], answers: {'a': 5});
      servers = ServerSelectionController(
        catalog,
        readSelected: () async => null,
        writeSelected: (_) async {},
        latencyRefreshInterval: null,
      );
      // Measured because somebody opened the list (#156).
      servers.listOpen = true;
      await servers.load();
      await Future<void>.delayed(const Duration(milliseconds: 10));

      final a = servers.servers.firstWhere((s) => s.id == 'a');
      final b = servers.servers.firstWhere((s) => s.id == 'b');
      expect(a.latencyMs, 5);
      expect(b.unreachable, isTrue);
      expect(b.measured, isTrue);
    });

    test('measurements survive a reload', () async {
      catalog = _ScriptedCatalog([_node('a')], answers: {'a': 5});
      servers = ServerSelectionController(
        catalog,
        readSelected: () async => null,
        writeSelected: (_) async {},
        latencyRefreshInterval: null,
      );
      // Measured because somebody opened the list (#156).
      servers.listOpen = true;
      await servers.load();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      servers.tunnelActive = true;
      await servers.load();

      expect(servers.servers.last.latencyMs, 5);
    });

    test('never measures the automatic entry', () async {
      catalog = _ScriptedCatalog([_node('a')], answers: {'a': 5});
      servers = ServerSelectionController(
        catalog,
        readSelected: () async => null,
        writeSelected: (_) async {},
        latencyRefreshInterval: null,
      );
      // Measured because somebody opened the list (#156).
      servers.listOpen = true;
      await servers.load();
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(catalog.probed, isNot(contains(ServerOption.automaticId)));
    });
  });

  test('connecting first catches up with the panel, so a removed server '
      'is neither tried nor shown (#124)', () async {
    catalog = _ScriptedCatalog(
      [_node('a'), _node('b')],
      answers: {'a': 5, 'b': 50},
    );
    servers = build();
    await servers.load();

    // Removed in the panel since the list was last read.
    panelChange = () => catalog.list = [_node('b')];
    final prepared = await servers.prepareConnection({}, never);

    expect(prepared.id, 'b');
    expect(catalog.probed, isNot(contains('a')));
    expect(servers.servers.map((s) => s.id), [ServerOption.automaticId, 'b']);
  });

  test('a hand-picked server removed in the panel is reported, not '
      'replaced; the next press connects automatically (#128)', () async {
    catalog = _ScriptedCatalog(
      [_node('a'), _node('b')],
      answers: {'a': 5, 'b': 50},
    );
    servers = build();
    await servers.load();
    await servers.select(servers.servers.firstWhere((s) => s.id == 'b'));
    catalog.activated.clear();

    panelChange = () => catalog.list = [_node('a')];
    final first = await servers.prepareConnection({}, never);

    expect(first.failure, TunnelFailure.chosenServerRemoved);
    expect(servers.removedChoice, 'b');
    expect(catalog.activated, isEmpty);
    expect(servers.selected?.automatic, isTrue);
    expect(saved, ServerOption.automaticId);

    final second = await servers.prepareConnection({}, never);
    expect(second.id, 'a');
    expect(servers.removedChoice, isNull);
  });

  test('while connected, servers without a figure are measured, the one in '
      'use is not (#128)', () async {
    catalog = _ScriptedCatalog(
      [_node('a'), _node('b')],
      answers: {'a': 5, 'b': 50},
    );
    servers = ServerSelectionController(
      catalog,
      readSelected: () async => null,
      writeSelected: (_) async {},
      activateConfiguration: (_) async {},
      activateNode: (_, _) async {},
      readLastConnected: () async => null,
      writeLastConnected: (_) async {},
      checkSubscriptions: () async => false,
      latencyRefreshInterval: null,
      fastestGrace: const Duration(milliseconds: 10),
    );
    await servers.load();
    await servers.prepareConnection({}, never);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    catalog.probed.clear();

    servers.tunnelActive = false;
    servers.tunnelActive = true;
    catalog.list = [_node('a'), _node('b'), _node('c')];
    catalog.answers['c'] = 30;
    await servers.load();
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(catalog.probed, contains('c'));
    expect(catalog.probed, isNot(contains('a')));
  });

  test('new servers from the panel get their keys asked for at once, and '
      'say so meanwhile (#131)', () async {
    catalog = _ScriptedCatalog([_node('a')], answers: {'a': 5});
    servers = build();
    await servers.load();

    var asked = 0;
    provisioned = () {
      asked++;
      expect(servers.provisioning, isTrue);
      catalog.list = [_node('a'), _node('b')];
      return 1;
    };
    panelChange = () => catalog.list = [_node('a'), _offer('b')];
    await servers.syncWithSubscriptions();
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(asked, 1);
    expect(servers.provisioning, isFalse);
    expect(servers.servers.firstWhere((s) => s.id == 'b').connectable, isTrue);
  });

  test('a reload while measuring does not probe a server twice at once '
      '(#146)', () async {
    catalog = _ScriptedCatalog([_node('a')], answers: {'a': 30});
    catalog.delays['a'] = const Duration(milliseconds: 40);
    servers = ServerSelectionController(
      catalog,
      readSelected: () async => null,
      writeSelected: (_) async {},
      activateConfiguration: (_) async {},
      activateNode: (_, _) async {},
      readLastConnected: () async => null,
      writeLastConnected: (_) async {},
      checkSubscriptions: () async => false,
      provisionOffers: () async => 0,
      latencyRefreshInterval: null,
      fastestGrace: const Duration(milliseconds: 10),
    );
    await servers.load();
    await Future<void>.delayed(const Duration(milliseconds: 5));
    // The list reloads (a refresh, keys arriving) while the first
    // measurement of 'a' is still out, and somebody presses connect.
    await servers.load();
    final prepared = await servers.prepareConnection({}, never);
    await Future<void>.delayed(const Duration(milliseconds: 60));

    expect(prepared.id, 'a');
    expect(catalog.maxInFlight, 1, reason: 'one key, one probe at a time');
  });

  group('moving to a faster server while connected (#132)', () {
    ServerSelectionController measuring() => ServerSelectionController(
      catalog,
      readSelected: () async => saved,
      writeSelected: (id) async => saved = id,
      activateConfiguration: (_) async {},
      activateNode: (_, _) async {},
      readLastConnected: () async => null,
      writeLastConnected: (_) async {},
      checkSubscriptions: () async => false,
      provisionOffers: () async => 0,
      latencyRefreshInterval: null,
      fastestGrace: const Duration(milliseconds: 10),
    );

    Future<void> connectThenRecover(String recovering, int latency) async {
      await servers.load();
      await servers.prepareConnection({}, never);
      servers.tunnelActive = true;
      catalog.answers[recovering] = latency;
      await servers.load();
      await Future<void>.delayed(const Duration(milliseconds: 30));
    }

    test(
      'a server that answers later and is clearly faster is moved to',
      () async {
        catalog = _ScriptedCatalog(
          [_node('kazy'), _node('eintopf')],
          answers: {'kazy': 242},
        );
        servers = measuring();
        final moved = <String>[];
        servers.onFasterAvailable = (server) => moved.add(server.id);

        // 205 against 242 is 15% faster: not enough. 190 is over 20%.
        await connectThenRecover('eintopf', 190);
        expect(servers.active?.id, 'kazy');
        expect(moved, ['eintopf']);
      },
    );

    test('a little faster is not worth a reconnect', () async {
      catalog = _ScriptedCatalog(
        [_node('kazy'), _node('eintopf')],
        answers: {'kazy': 242},
      );
      servers = measuring();
      final moved = <String>[];
      servers.onFasterAvailable = (server) => moved.add(server.id);

      // 10% faster: below the 20% threshold.
      await connectThenRecover('eintopf', 220);
      expect(moved, isEmpty);
    });

    test('never with a server picked by hand', () async {
      catalog = _ScriptedCatalog(
        [_node('kazy'), _node('eintopf')],
        answers: {'kazy': 242},
      );
      servers = measuring();
      final moved = <String>[];
      servers.onFasterAvailable = (server) => moved.add(server.id);
      await servers.load();
      await servers.select(servers.servers.firstWhere((s) => s.id == 'kazy'));

      await connectThenRecover('eintopf', 100);
      expect(moved, isEmpty);
    });
  });

  group('a server removed from the subscription (#111)', () {
    test('says so when it was the one in use', () async {
      catalog = _ScriptedCatalog([_node('a'), _node('b')], answers: {'a': 5});
      servers = build();
      final removed = <String>[];
      servers.onActiveRemoved = (server) => removed.add(server.id);
      await servers.load();
      await servers.prepareConnection({}, never);

      catalog.list = [_node('b')];
      await servers.load();

      expect(removed, ['a']);
      expect(servers.active, isNull);
      expect(servers.servers.map((s) => s.id), [ServerOption.automaticId, 'b']);
    });

    test('says nothing when another server was removed', () async {
      catalog = _ScriptedCatalog([_node('a'), _node('b')], answers: {'a': 5});
      servers = build();
      final removed = <String>[];
      servers.onActiveRemoved = (server) => removed.add(server.id);
      await servers.load();
      await servers.prepareConnection({}, never);

      catalog.list = [_node('a')];
      await servers.load();

      expect(removed, isEmpty);
      expect(servers.active?.id, 'a');
    });

    test('a removed server picked by hand falls back to automatic', () async {
      catalog = _ScriptedCatalog([_node('a'), _node('b')]);
      servers = build();
      await servers.load();
      await servers.select(servers.servers.firstWhere((s) => s.id == 'b'));

      catalog.list = [_node('a')];
      await servers.load();

      expect(servers.selected?.automatic, isTrue);
    });
  });

  test('clear forgets everything held in memory', () async {
    catalog = _ScriptedCatalog([_node('a')], answers: {'a': 5});
    servers = build();
    await servers.load();
    await servers.prepareConnection({}, never);

    servers.clear();
    expect(servers.servers, isEmpty);
    expect(servers.selected, isNull);
    expect(servers.active, isNull);
  });

  group('when the list is measured (#156)', () {
    ServerSelectionController measuring({Duration? interval}) =>
        ServerSelectionController(
          catalog,
          readSelected: () async => saved,
          writeSelected: (id) async => saved = id,
          activateConfiguration: (_) async {},
          activateNode: (_, _) async {},
          readLastConnected: () async => null,
          writeLastConnected: (_) async {},
          checkSubscriptions: () async => false,
          provisionOffers: () async => 0,
          latencyRefreshInterval: interval,
          fastestGrace: const Duration(milliseconds: 10),
        );

    Future<void> settle() =>
        Future<void>.delayed(const Duration(milliseconds: 20));

    setUp(() => saved = null);

    test('a list nobody opened is not measured while disconnected', () async {
      catalog = _ScriptedCatalog(
        [_node('a'), _node('b')],
        answers: {'a': 5, 'b': 9},
      );
      servers = measuring();
      await servers.load();
      await settle();
      servers.tunnelActive = false;
      await servers.load();
      await settle();

      expect(catalog.probed, isEmpty);
    });

    test('opening the list measures every server in it', () async {
      catalog = _ScriptedCatalog(
        [_node('a'), _node('b')],
        answers: {'a': 5, 'b': 9},
      );
      servers = measuring();
      await servers.load();
      servers.listOpen = true;
      await settle();

      expect(catalog.probed, unorderedEquals(['a', 'b']));
      expect(servers.servers.firstWhere((s) => s.id == 'a').latencyMs, 5);
      expect(servers.servers.firstWhere((s) => s.id == 'b').latencyMs, 9);
    });

    test('opened again a moment later, only a server that did not answer is '
        'asked again', () async {
      catalog = _ScriptedCatalog([_node('a'), _node('b')], answers: {'a': 5});
      servers = measuring();
      await servers.load();
      servers.listOpen = true;
      await settle();
      servers.listOpen = false;
      catalog.probed.clear();

      servers.listOpen = true;
      await settle();

      expect(catalog.probed, ['b']);
    });

    test('while it stays open, it is measured again every interval', () async {
      catalog = _ScriptedCatalog([_node('a')], answers: {'a': 5});
      servers = measuring(interval: const Duration(milliseconds: 15));
      await servers.load();
      servers.listOpen = true;
      await Future<void>.delayed(const Duration(milliseconds: 80));

      expect(catalog.probed.length, greaterThanOrEqualTo(3));
      expect(catalog.maxInFlight, 1);
    });

    test('closing it stops the measuring', () async {
      catalog = _ScriptedCatalog([_node('a')], answers: {'a': 5});
      servers = measuring(interval: const Duration(milliseconds: 10));
      await servers.load();
      servers.listOpen = true;
      await settle();
      servers.listOpen = false;
      catalog.probed.clear();
      await Future<void>.delayed(const Duration(milliseconds: 60));

      expect(catalog.probed, isEmpty);
    });

    test('connected automatically, the others are measured in the '
        'background, and never the one in use (#132, #102)', () async {
      catalog = _ScriptedCatalog(
        [_node('a'), _node('b')],
        answers: {'a': 5, 'b': 50},
      );
      servers = measuring();
      await servers.load();
      final prepared = await servers.prepareConnection({}, never);
      expect(prepared.id, 'a');
      servers.tunnelActive = true;
      catalog.probed.clear();
      catalog.answers['c'] = 30;
      catalog.list = [_node('a'), _node('b'), _node('c')];
      await servers.load();
      await settle();

      expect(catalog.probed, contains('c'));
      expect(catalog.probed, isNot(contains('a')));
    });

    test('connected through a server picked by hand, nothing is measured in '
        'the background', () async {
      catalog = _ScriptedCatalog(
        [_node('a'), _node('b')],
        answers: {'a': 5, 'b': 50},
      );
      servers = measuring();
      await servers.load();
      await servers.select(servers.servers.firstWhere((s) => s.id == 'b'));
      await servers.prepareConnection({}, never);
      servers.tunnelActive = true;
      catalog.probed.clear();
      catalog.answers['c'] = 30;
      catalog.list = [_node('a'), _node('b'), _node('c')];
      await servers.load();
      await settle();

      expect(catalog.probed, isEmpty);
    });

    test('disconnected again, the background measuring stops', () async {
      catalog = _ScriptedCatalog([_node('a'), _node('b')], answers: {'a': 5});
      servers = measuring();
      await servers.load();
      await servers.prepareConnection({}, never);
      servers.tunnelActive = true;
      servers.tunnelActive = false;
      catalog.probed.clear();
      catalog.answers['c'] = 30;
      catalog.list = [_node('a'), _node('b'), _node('c')];
      await servers.load();
      await settle();

      expect(catalog.probed, isEmpty);
    });

    test('opening the list while a server is being measured for connecting '
        'joins that measurement (#146)', () async {
      catalog = _ScriptedCatalog([_node('a')], answers: {'a': 30});
      catalog.delays['a'] = const Duration(milliseconds: 40);
      servers = measuring();
      await servers.load();
      final connecting = servers.prepareConnection({}, never);
      await Future<void>.delayed(const Duration(milliseconds: 5));
      servers.listOpen = true;
      await connecting;
      await Future<void>.delayed(const Duration(milliseconds: 60));

      expect(catalog.maxInFlight, 1, reason: 'one key, one probe at a time');
    });
  });
}
