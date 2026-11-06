import 'dart:async';

import 'package:flutter/widgets.dart';

import 'config_store.dart';
import 'diagnostics.dart';
import 'tunnel.dart';
import 'tunnel_controller.dart';
import 'ffi/core_library.dart';
import 'node_chooser.dart';
import 'settings_store.dart';
import 'subscription.dart';
import 'subscription_fetcher.dart';
import 'subscription_store.dart';

/// Why a listed server cannot be used (#126).
enum UnavailableReason {
  /// The subscription marked it as under maintenance.
  maintenance,

  /// The subscription offers it and would not issue keys for it.
  notIssued,
}

@immutable
class ServerOption {
  const ServerOption({
    required this.id,
    required this.name,
    required this.description,
    required this.flag,
    this.latencyMs,
    this.configId,
    this.subscriptionId,
    this.nodeId,
    this.serverId,
    this.available = true,
    this.automatic = false,
    this.unreachable = false,
    this.reason,
  });

  /// The entry that stands for "pick one that works". Not a server: it has no
  /// configuration, and its name and description are the interface's to say.
  const ServerOption.automatic()
    : id = automaticId,
      name = '',
      description = '',
      flag = '⚡️',
      latencyMs = null,
      configId = null,
      subscriptionId = null,
      nodeId = null,
      serverId = null,
      available = true,
      automatic = true,
      unreachable = false,
      reason = null;

  static const automaticId = 'auto';

  final String id;
  final String name;
  final String description;
  final String flag;
  final int? latencyMs;
  final String? configId;
  final String? subscriptionId;
  final String? nodeId;

  /// Set when the subscription offers this server but has no keys for it yet.
  /// Choosing it asks for them; until then there is nothing to connect with and
  /// nothing to measure.
  final String? serverId;

  final bool available;

  /// Whether this is the automatic entry rather than a server.
  final bool automatic;

  /// Measured, and nothing came back. A result, as much as a latency is.
  final bool unreachable;

  /// Set when [available] is false, to say why in the list.
  final UnavailableReason? reason;

  /// Whether the last measurement reached a verdict either way.
  bool get measured => latencyMs != null || unreachable;

  /// Whether this can be dialled as it stands.
  bool get connectable =>
      !automatic &&
      available &&
      !needsKeys &&
      (configId != null || nodeId != null);

  /// Whether picking this costs a round trip to the subscription.
  bool get needsKeys => nodeId == null && serverId != null;

  ServerOption withLatency(int latencyMs) => _measured(latencyMs, false);

  ServerOption withUnreachable() => _measured(null, true);

  ServerOption _measured(int? latencyMs, bool unreachable) => ServerOption(
    id: id,
    name: name,
    description: description,
    flag: flag,
    latencyMs: latencyMs,
    configId: configId,
    subscriptionId: subscriptionId,
    nodeId: nodeId,
    serverId: serverId,
    available: available,
    automatic: automatic,
    unreachable: unreachable,
    reason: reason,
  );
}

/// The server list Home consumes, independent of where its nodes are stored.
abstract interface class ServerCatalog {
  Future<List<ServerOption>> load();

  /// A latency through the server, or null if it carried nothing.
  Future<int?> measureLatency(ServerOption server);

  /// Makes [server] the configuration the tunnel will dial, without pinning
  /// it and without adding anything to the person's own configurations.
  Future<void> activate(ServerOption server);
}

class SubscriptionServerCatalog implements ServerCatalog {
  SubscriptionServerCatalog({
    Future<List<Subscription>> Function()? loadSubscriptions,
    Future<List<StoredConfig>> Function()? loadConfigurations,
    Future<Map<String, dynamic>> Function(String)? probeConfiguration,
  }) : _loadSubscriptions = loadSubscriptions ?? SubscriptionStore.all,
       _loadConfigurations = loadConfigurations ?? ConfigStore.list,
       _probeConfiguration = probeConfiguration ?? _probe;

  final Future<List<Subscription>> Function() _loadSubscriptions;
  final Future<List<StoredConfig>> Function() _loadConfigurations;
  final Future<Map<String, dynamic>> Function(String) _probeConfiguration;

