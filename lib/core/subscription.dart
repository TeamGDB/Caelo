import 'dart:convert';

/// One node a subscription offers.
///
/// [endpoint] is the endpoint object exactly as it was served, kept as text and
/// never interpreted here. What a node *is* — keys, addresses, MTU,
/// obfuscation — belongs to the core, next to the code that dials with it; a
/// second reading of that format in Dart would eventually disagree with the one
/// that connects, and only one of the two would be tested.
///
/// The app reads the list, its order and the names. That is all.
class SubscriptionNode {
  const SubscriptionNode({
    required this.id,
    required this.tag,
    required this.endpoint,
    required this.position,
    this.country = '',
    this.description = '',
    this.maintenance = false,
    this.protocol = amneziaWgProtocol,
  });

  /// What this node is remembered by.
  ///
  /// From the server when it sends a Caelo document, and made up otherwise —
  /// see [identify]. A choice somebody made by hand is stored against this, so
  /// it is the one field whose stability decides whether that choice survives a
  /// refresh.
  final String id;

  /// What to call it. May be empty: a server is not obliged to name its nodes,
  /// and the interface can fall back to the position.
  final String tag;

  /// The endpoint object, as served. Handed to the core unchanged.
  final String endpoint;

  /// Where it came in the list. The order *is* the priority — the server
  /// decided it, and recomputing it here would be overriding a decision we were
  /// told rather than making one.
  final int position;

  /// ISO 3166-1 alpha-2, or empty. The flag is built from this rather than
  /// sent: an emoji is a picture, and a picture cannot be sorted by.
  final String country;

  /// One line from the server about this node. Shown as sent; the server knows
  /// what it wants to say and in which language.
  final String description;

  /// The server saying "not this one, for now". Skipped when choosing, and
  /// still worth showing: a node that is missing looks like a node that was
  /// taken away.
  final bool maintenance;

  /// Which protocol carries it: `amneziawg`, `vless`. The name, as
  /// capabilities and documents spell it; what the protocol *is* stays in the
  /// core with everything else about a node.
  final String protocol;

  /// The flag for [country], built here rather than transmitted.
  ///
  /// Regional indicators are the letters offset into a block of their own, so
  /// this is arithmetic rather than a table of two hundred entries that would
  /// go out of date.
  String get flag => flagFor(country);

  /// Shared with [AvailableServer], which needs the same arithmetic for the
  /// same reason and should not carry a second copy of it.
  static String flagFor(String country) {
    if (country.length != 2) return '';
    final upper = country.toUpperCase();
    const base = 0x1F1E6;
    const a = 0x41;
    final first = upper.codeUnitAt(0);
    final second = upper.codeUnitAt(1);
    if (first < a || first > a + 25 || second < a || second > a + 25) return '';
    return String.fromCharCodes([base + first - a, base + second - a]);
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'tag': tag,
    'endpoint': endpoint,
    'position': position,
    if (country.isNotEmpty) 'country': country,
    if (description.isNotEmpty) 'description': description,
    if (maintenance) 'maintenance': true,
    // Absent for AmneziaWG, as it was in every node stored before there was
    // a choice.
    if (protocol != amneziaWgProtocol) 'protocol': protocol,
  };

  /// The same node under another identity — what [identify] hands out.
  SubscriptionNode withId(String id) => SubscriptionNode(
    id: id,
    tag: tag,
    endpoint: endpoint,
    position: position,
    country: country,
    description: description,
    maintenance: maintenance,
    protocol: protocol,
  );

  static SubscriptionNode fromJson(Map<String, dynamic> json) =>
      SubscriptionNode(
        id: json['id'] as String? ?? '',
        tag: json['tag'] as String? ?? '',
        endpoint: json['endpoint'] as String? ?? '',
        position: json['position'] as int? ?? 0,
        country: json['country'] as String? ?? '',
        description: json['description'] as String? ?? '',
        maintenance: json['maintenance'] == true,
        protocol: json['protocol'] as String? ?? amneziaWgProtocol,
      );
}

/// What the server said about the account behind a subscription.
///
/// From the `subscription-userinfo` response header, whose spelling comes from
/// the V2Ray and Clash ecosystems: followed rather than reinvented so that a
/// Caelo subscription can be read by other clients and theirs by us.
class SubscriptionUsage {
  const SubscriptionUsage({
    this.uploadBytes,
    this.downloadBytes,
    this.totalBytes,
    this.expires,
  });

