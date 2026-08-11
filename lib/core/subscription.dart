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
    required this.tag,
    required this.endpoint,
    required this.position,
  });

  /// What to call it. May be empty: a server is not obliged to name its nodes,
  /// and the interface can fall back to the position.
  final String tag;

  /// The endpoint object, as served. Handed to the core unchanged.
  final String endpoint;

  /// Where it came in the list. The order *is* the priority — the server
  /// decided it, and recomputing it here would be overriding a decision we were
  /// told rather than making one.
  final int position;

  Map<String, dynamic> toJson() => {
    'tag': tag,
    'endpoint': endpoint,
    'position': position,
  };

  static SubscriptionNode fromJson(Map<String, dynamic> json) =>
      SubscriptionNode(
        tag: json['tag'] as String? ?? '',
        endpoint: json['endpoint'] as String? ?? '',
        position: json['position'] as int? ?? 0,
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
    this.pinnedTag,
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

  /// A node the person chose by hand.
  ///
  /// Held by tag rather than by position, because a refresh reorders. It
  /// survives an update if the tag is still there and is silently forgotten if
  /// it is not — a pin to a node the server has withdrawn is a pin to nothing.
  final String? pinnedTag;

  bool get hasNodes => nodes.isNotEmpty;

  /// The node to try first: whatever was pinned, then the server's order.
  SubscriptionNode? get preferred {
    if (nodes.isEmpty) return null;
    final pinned = pinnedTag;
    if (pinned != null) {
      for (final node in nodes) {
        if (node.tag == pinned) return node;
      }
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
    final pinned = preferred;
    if (pinned == null || pinned == nodes.first) return nodes;
    return [pinned, ...nodes.where((node) => node != pinned)];
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

  Subscription copyWith({
    String? name,
    List<SubscriptionNode>? nodes,
    SubscriptionUsage? usage,
    Duration? updateInterval,
    DateTime? lastFetched,
    String? lastError,
    bool clearError = false,
    String? pinnedTag,
    bool clearPin = false,
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
      pinnedTag: clearPin ? null : (pinnedTag ?? this.pinnedTag),
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
    if (pinnedTag != null) 'pinnedTag': pinnedTag,
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
      pinnedTag: json['pinnedTag'] as String?,
    );
  }
}

/// Reads the node list out of a subscription document.
///
/// Only the list: which nodes there are, what they are called, and what order
/// they came in. Each endpoint is re-encoded and carried as text, so that
/// nothing here has to know what is inside one.
List<SubscriptionNode> readNodes(String body) {
  final decoded = jsonDecode(body);
  if (decoded is! Map<String, dynamic>) {
    throw const FormatException('the document is not a JSON object');
  }

  final endpoints = decoded['endpoints'];
  if (endpoints is! List) {
    throw const FormatException('the document has no endpoints');
  }

  final nodes = <SubscriptionNode>[];
  for (var index = 0; index < endpoints.length; index++) {
    final endpoint = endpoints[index];
    if (endpoint is! Map<String, dynamic>) continue;

    // Everything that is not AmneziaWG is skipped rather than refused. A
    // subscription that also carries protocols this build cannot run is a
    // subscription whose AmneziaWG nodes still work, and refusing the document
    // would take those away too.
    final type = endpoint['type'];
    if (type != null && type != 'amneziawg') continue;

    nodes.add(
      SubscriptionNode(
        tag: endpoint['tag'] as String? ?? '',
        endpoint: jsonEncode(endpoint),
        position: index,
      ),
    );
  }

  if (nodes.isEmpty) {
    throw const FormatException('the document has no nodes this build can use');
  }
  return nodes;
}