  /// Every configuration a row stands for, by row id. Usually one; a
  /// backend that issued a server twice gives two, and one of them may have
  /// no peer behind it (#129).
  final Map<String, List<String>> _endpoints = {};

  /// The configuration of a row that last carried traffic.
  final Map<String, String> _working = {};

  @override
  Future<List<ServerOption>> load() async {
    final configs = await _loadConfigurations();
    final subscriptions = await _loadSubscriptions();
    // One row per server (#127), standing for every configuration the
    // server issued to this device: whichever of them answers is the one
    // used (#129).
    _endpoints.clear();
    final rowOf = <String, String>{};
    final seen = <String>{};
    bool firstOf(Subscription subscription, SubscriptionNode node) {
      final server = '${subscription.id}|${node.tag.trim()}|${node.country}';
      final row = rowOf.putIfAbsent(
        server,
        () => 'node:${subscription.id}:${node.id}',
      );
      _endpoints.putIfAbsent(row, () => []).add(node.endpoint);
      return seen.add(server);
    }

    for (final subscription in subscriptions) {
      for (final node in subscription.nodes) {
        firstOf(subscription, node);
      }
    }
    seen.clear();
    _working.removeWhere(
      (row, endpoint) => !(_endpoints[row]?.contains(endpoint) ?? false),
    );
    return [
      for (final subscription in subscriptions)
        for (final node in subscription.nodes)
          if (firstOf(subscription, node))
            ServerOption(
              id: 'node:${subscription.id}:${node.id}',
              name: node.tag.trim().isEmpty
                  ? 'Server ${node.position + 1}'
                  : node.tag.trim(),
              description: node.description,
              flag: node.flag.isEmpty ? '🌐' : node.flag,
              subscriptionId: subscription.id,
              nodeId: node.id,
              available: !node.maintenance,
              reason: node.maintenance ? UnavailableReason.maintenance : null,
            ),
      // Серверы, которые подписка может выдать, но ещё не выдала. Ключей у них
      // нет, поэтому и узла нет: он появится, когда его выберут.
      for (final subscription in subscriptions)
        for (final server in subscription.available)
          if (!server.ready)
            // One the subscription would not issue is still shown, dimmed and
            // explained, rather than vanishing from a list somebody can
            // compare with the panel (#126).
            if (SubscriptionFetcher.isRefused(
              '${subscription.id}:${server.id}',
            ))
              ServerOption(
                id: 'offer:${subscription.id}:${server.id}',
                name: server.name,
                description: server.description,
                flag: server.flag.isEmpty ? '🌐' : server.flag,
                subscriptionId: subscription.id,
                serverId: server.id,
                available: false,
                reason: UnavailableReason.notIssued,
              )
            else
              ServerOption(
                id: 'offer:${subscription.id}:${server.id}',
                name: server.name,
                description: server.description,
                flag: server.flag.isEmpty ? '🌐' : server.flag,
                subscriptionId: subscription.id,
                serverId: server.id,
              ),
      for (final config in configs)
        ServerOption(
          id: 'user-${config.id}',
          name: config.name,
          description: config.description,
          flag: config.emoji,
          configId: config.id,
        ),
    ];
  }

  @override
  Future<int?> measureLatency(ServerOption server) async {
    if (!server.available) return null;
    final configId = server.configId;
    if (configId != null) {
      final endpoint = await ConfigStore.readById(configId);
      if (endpoint == null || endpoint.trim().isEmpty) return null;
      return _latencyOf(endpoint);
    }
    // The one that worked last first, then the rest in the order served.
    final all = _endpoints[server.id] ?? const <String>[];
    final known = _working[server.id];
    for (final endpoint in [?known, ...all.where((e) => e != known)]) {
      if (endpoint.trim().isEmpty) continue;
      final latency = await _latencyOf(endpoint);
      if (latency != null) {
        _working[server.id] = endpoint;
        return latency;
      }
    }
    return null;
  }

  Future<int?> _latencyOf(String endpoint) async {
    try {
      final result = await _probeConfiguration(endpoint);
      return (result['latency_ms'] as num?)?.round();
    } on Object {
      return null;
    }
  }