  final int? uploadBytes;
  final int? downloadBytes;

  /// The allowance. Null when the server did not say, which is not the same as
  /// zero and must not be shown as "nothing left".
  final int? totalBytes;

  /// When access ends. Null when the server did not say or sent `expire=0`.
  final DateTime? expires;

  int? get usedBytes {
    final up = uploadBytes;
    final down = downloadBytes;
    if (up == null && down == null) return null;
    return (up ?? 0) + (down ?? 0);
  }

  int? get remainingBytes {
    final total = totalBytes;
    final used = usedBytes;
    if (total == null || used == null) return null;
    final left = total - used;
    return left < 0 ? 0 : left;
  }

  bool get isEmpty =>
      uploadBytes == null &&
      downloadBytes == null &&
      totalBytes == null &&
      expires == null;

  /// Reads the header. Every field is optional and a malformed one is skipped
  /// rather than fatal: a subscription whose quota display is wrong is still a
  /// subscription somebody is trying to connect through.
  static SubscriptionUsage parse(String? header) {
    if (header == null || header.trim().isEmpty) {
      return const SubscriptionUsage();
    }

    final values = <String, int>{};
    for (final part in header.split(';')) {
      final cut = part.indexOf('=');
      if (cut < 0) continue;
      final key = part.substring(0, cut).trim().toLowerCase();
      final value = int.tryParse(part.substring(cut + 1).trim());
      if (value != null) values[key] = value;
    }

    final expire = values['expire'];
    return SubscriptionUsage(
      uploadBytes: values['upload'],
      downloadBytes: values['download'],
      totalBytes: values['total'],
      // Zero is the convention for "no expiry", not for the epoch.
      expires: expire == null || expire == 0
          ? null
          : DateTime.fromMillisecondsSinceEpoch(expire * 1000, isUtc: true),
    );
  }

  Map<String, dynamic> toJson() => {
    if (uploadBytes != null) 'upload': uploadBytes,
    if (downloadBytes != null) 'download': downloadBytes,
    if (totalBytes != null) 'total': totalBytes,
    if (expires != null) 'expire': expires!.millisecondsSinceEpoch ~/ 1000,
  };

  static SubscriptionUsage fromJson(Map<String, dynamic>? json) {
    if (json == null) return const SubscriptionUsage();
    final expire = json['expire'] as int?;
    return SubscriptionUsage(
      uploadBytes: json['upload'] as int?,
      downloadBytes: json['download'] as int?,
      totalBytes: json['total'] as int?,
      expires: expire == null || expire == 0
          ? null
          : DateTime.fromMillisecondsSinceEpoch(expire * 1000, isUtc: true),
    );
  }
}

/// A subscription and the last answer it gave.
///
/// [nodes] is a cache, not a fetch: it is whatever the last successful refresh
/// returned. A subscription that is unreachable, or that answers with something
/// unparseable, leaves this untouched and the client keeps working. Whatever
/// else is failing, the VPN is what somebody is trying to use to fix it.
/// A server the subscription can hand out but has not yet.
///
/// No keys: until a configuration exists there is nothing to carry. The client
/// shows it in the list and asks for it when somebody picks it — which is what
/// stops a subscription provisioning every server on a link nobody will use.
class AvailableServer {
  const AvailableServer({
    required this.id,
    required this.name,
    this.country = '',
    this.description = '',
    this.ready = false,
  });

  final String id;
  final String name;
  final String country;
  final String description;

  /// Whether this device already has keys for it.
  final bool ready;

  String get flag => SubscriptionNode.flagFor(country);

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    if (country.isNotEmpty) 'country': country,
    if (description.isNotEmpty) 'description': description,
    'ready': ready,
  };

  static AvailableServer fromJson(Map<String, dynamic> json) => AvailableServer(
    id: json['id'] as String? ?? '',
    name: json['name'] as String? ?? '',
    country: json['country'] as String? ?? '',
    description: json['description'] as String? ?? '',
    ready: json['ready'] as bool? ?? false,
  );
}

class Subscription {
  const Subscription({
    required this.id,
    required this.url,
    this.name = '',
    this.nodes = const [],
    this.usage = const SubscriptionUsage(),
    this.updateInterval,
    this.lastFetched,
    this.lastError,
    this.pinnedId,
    this.stateVersion,
    this.available = const [],
    this.fetchedAsDevice = false,
    this.skipped = const [],
    this.title = '',
  });

