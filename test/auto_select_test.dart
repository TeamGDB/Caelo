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

  ServerSelectionController build({
    Future<bool> Function()? refresh,
    Future<Subscription?> Function(Subscription, String)? grant,
  }) {
    final controller = ServerSelectionController(
      catalog,
      readSubscription: (id) async => Subscription(id: id, url: 'https://x'),
      grantServer: grant ?? (_, _) async => null,
      readSelected: () async => saved,
      writeSelected: (id) async => saved = id,
      activateConfiguration: (_) async {},
      activateNode: (_, _) async {},
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

  test('picks the first server that answers, in list order', () async {
    catalog = _ScriptedCatalog(
      [_node('a'), _node('b'), _node('c')],
      answers: {'b': 40, 'c': 10},
    );
    servers = build();
    await servers.load();

    final prepared = await servers.prepareConnection({}, never);

    expect(prepared.id, 'b');
    expect(prepared.retryable, isTrue);
    expect(prepared.latencyMs, 40);
    expect(catalog.activated, ['b']);
    expect(servers.active?.id, 'b');
    // Automatic stays the choice; only what it picked changed.
    expect(servers.selected?.automatic, isTrue);
  });

  test('an earlier server still being asked beats a later fast one', () async {
    catalog = _ScriptedCatalog(
      [_node('slow'), _node('fast')],
      answers: {'slow': 300, 'fast': 5},
    );
    catalog.delays['slow'] = const Duration(milliseconds: 50);
    servers = build();
    await servers.load();

    final prepared = await servers.prepareConnection({}, never);
    expect(prepared.id, 'slow');
  });

  test('probes several servers at once, but not all of them', () async {
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
    expect(catalog.maxInFlight, inInclusiveRange(2, 4));
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

  test('a server picked by hand is used without probing anything', () async {
    catalog = _ScriptedCatalog([_node('a'), _node('b')]);
    servers = build();
    await servers.load();
    await servers.select(servers.servers.firstWhere((s) => s.id == 'b'));

    final prepared = await servers.prepareConnection({}, never);

    expect(prepared.id, 'b');
    expect(prepared.retryable, isFalse);
    expect(catalog.probed, isEmpty);
    expect(catalog.activated, ['b']);
  });

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
    test('does not measure while the tunnel is up (#102)', () async {
      catalog = _ScriptedCatalog([_node('a')], answers: {'a': 5});
      servers = ServerSelectionController(
        catalog,
        readSelected: () async => null,
        writeSelected: (_) async {},
        latencyRefreshInterval: null,
      );
      servers.tunnelActive = true;
      await servers.load();
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(catalog.probed, isEmpty);
    });

    test('measures once the tunnel is down again', () async {
      catalog = _ScriptedCatalog([_node('a')], answers: {'a': 5});
      servers = ServerSelectionController(
        catalog,
        readSelected: () async => null,
        writeSelected: (_) async {},
        latencyRefreshInterval: null,
      );
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
      await servers.load();
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(catalog.probed, isNot(contains(ServerOption.automaticId)));
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
}