  @override
  Future<void> activate(ServerOption server) async {
    if (server.configId case final id?) {
      await ConfigStore.select(id);
      return;
    }
    final endpoint = _working[server.id] ?? _endpoints[server.id]?.firstOrNull;
    if (endpoint == null) {
      throw StateError('the server has no configuration to activate');
    }
    await ConfigStore.activateSubscriptionNode(endpoint);
  }

  static Future<Map<String, dynamic>> _probe(String configuration) =>
      CoreLibrary.measureLatency(
        configuration,
        url: NodeChooser.probeUrl,
        timeout: NodeChooser.perNode,
      );
}

class ServerSelectionController extends ChangeNotifier {
  ServerSelectionController(
    this.catalog, {
    this.readSelected = SettingsStore.selectedServerId,
    this.writeSelected = SettingsStore.setSelectedServerId,
    this.activateConfiguration = ConfigStore.select,
    this.grantServer = SubscriptionFetcher.enable,
    this.readSubscription = SubscriptionStore.byId,
    this.activateNode = _activateNode,
    this.refreshSubscriptions = _refreshSubscriptions,
    this.checkSubscriptions = _checkSubscriptions,
    this.provisionOffers = SubscriptionFetcher.enableAll,
    this.latencyRefreshInterval = const Duration(minutes: 5),
    this.probeConcurrency = 8,
    this.backgroundMeasurement = true,
    this.fastestGrace = const Duration(milliseconds: 1500),
    this.readLastConnected = SettingsStore.lastConnectedServerId,
    this.writeLastConnected = SettingsStore.setLastConnectedServerId,
  });

  final ServerCatalog catalog;
  final Future<String?> Function() readSelected;
  final Future<void> Function(String) writeSelected;
  final Future<void> Function(String) activateConfiguration;

  /// Asks a subscription for keys on one of the servers it offers.
  final Future<Subscription?> Function(Subscription, String) grantServer;

  /// Reads a stored subscription. A seam so the picker can be driven without
  /// storage, which is what a test has instead of a filesystem.
  final Future<Subscription?> Function(String) readSubscription;
  final Future<void> Function(String, String) activateNode;

  /// Fetches every subscription again, regardless of schedule. Used once per
  /// connection, when nothing answered: the likeliest cause after "no
  /// network" is keys that were rotated on the server since the last fetch.
  ///
  /// Answers whether every subscription was refused by its server as unknown.
  final Future<bool> Function() refreshSubscriptions;

  /// Asks each subscription whether its list changed (a few hundred bytes)
  /// and fetches the ones that did. Answers whether anything changed.
  final Future<bool> Function() checkSubscriptions;

  /// Brings the list up to date with the subscription, cheaply. Run every
  /// minute while the app is open and at the start of every connect (#124).
  Future<void> syncWithSubscriptions() async {
    try {
      if (await checkSubscriptions()) {
        await load();
        // New servers come without keys. Ask now rather than at the next
        // tick, so they are usable by the time somebody looks (#131).
        if (servers.any((server) => server.needsKeys && server.available)) {
          unawaited(provisionAll());
        }
      }
    } on Object catch (error) {
      Diagnostics.record('checking the subscription failed', error: error);
    }
  }

  /// Asks for keys on every offered server without them, one request per
  /// server at a time. Answers how many were issued.
  final Future<int> Function() provisionOffers;

  /// Whether a background pass for keys is running. Rows still waiting for
  /// theirs say so instead of looking ready (#131).
  bool provisioning = false;

  Future<void> provisionAll() async {
    if (provisioning) return;
    if (!servers.any((server) => server.needsKeys && server.available)) {
      return;
    }
    provisioning = true;
    notifyListeners();
    final refusedBefore = SubscriptionFetcher.refused.length;
    var granted = 0;
    try {
      granted = await provisionOffers();
    } on Object catch (error) {
      Diagnostics.record('asking for keys failed', error: error);
    } finally {
      provisioning = false;
    }
    // New keys add servers; a refusal dims one (#126).
    if (granted > 0 || SubscriptionFetcher.refused.length != refusedBefore) {
      await load();
    } else {
      notifyListeners();
    }
  }