  /// Stable across refreshes and renames, so that a pinned node and a
  /// subscription survive the list being rewritten.
  final String id;

  final String url;

  /// What the person called it. Ours to keep; the server has no say.
  final String name;

  /// The last list that arrived, in the order it arrived.
  final List<SubscriptionNode> nodes;

  final SubscriptionUsage usage;

  /// How long the server asked us to wait, from `profile-update-interval`.
  final Duration? updateInterval;

  final DateTime? lastFetched;

  /// Why the last attempt failed, if it did. Kept beside the cached nodes
  /// rather than replacing them: both are true at once, and an interface that
  /// showed only the error would suggest there is nothing to connect to.
  final String? lastError;

  /// What the server called the state of this list last time we looked.
  ///
  /// Opaque: compared for equality and nothing else. It is what makes checking
  /// cheap — the state endpoint answers with it in a few hundred bytes, while
  /// the document itself carries the private key of every node, which is a lot
  /// to fetch in order to learn that nothing moved.
  final String? stateVersion;

  /// Everything this subscription can hand out, whether or not it has. Empty
  /// against a server that does not offer the catalogue, and then the node list
  /// is the whole of what there is.
  final List<AvailableServer> available;

  /// Whether the last successful fetch carried the device headers.
  ///
  /// Clients before v0.2.0 sent none, and a server that keeps keys per device
  /// does not know an installation it has never been told about (#159).
  final bool fetchedAsDevice;

  /// Why nodes the last refresh received are not in [nodes]: one short reason
  /// per node, as [SubscriptionRead.skipped] gives them. Shown, so that a
  /// subscription carrying protocols this build cannot run says so rather than
  /// looking smaller than the server's own list.
  final List<String> skipped;

  /// What the server calls this subscription, from `profile-title`. Shown
  /// where the subscription itself has to be named; [name] is the person's
  /// and wins over it.
  final String title;

  /// The server answered with a valid subscription that has nothing in it:
  /// no nodes and nothing on offer. Distinct from a refresh that failed, which
  /// keeps the last list, and from one this build cannot use, which says why.
  bool get isEmpty =>
      lastFetched != null &&
      lastError == null &&
      nodes.isEmpty &&
      available.isEmpty;

  /// A node the person chose by hand, by [SubscriptionNode.id].
  ///
  /// By id rather than by tag or position, because both change: a refresh
  /// reorders, and a tag is neither required nor required to be unique. It
  /// survives an update if that node is still offered and is forgotten if it is
  /// not — a pin to a node the server has withdrawn is a pin to nothing.
  final String? pinnedId;

  bool get hasNodes => nodes.isNotEmpty;

  /// The server said, at the last refresh, that this link is not one of its
  /// subscriptions: revoked, expired, or never was.
  bool get isGone => lastError == subscriptionGoneMessage;

  /// The node to try first: whatever was pinned, then the server's order.
  SubscriptionNode? get preferred {
    if (nodes.isEmpty) return null;
    final pinned = pinnedId;
    if (pinned != null) {
      for (final node in nodes) {
        if (node.id == pinned) return node;
      }
    }
    // The first the server offered that it has not taken out of service.
    for (final node in nodes) {
      if (!node.maintenance) return node;
    }
    return nodes.first;
  }

  /// Every node, most preferred first.
  ///
  /// A pinned node moves to the front and the rest keep the server's order. It
  /// is a list rather than a single choice because connecting is "try until one
  /// carries traffic", and the order to try in is the whole of what the client
  /// decides.
  List<SubscriptionNode> get candidates {
    // Nodes the server has taken out of service are not tried. It said so
    // before we spent anybody's time finding out.
    final usable = nodes.where((node) => !node.maintenance).toList();
    if (usable.isEmpty) return const [];

    final pinned = preferred;
    if (pinned == null || pinned.maintenance || pinned == usable.first) {
      return usable;
    }
    return [pinned, ...usable.where((node) => node != pinned)];
  }

  /// Whether the server's requested interval has elapsed.
  ///
  /// Never fetched counts as due. No interval means the server did not ask, and
  /// refreshing on a schedule it did not request is a request it did not want.
  bool get isDue {
    final fetched = lastFetched;
    final interval = updateInterval;
    if (fetched == null) return true;
    if (interval == null) return false;
    return DateTime.now().difference(fetched) >= interval;
  }