  /// How long to wait between re-measuring the list. Long: each measurement is
  /// a real handshake with every server, which costs battery and tells each of
  /// them the app is open.
  final Duration? latencyRefreshInterval;

  /// How many servers are probed at once when choosing automatically.
  final int probeConcurrency;

  /// Whether the list measures itself in the background. Off in tests that
  /// count probes made by connecting.
  final bool backgroundMeasurement;

  /// How long the others get once the first server has answered.
  final Duration fastestGrace;

  final Future<String?> Function() readLastConnected;
  final Future<void> Function(String) writeLastConnected;

  /// The automatic entry first, then every server.
  List<ServerOption> servers = const [];

  /// What the person chose: a server, or the automatic entry.
  ServerOption? selected;

  /// The server the last connection was actually made through. Differs from
  /// [selected] when that is the automatic entry.
  ServerOption? active;

  /// The server being prepared, if one is.
  ///
  /// Asking a subscription for keys takes seconds -- it provisions on a real
  /// server over SSH. Without somewhere to say so, the list went on showing the
  /// previous choice for all of it, and the obvious thing to do with a list
  /// that has not reacted is to tap something else, which connected through
  /// whatever was tapped second.
  ServerOption? preparing;

  /// Whether a choice is waiting on the subscription.
  bool get isPreparing => preparing != null;

  /// Called when a reload no longer has the server the last connection went
  /// through: the subscription removed it (#111). The tunnel is still on it,
  /// and the peer is about to disappear from under it.
  void Function(ServerOption removed)? onActiveRemoved;

  /// The name of a hand-picked server that the subscription removed, for the
  /// failure note (#128).
  String? removedChoice;

  /// Whether the automatic entry is the choice.
  bool get isAutomatic => selected?.automatic ?? true;

  int _loadGeneration = 0;

  /// Measurements in flight, by server id, so a connection can wait for one
  /// instead of probing the same server at the same moment.
  final _measuring = <String, Future<int?>>{};
  int _measureGeneration = 0;
  Timer? _latencyRefreshTimer;
  bool _tunnelActive = false;

  /// Told by the app whenever the tunnel goes up or down.
  ///
  /// Measuring while connected is not only wasted: probing the connected
  /// node is a second device with the same key, and the server hands the
  /// session to whichever handshook last — the live tunnel goes deaf until it
  /// handshakes again (#102).
  set tunnelActive(bool active) {
    if (active == _tunnelActive) return;
    _tunnelActive = active;
    _measureGeneration++;
    _latencyRefreshTimer?.cancel();
    _scheduleMeasurement(const Duration(seconds: 2));
  }

  bool get tunnelActive => _tunnelActive;

  Future<void> load() async {
    final generation = ++_loadGeneration;
    final loaded = await catalog.load();
    final savedId = await readSelected();
    if (generation != _loadGeneration) return;
    // What was measured survives a reload: the list is rebuilt from storage
    // every time keys arrive, and wiping the column each time would flicker.
    final previous = {for (final server in servers) server.id: server};
    ServerOption carry(ServerOption server) {
      final before = previous[server.id];
      if (before == null || server.latencyMs != null) return server;
      if (before.latencyMs case final latency?) {
        return server.withLatency(latency);
      }
      return before.unreachable ? server.withUnreachable() : server;
    }

    final carried = loaded.map(carry).toList();
    // Usable first, the rest below in their own order (#126).
    servers = [
      if (loaded.isNotEmpty) const ServerOption.automatic(),
      ...carried.where((server) => server.available),
      ...carried.where((server) => !server.available),
    ];
    selected =
        servers.where((server) => server.id == savedId).firstOrNull ??
        servers.firstOrNull;
    final wasActive = active;
    active = wasActive == null
        ? null
        : servers.where((server) => server.id == wasActive.id).firstOrNull;
    notifyListeners();
    if (wasActive != null && active == null) {
      Diagnostics.record('the server in use was removed: ${wasActive.name}');
      onActiveRemoved?.call(wasActive);
    }
    _measureGeneration++;
    _latencyRefreshTimer?.cancel();
    unawaited(_measureLatencies(_measureGeneration));
  }

  void _scheduleMeasurement(Duration after) {
    _latencyRefreshTimer?.cancel();
    final generation = _measureGeneration;
    _latencyRefreshTimer = Timer(after, () {
      if (generation == _measureGeneration) {
        unawaited(_measureLatencies(generation));
      }
    });
  }

  Future<void> _measureLatencies(int generation) async {
    if (!backgroundMeasurement) return;
    for (final server in [...servers]) {
      if (generation != _measureGeneration) return;
      if (!server.connectable) continue;
      // While connected, the server in use is left alone: a probe of it is a
      // second device with the same key and takes the session from the live
      // tunnel (#102). Everything else is measured once, so a server that
      // arrived while connected still gets a figure (#128).
      // A fresh figure is not asked for again; one that did not answer is,
      // because a server just issued often answers a minute later (#132).
      final at = _measuredAt[server.id];
      final fresh =
          at != null &&
          DateTime.now().difference(at) < const Duration(minutes: 4);
      if (_tunnelActive &&
          (server.id == active?.id || (fresh && !server.unreachable))) {
        continue;
      }
      final pending = catalog.measureLatency(server);
      _measuring[server.id] = pending;
      int? latency;
      try {
        latency = await pending;
      } on Object {
        latency = null;
      } finally {
        if (identical(_measuring[server.id], pending)) {
          _measuring.remove(server.id);
        }
      }
      if (generation != _measureGeneration) continue;
      Diagnostics.record(
        latency == null
            ? 'measure: ${server.name} did not answer'
            : 'measure: ${server.name} ${latency}ms',
      );
      if (latency == null) {
        _recordUnreachable(server.id);
      } else {
        _recordLatency(server.id, latency);
        _considerFaster();
      }
    }
    if (generation != _measureGeneration) return;
    final interval = latencyRefreshInterval;
    if (interval != null) _scheduleMeasurement(interval);
  }

  void _recordUnreachable(String id) {
    _measuredAt[id] = DateTime.now();
    servers = [
      for (final current in servers)
        if (current.id == id) current.withUnreachable() else current,
    ];
    if (selected?.id == id) selected = selected!.withUnreachable();
    notifyListeners();
  }

  /// When each server was last measured.
  final _measuredAt = <String, DateTime>{};

  /// Told when, while connected automatically, another server measures
  /// clearly faster than the one in use (#132). The app reconnects, which
  /// chooses afresh.
  void Function(ServerOption faster)? onFasterAvailable;

  /// How much faster another server must be to be worth moving to.
  static const switchWhenFaster = 0.7;

  /// The least time between two moves made for speed.
  static const switchCooldown = Duration(minutes: 10);

  DateTime? _lastSwitch;

  void _considerFaster() {
    if (!_tunnelActive || !isAutomatic) return;
    final current = active;
    final own = current?.latencyMs;
    if (current == null || own == null) return;
    final now = DateTime.now();
    if (_lastSwitch case final last?
        when now.difference(last) < switchCooldown) {
      return;
    }
    final faster = servers
        .where(
          (server) =>
              server.connectable &&
              server.id != current.id &&
              server.latencyMs != null &&
              server.latencyMs! < own * switchWhenFaster,
        )
        .fold<ServerOption?>(
          null,
          (best, server) => best == null || server.latencyMs! < best.latencyMs!
              ? server
              : best,
        );
    if (faster == null) return;
    _lastSwitch = now;
    Diagnostics.record(
      'moving to ${faster.name} (${faster.latencyMs}ms), faster than '
      '${current.name} (${own}ms)',
    );
    onFasterAvailable?.call(faster);
  }

  void _recordLatency(String id, int latency) {
    _measuredAt[id] = DateTime.now();
    ServerOption? measured;
    servers = [
      for (final current in servers)
        if (current.id == id)
          measured = current.withLatency(latency)
        else
          current,
    ];
    if (measured == null) return;
    if (selected?.id == id) selected = measured;
    if (active?.id == id) active = measured;
    notifyListeners();
  }