  /// Whether the server may never have heard of this device.
  ///
  /// A stored version means the state checks already carry the headers, so
  /// only a subscription with neither is asked once more, out of schedule.
  bool get isUnannounced => !fetchedAsDevice && stateVersion == null;

  Subscription copyWith({
    String? name,
    List<SubscriptionNode>? nodes,
    SubscriptionUsage? usage,
    Duration? updateInterval,
    DateTime? lastFetched,
    String? lastError,
    bool clearError = false,
    String? pinnedId,
    bool clearPin = false,
    String? stateVersion,
    List<AvailableServer>? available,
    bool? fetchedAsDevice,
    List<String>? skipped,
    String? title,
  }) {
    return Subscription(
      id: id,
      url: url,
      name: name ?? this.name,
      nodes: nodes ?? this.nodes,
      usage: usage ?? this.usage,
      updateInterval: updateInterval ?? this.updateInterval,
      lastFetched: lastFetched ?? this.lastFetched,
      lastError: clearError ? null : (lastError ?? this.lastError),
      pinnedId: clearPin ? null : (pinnedId ?? this.pinnedId),
      stateVersion: stateVersion ?? this.stateVersion,
      available: available ?? this.available,
      fetchedAsDevice: fetchedAsDevice ?? this.fetchedAsDevice,
      skipped: skipped ?? this.skipped,
      title: title ?? this.title,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'url': url,
    'name': name,
    'nodes': nodes.map((node) => node.toJson()).toList(),
    'usage': usage.toJson(),
    if (updateInterval != null)
      'updateIntervalMinutes': updateInterval!.inMinutes,
    if (lastFetched != null) 'lastFetched': lastFetched!.toIso8601String(),
    if (lastError != null) 'lastError': lastError,
    if (pinnedId != null) 'pinnedId': pinnedId,
    if (stateVersion != null) 'stateVersion': stateVersion,
    if (available.isNotEmpty)
      'available': available.map((server) => server.toJson()).toList(),
    if (fetchedAsDevice) 'fetchedAsDevice': true,
    if (skipped.isNotEmpty) 'skipped': skipped,
    if (title.isNotEmpty) 'title': title,
  };

  static Subscription fromJson(Map<String, dynamic> json) {
    final minutes = json['updateIntervalMinutes'] as int?;
    final fetched = json['lastFetched'] as String?;
    return Subscription(
      id: json['id'] as String? ?? '',
      url: json['url'] as String? ?? '',
      name: json['name'] as String? ?? '',
      nodes: (json['nodes'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(SubscriptionNode.fromJson)
          .toList(),
      usage: SubscriptionUsage.fromJson(json['usage'] as Map<String, dynamic>?),
      updateInterval: minutes == null ? null : Duration(minutes: minutes),
      lastFetched: fetched == null ? null : DateTime.tryParse(fetched),
      lastError: json['lastError'] as String?,
      pinnedId: json['pinnedId'] as String?,
      stateVersion: json['stateVersion'] as String?,
      available: (json['available'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(AvailableServer.fromJson)
          .toList(),
      fetchedAsDevice: json['fetchedAsDevice'] == true,
      skipped: (json['skipped'] as List? ?? const [])
          .whereType<String>()
          .toList(),
      title: json['title'] as String? ?? '',
    );
  }
}

/// Reads `profile-title`: plain text, or `base64:` and base64 of UTF-8 — the
/// form servers use for a name that is not ASCII, since a header cannot carry
/// it. Empty when absent or unreadable; a name is not worth failing over.
String parseProfileTitle(String? header) {
  final value = header?.trim() ?? '';
  if (value.isEmpty) return '';
  if (value.toLowerCase().startsWith('base64:')) {
    var encoded = value
        .substring(7)
        .trim()
        .replaceAll('-', '+')
        .replaceAll('_', '/');
    final remainder = encoded.length % 4;
    if (remainder > 1) {
      encoded = encoded.padRight(encoded.length + 4 - remainder, '=');
    }
    try {
      return utf8.decode(base64.decode(encoded)).trim();
    } on FormatException {
      return '';
    }
  }
  // Headers arrive as Latin-1; a server that sent UTF-8 bytes anyway meant
  // UTF-8.
  try {
    return utf8.decode(latin1.encode(value)).trim();
  } on Object {
    return value;
  }
}

/// What a refresh records when the server says the link is not a
/// subscription. Recorded as text like every other failure, and compared here
/// so the interface can tell "revoked" from "unreachable" (#106).
const subscriptionGoneMessage =
    'the server does not recognise this subscription';

/// What a refresh records when the server has servers for the subscription
/// and none this build can run: `406 Not Acceptable` (#172).
const noRunnableServersMessage =
    'the subscription has no servers this version of Caelo can run';

/// The media type a server uses to say it sent the richer document.
const caeloDocumentType = 'application/vnd.caelo.subscription+json';

/// The protocol every build runs, and every node was before there was a
/// choice.
const amneziaWgProtocol = 'amneziawg';

/// What a refresh read out of a document.
class SubscriptionRead {
  const SubscriptionRead(this.nodes, {this.skipped = const []});

  /// Every node this build can use, identified, in the order served.
  final List<SubscriptionNode> nodes;

  /// Why each node that was served and is not in [nodes] was left out, one
  /// short reason per node: "vmess", "vless: transport ws not supported".
  /// Kept so that a subscription carrying protocols this build does not run
  /// says so, rather than looking smaller than it is.
  final List<String> skipped;
}

/// Reads the node list out of a subscription, whatever shape it came in.
///
/// Only the list: which nodes there are, what they are called, what to show
/// about them, what carries them, and what order they came in. Each node is
/// carried as text — an endpoint object re-encoded, or a link as served — so
/// that nothing here has to know what is inside one.
///
/// Which shape it is comes from the response rather than from what was asked
/// for, so a server may ignore the Accept header entirely and a client never
/// has to ask twice: JSON is the Caelo document when the `Content-Type` says
/// so and sing-box's otherwise, and anything that is not JSON is a list of
/// links, one per line, possibly in base64 — the shape every V2Ray-family
/// subscription already serves.
///
/// [protocols] are what this build runs. Nodes of others are skipped, never
/// refused: a subscription that also carries protocols this build cannot run
/// is one whose other nodes still work, and turning the whole of it down would
/// take those away too.
///
/// A document with no nodes at all is a valid, empty subscription, and comes
/// back empty. One whose nodes are all of protocols this build cannot run is
/// refused with that reason, so that the list that worked stays in place.
SubscriptionRead readSubscription(
  String body, {
  String? contentType,
  Set<String> protocols = const {amneziaWgProtocol},
}) {
  // A byte order mark is not content, and leaving it in front of a JSON
  // document would send it down the path for links.
  final trimmed = body.replaceFirst('\uFEFF', '').trim();
  final mime = contentType?.toLowerCase() ?? '';

  final _Read read;
  if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
    final decoded = jsonDecode(trimmed);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('the document is not a JSON object');
    }
    read = mime.contains('vnd.caelo.subscription')
        ? _readCaelo(decoded, protocols)
        : _readPlain(decoded, protocols);
  } else {
    read = _readLinks(trimmed, protocols, plainText: mime == 'text/plain');
  }

  if (read.nodes.isEmpty && read.skipped.isNotEmpty) {
    throw FormatException(
      'none of the nodes can run in this build: ${_summarise(read.skipped)}',
    );
  }
  return SubscriptionRead(identify(read.nodes), skipped: read.skipped);
}

/// The nodes alone. See [readSubscription].
List<SubscriptionNode> readNodes(
  String body, {
  String? contentType,
  Set<String> protocols = const {amneziaWgProtocol},
}) => readSubscription(
  body,
  contentType: contentType,
  protocols: protocols,
).nodes;

/// "vmess ×3, vless: transport ws not supported" — what was left out, short.
String _summarise(List<String> skipped) {
  final counts = <String, int>{};
  for (final reason in skipped) {
    counts[reason] = (counts[reason] ?? 0) + 1;
  }
  return counts.entries
      .map((e) => e.value == 1 ? e.key : '${e.key} ×${e.value}')
      .join(', ');
}

class _Read {
  _Read();
  final nodes = <SubscriptionNode>[];
  final skipped = <String>[];
}

/// The plain document: sing-box JSON, and nothing about a node but its tag.
_Read _readPlain(Map<String, dynamic> document, Set<String> protocols) {
  final endpoints = document['endpoints'];
  if (endpoints is! List) {
    throw const FormatException('the document has no endpoints');
  }

  final read = _Read();
  for (var index = 0; index < endpoints.length; index++) {
    final endpoint = endpoints[index];
    if (endpoint is! Map<String, dynamic>) continue;
    if (!_isOurs(endpoint)) {
      read.skipped.add('${endpoint['type']}');
      continue;
    }

    read.nodes.add(
      SubscriptionNode(
        id: '',
        tag: endpoint['tag'] as String? ?? '',
        endpoint: jsonEncode(endpoint),
        position: index,
      ),
    );
  }
  // sing-box puts everything that is not WireGuard-shaped in outbounds. None
  // of it is read: a VLESS node reaches this client as a link, not as a
  // sing-box outbound, and those that are not in endpoints are not nodes.
  return read;
}

/// The Caelo document: each node carries its own endpoint or link, plus an
/// identity and what to show.
///
/// Version 1 nodes carry an AmneziaWG `endpoint`; version 2 adds nodes of
/// other protocols, each with a `protocol` and its standard `uri`. One reader
/// serves both: a version-1 client meeting a version-2 document skips the
/// nodes with no endpoint and keeps the rest, which is what lets one server
/// answer both.
_Read _readCaelo(Map<String, dynamic> document, Set<String> protocols) {
  final entries = document['nodes'];
  if (entries is! List) {
    throw const FormatException('the document has no nodes');
  }

  // An unknown version is read for what is recognisable rather than refused.
  // A client that turns down a whole subscription over a field it has not
  // learned yet is a client that stops working when its server is upgraded.
  final read = _Read();
  for (var index = 0; index < entries.length; index++) {
    final entry = entries[index];
    if (entry is! Map<String, dynamic>) continue;

    final endpoint = entry['endpoint'];
    final uri = entry['uri'];
    final String text;
    final String protocol;
    final String tag;
    if (endpoint is Map<String, dynamic>) {
      if (!_isOurs(endpoint)) {
        read.skipped.add('${endpoint['type']}');
        continue;
      }
      text = jsonEncode(endpoint);
      protocol = amneziaWgProtocol;
      tag = endpoint['tag'] as String? ?? '';
    } else if (uri is String && uri.trim().isNotEmpty) {
      protocol =
          (entry['protocol'] as String?)?.toLowerCase() ?? _schemeOf(uri) ?? '';
      // A link for AmneziaWG is nothing this client reads: AmneziaWG nodes
      // carry an endpoint.
      if (protocol.isEmpty ||
          protocol == amneziaWgProtocol ||
          !protocols.contains(protocol)) {
        read.skipped.add(protocol.isEmpty ? 'unknown' : protocol);
        continue;
      }
      text = uri.trim();
      final named = entry['tag'];
      tag = named is String ? named : _fragmentOf(text);
    } else {
      continue;
    }

    read.nodes.add(
      SubscriptionNode(
        id: entry['id'] as String? ?? '',
        tag: tag,
        endpoint: text,
        position: index,
        country: (entry['country'] as String? ?? '').toUpperCase(),
        description: entry['description'] as String? ?? '',
        maintenance: entry['maintenance'] == true,
        protocol: protocol,
      ),
    );
  }
  return read;
}

/// A list of links, one per line, as text or as base64 of that text.
///
/// [plainText] says the server declared `text/plain`, which is what makes an
/// empty answer an empty subscription rather than a server that sent nothing.
_Read _readLinks(
  String body,
  Set<String> protocols, {
  required bool plainText,
}) {
  if (body.isEmpty) {
    if (plainText) return _Read();
    throw const FormatException('the server sent nothing');
  }

  final text = body.contains('://') ? body : _fromBase64(body);
  if (text == null) {
    throw const FormatException(
      'the document is neither JSON nor a list of links',
    );
  }

  final lines = const LineSplitter()
      .convert(text)
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList();
  // At least one line has to be a link itself, starting with its scheme. An
  // error page, a captive portal or a panel's HTML mentions https://
  // somewhere and is none of those; reading it as an empty subscription
  // would throw away the list that worked.
  if (!lines.any((line) => _schemeOf(line) != null)) {
    throw const FormatException(
      'the document is neither JSON nor a list of links',
    );
  }

  final read = _Read();
  for (var index = 0; index < lines.length; index++) {
    final line = lines[index];
    final protocol = _schemeOf(line);
    if (protocol == null) continue; // a comment or a stray line, not a node
    if (!protocols.contains(protocol)) {
      read.skipped.add(protocol);
      continue;
    }
    read.nodes.add(
      SubscriptionNode(
        id: '',
        tag: _fragmentOf(line),
        endpoint: line,
        position: index,
        protocol: protocol,
      ),
    );
  }
  return read;
}

/// Standard or URL-safe base64, with or without padding and line breaks —
/// all of which servers send. Null when it is not base64 of UTF-8 text.
String? _fromBase64(String body) {
  var compact = body.replaceAll(RegExp(r'\s'), '');
  compact = compact.replaceAll('-', '+').replaceAll('_', '/');
  final remainder = compact.length % 4;
  if (remainder == 1) return null;
  if (remainder > 0) {
    compact = compact.padRight(compact.length + 4 - remainder, '=');
  }
  try {
    return utf8.decode(base64.decode(compact));
  } on FormatException {
    return null;
  }
}

/// `vless` for `vless://…`; null for a line that is not a link.
String? _schemeOf(String line) {
  final cut = line.indexOf('://');
  if (cut <= 0) return null;
  final scheme = line.substring(0, cut).toLowerCase();
  return RegExp(r'^[a-z][a-z0-9+.-]*$').hasMatch(scheme) ? scheme : null;
}

/// The name a link gives its node: the fragment, percent-decoded.
String _fragmentOf(String link) {
  final cut = link.indexOf('#');
  if (cut < 0) return '';
  final raw = link.substring(cut + 1);
  try {
    return Uri.decodeComponent(raw).trim();
  } on ArgumentError {
    return raw.trim();
  }
}

/// What identifies a link's node apart from its name and credentials: the
/// protocol, the server and how it is reached. Two kinds of connection to one
/// server (Vision, XHTTP, through a CDN) differ here even when they share a
/// user id; a user id or fingerprint that changes on a refresh does not.
String? _connectionOf(SubscriptionNode node) {
  if (node.protocol == amneziaWgProtocol) return null;
  final Uri uri;
  try {
    uri = Uri.parse(node.endpoint);
  } on FormatException {
    return null;
  }
  if (uri.host.isEmpty) return null;
  final query = uri.queryParameters;
  final transport = (query['type'] ?? 'tcp').toLowerCase();
  return '${node.protocol}://${uri.host}:${uri.port}'
      '/${transport == 'raw' ? 'tcp' : transport}'
      '/${(query['security'] ?? '').toLowerCase()}'
      '/${query['flow'] ?? ''}'
      '${query['path'] ?? ''}';
}

/// Everything that is not AmneziaWG is skipped rather than refused. A
/// subscription that also carries protocols this build cannot run is a
/// subscription whose AmneziaWG nodes still work, and turning the document down
/// would take those away too.
bool _isOurs(Map<String, dynamic> endpoint) {
  final type = endpoint['type'];
  return type == null || type == 'amneziawg';
}

/// Fills in an identity for every node that arrived without one.
///
/// The rule is in docs/subscriptions.md because it decides whose choice
/// survives a refresh: the server's id; then, for a link, the connection it
/// describes — protocol, server, port, transport, security, flow and path,
/// without the user id — if no other node shares it; then the tag, if it is
/// unique in this document; then the position, which is stable only until
/// the server reorders. A tag shared by two nodes identifies neither.
List<SubscriptionNode> identify(List<SubscriptionNode> nodes) {
  final tags = <String, int>{};
  final connections = <String, int>{};
  for (final node in nodes) {
    if (node.tag.isNotEmpty) tags[node.tag] = (tags[node.tag] ?? 0) + 1;
    final connection = _connectionOf(node);
    if (connection != null) {
      connections[connection] = (connections[connection] ?? 0) + 1;
    }
  }

  return [
    for (final node in nodes)
      if (node.id.isNotEmpty)
        node
      else
        node.withId(() {
          // For a link, what it connects to comes first: panels put the
          // remaining traffic or the days left into a link's name, which
          // changes it on every refresh, while the server, port, transport
          // and path stay.
          final connection = _connectionOf(node);
          if (connection != null && connections[connection] == 1) {
            return 'link:$connection';
          }
          if (node.tag.isNotEmpty && tags[node.tag] == 1) {
            return 'tag:${node.tag}';
          }
          return 'at:${node.position}';
        }()),
  ];
}