  Future<void> select(ServerOption server) async {
    if (!servers.contains(server) || !server.available) return;

    // Ключей ещё нет — просим их и перечитываем список: узел появляется только
    // после того, как сервер его выдал.
    if (server.needsKeys) {
      // Один запрос за раз. Пока идёт выдача, второе нажатие означало бы второй
      // peer на другом сервере — и подключение к тому, что нажали позже, а не к
      // тому, что выбрали.
      if (isPreparing) return;

      // Отмечаем выбранным сразу: человек нажал, и список обязан это показать,
      // не дожидаясь чужого сервера.
      preparing = server;
      notifyListeners();
      try {
        final granted = await requestKeys(server);
        if (!granted) return;
        await load();
      } finally {
        preparing = null;
        notifyListeners();
      }
      final now = servers.firstWhere(
        (candidate) =>
            candidate.subscriptionId == server.subscriptionId &&
            candidate.name == server.name &&
            candidate.nodeId != null,
        orElse: () => server,
      );
      if (now.nodeId == null) return;
      return select(now);
    }

    if (server.configId case final id?) {
      await activateConfiguration(id);
    } else if ((server.subscriptionId, server.nodeId) case (
      final subscriptionId?,
      final nodeId?,
    )) {
      await activateNode(subscriptionId, nodeId);
    }
    await writeSelected(server.id);
    selected = server;
    notifyListeners();
  }

  /// Decides what the next connection goes through and makes it the active
  /// configuration. The [TunnelController] calls this before every attempt.
  ///
  /// A server picked by hand is used as it is: the person chose it, and
  /// quietly connecting somewhere else would make the list a lie. The tunnel
  /// itself proves whether it answers.
  ///
  /// Automatic takes the fastest server that carries a real request from this
  /// device, asking the one that worked last time first (#112). The backend
  /// cannot know where somebody is; the device can measure it. If nothing
  /// answers, subscriptions are fetched again and the list is tried once more,
  /// then keys are asked for on offered servers, before giving up.
  Future<PreparedConnection> prepareConnection(
    Set<String> tried,
    bool Function() cancelled,
  ) async {
    // What the panel says now, before anything is probed (#124): a server
    // removed a minute ago should neither be tried nor be shown.
    if (tried.isEmpty) {
      final before = selected;
      await syncWithSubscriptions();
      if (cancelled()) return const PreparedConnection.cancelled();
      // The server picked by hand is gone. Connecting somewhere else without
      // a word is the surprise this avoids (#128): say so, and leave the
      // choice on automatic so the next press connects.
      if (before != null &&
          !before.automatic &&
          !servers.any((server) => server.id == before.id)) {
        removedChoice = before.name;
        await writeSelected(ServerOption.automaticId);
        Diagnostics.record(
          'the server picked by hand was removed: ${before.name}',
        );
        return const PreparedConnection.failed(
          TunnelFailure.chosenServerRemoved,
        );
      }
    }
    removedChoice = null;
    final choice = selected;
    if (choice != null && !choice.automatic) {
      if (tried.contains(choice.id)) {
        return const PreparedConnection.failed(
          TunnelFailure.chosenServerUnreachable,
        );
      }
      if (!choice.connectable) {
        return const PreparedConnection.failed(
          TunnelFailure.chosenServerUnreachable,
        );
      }
      // Checked on every press, like automatic (#123). Handing the tunnel a
      // configuration nobody has tried is how a server removed in the panel
      // came to be shown as connected.
      final latency = await _probe(choice);
      if (cancelled()) return const PreparedConnection.cancelled();
      if (latency == null) {
        _recordUnreachable(choice.id);
        return const PreparedConnection.failed(
          TunnelFailure.chosenServerUnreachable,
        );
      }
      _recordLatency(choice.id, latency);
      await catalog.activate(choice);
      active =
          servers.where((each) => each.id == choice.id).firstOrNull ?? choice;
      notifyListeners();
      Diagnostics.record('connecting through ${choice.name}, picked by hand');
      return PreparedConnection.ready(choice.id, latencyMs: latency);
    }

    var found = await _fastest(tried, cancelled);
    if (cancelled()) return const PreparedConnection.cancelled();
    var gone = false;

    if (found == null && tried.isEmpty) {
      // Keys may have been rotated since the last fetch, or a subscription
      // whose cache was empty may have servers now.
      gone = await _refreshAndReload();
      if (cancelled()) return const PreparedConnection.cancelled();
      found = await _fastest(tried, cancelled);
      if (cancelled()) return const PreparedConnection.cancelled();
    }

    // Nothing with keys answered. A subscription that hands out keys on demand
    // may still have servers that work; ask for a few (#107).
    if (found == null && !gone) {
      found = await _provisionUntilWorking(cancelled);
      if (cancelled()) return const PreparedConnection.cancelled();
    }

    if (found == null) {
      final anything = servers.any(
        (server) => server.connectable || server.needsKeys,
      );
      return PreparedConnection.failed(
        gone
            ? TunnelFailure.subscriptionGone
            : anything
            ? TunnelFailure.noServerReachable
            : TunnelFailure.noServers,
      );
    }

    final (server, latency) = found;
    await catalog.activate(server);
    _recordLatency(server.id, latency);
    active =
        servers.where((each) => each.id == server.id).firstOrNull ?? server;
    notifyListeners();
    return PreparedConnection.ready(
      server.id,
      retryable: true,
      latencyMs: latency,
    );
  }

  /// True when every subscription was just refused as unknown.
  Future<bool> _refreshAndReload() async {
    var gone = false;
    try {
      gone = await refreshSubscriptions();
    } on Object catch (error) {
      Diagnostics.record(
        'subscription refresh before retry failed',
        error: error,
      );
    }
    await load();
    return gone;
  }

  /// How many offered servers one connection may ask keys for.
  static const maxProvisionPerConnection = 3;

  /// Asks for keys on offered servers, in list order, one at a time, and
  /// returns the first new node that carries traffic.
  ///
  /// One at a time and few: each request provisions a peer on a real server,
  /// and a phone on a network that blocks everything would otherwise ask for
  /// keys on every server the link offers.
  Future<(ServerOption, int)?> _provisionUntilWorking(
    bool Function() cancelled,
  ) async {
    final offers = servers
        .where((server) => server.needsKeys && server.available)
        .take(maxProvisionPerConnection)
        .toList();
    for (final offer in offers) {
      if (cancelled()) return null;
      preparing = offer;
      notifyListeners();
      try {
        Diagnostics.record('asking for keys on ${offer.name}');
        if (!await requestKeys(offer)) continue;
        await load();
        if (cancelled()) return null;
        final node = servers
            .where(
              (candidate) =>
                  candidate.subscriptionId == offer.subscriptionId &&
                  candidate.name == offer.name &&
                  candidate.connectable,
            )
            .firstOrNull;
        if (node == null) continue;
        int? latency;
        try {
          latency = await catalog.measureLatency(node);
        } on Object {
          latency = null;
        }
        if (latency != null) return (node, latency);
      } on Object catch (error) {
        Diagnostics.record('asking for keys failed', error: error);
      } finally {
        preparing = null;
        notifyListeners();
      }
    }
    return null;
  }

  /// The fastest candidate that carries traffic (#112).
  ///
  /// Every candidate is asked at once. Slow ones are not waited for
  /// to time out: once one answers, the rest get [fastestGrace], and the
  /// lowest latency among those that answered wins. Ties go to the
  /// subscription's order.
  Future<(ServerOption, int)?> _fastest(
    Set<String> tried,
    bool Function() cancelled,
  ) async {
    final candidates = servers
        .where((server) => server.connectable && !tried.contains(server.id))
        .toList();
    if (candidates.isEmpty) return null;

    final answered = <(ServerOption, int)>[];
    final settled = Completer<void>();
    var outstanding = candidates.length;
    var next = 0;
    var finished = false;
    Timer? grace;

    void settle() {
      if (!settled.isCompleted) settled.complete();
    }

    Future<void> worker() async {
      while (next < candidates.length) {
        final server = candidates[next++];
        if (!finished && !cancelled()) {
          final latency = await _probe(server);
          if (latency != null && !finished) {
            answered.add((server, latency));
            grace ??= Timer(fastestGrace, settle);
          }
        }
        if (--outstanding == 0) settle();
      }
    }

    final workers = probeConcurrency.clamp(1, candidates.length);
    for (var i = 0; i < workers; i++) {
      unawaited(worker());
    }
    await settled.future;
    finished = true;
    grace?.cancel();

    if (cancelled() || answered.isEmpty) return null;
    answered.sort((a, b) {
      final byLatency = a.$2.compareTo(b.$2);
      if (byLatency != 0) return byLatency;
      return candidates.indexOf(a.$1).compareTo(candidates.indexOf(b.$1));
    });
    // The one that worked last time keeps the connection when it is about as
    // fast as the best: moving between near-equal servers on every press
    // gains nothing and changes the address every time.
    final best = answered.first;
    final lastId = await readLastConnected().catchError((_) => null);
    final last = answered.where((each) => each.$1.id == lastId).firstOrNull;
    final pick = last != null && last.$2 <= best.$2 * 1.15 ? last : best;
    Diagnostics.record(
      'chose ${pick.$1.name} (${pick.$2}ms) of ${answered.length} that '
      'answered out of ${candidates.length}',
    );
    return pick;
  }

  Future<int?> _probe(ServerOption server) async {
    int? latency;
    try {
      // A measurement of this server already in flight is the answer.
      // Starting a second one would be two devices handshaking with one key
      // at once; the server takes one and the other waits out a retry.
      latency = await (_measuring[server.id] ?? catalog.measureLatency(server));
    } on Object {
      latency = null;
    }
    Diagnostics.record(
      latency == null
          ? 'probe: ${server.name} did not answer'
          : 'probe: ${server.name} answered in ${latency}ms',
    );
    return latency;
  }

  /// Remembers the server the tunnel came up through, so the next connection
  /// asks it first. Called once the tunnel reports connected.
  Future<void> rememberActive() async {
    final server = active;
    if (server == null) return;
    await writeLastConnected(server.id).catchError((_) {});
  }

  /// Asks the subscription for keys on a server it offers.
  ///
  /// Separate and injectable so the picker can be driven in a test without a
  /// network, and written out rather than passed as a tear-off: `a ?? b` over
  /// two functions with no common type infers plain Function and goes dynamic,
  /// which compiles and then throws on a device (#71).
  Future<bool> requestKeys(ServerOption server) async {
    final subscriptionId = server.subscriptionId;
    final serverId = server.serverId;
    if (subscriptionId == null || serverId == null) return false;

    final subscription = await readSubscription(subscriptionId);
    if (subscription == null) return false;

    return await grantServer(subscription, serverId) != null;
  }

  /// Forgets everything held in memory. For when the account is forgotten.
  void clear() {
    _loadGeneration++;
    _measureGeneration++;
    _latencyRefreshTimer?.cancel();
    servers = const [];
    selected = null;
    active = null;
    preparing = null;
    notifyListeners();
  }

  static Future<void> _activateNode(
    String subscriptionId,
    String nodeId,
  ) async {
    final subscription = await SubscriptionStore.byId(subscriptionId);
    if (subscription == null) return;
    final node = subscription.nodes
        .where((candidate) => candidate.id == nodeId)
        .firstOrNull;
    if (node == null || node.maintenance) return;
    await SubscriptionStore.save(subscription.copyWith(pinnedId: node.id));
    await ConfigStore.activateSubscriptionNode(node.endpoint);
  }

  static Future<bool> _checkSubscriptions() async {
    final before = await SubscriptionStore.all();
    final after = await SubscriptionFetcher.refreshDue();
    for (var i = 0; i < after.length; i++) {
      if (i >= before.length || !identical(after[i], before[i])) return true;
    }
    return false;
  }

  static Future<bool> _refreshSubscriptions() async {
    final refreshed = await SubscriptionFetcher.refreshDue(force: true);
    return refreshed.isNotEmpty &&
        refreshed.every((subscription) => subscription.isGone);
  }

  @override
  void dispose() {
    _loadGeneration++;
    _measureGeneration++;
    _latencyRefreshTimer?.cancel();
    super.dispose();
  }
}

class ServerSelectionScope
    extends InheritedNotifier<ServerSelectionController> {
  const ServerSelectionScope({
    required ServerSelectionController controller,
    required super.child,
    super.key,
  }) : super(notifier: controller);

  static ServerSelectionController of(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<ServerSelectionScope>()!
      .notifier!;
}
