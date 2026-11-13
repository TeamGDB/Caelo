#!/usr/bin/env bash
#
# Serves a subscription and hands it to the client's own reader.
#
#   ./examples/subscription-server/conformance.sh
#
# The example declares its own structs rather than importing the client's,
# because anyone implementing this contract will write their own in whatever
# language their service is in. That freedom is what this script pays for: the
# two sides are kept honest by running them against each other rather than by
# sharing a type, which tests the behaviour instead of the shape.
#
# Needs a Go toolchain and curl. It dials nothing: caelo-probe -check reads a
# configuration and describes it, so no server and no network are involved.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
WORK="$(mktemp -d)"
PORT="${PORT:-18080}"
TOKEN="conformance-token-long-enough-to-be-accepted"

cleanup() {
  [[ -n "${SERVER:-}" ]] && kill "$SERVER" 2>/dev/null || true
  rm -rf "$WORK"
}
trap cleanup EXIT

# Keys that are the right shape and no use to anybody: 32 bytes of one value,
# base64. A conformance check should never want a real one.
key() { python3 -c "import base64,sys; print(base64.b64encode(bytes([int(sys.argv[1])]*32)).decode())" "$1"; }

cat > "$WORK/nodes.json" <<JSON
{
  "update_interval_hours": 12,
  "subscribers": {
    "$TOKEN": {
      "title": "Дом",
      "expires": "2030-01-01T00:00:00Z",
      "quota_bytes": 107374182400,
      "used_bytes": 44040192,
      "nodes": ["first", "second", "third"]
    }
  },
  "meta": {
    "first":  { "country": "DE", "description": "Best for video" },
    "second": { "country": "NL", "maintenance": true },
    "third":  { "country": "CH", "description": "Example connection" }
  },
  "links": {
    "third": "vless://00000000-0000-4000-8000-000000000001@192.0.2.10:443?encryption=none&type=tcp&headerType=none&flow=xtls-rprx-vision&security=reality&sni=edge.example.com&pbk=AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8&sid=0123456789abcdef&fp=safari#Example%20Vision"
  },
  "nodes": {
    "first": {
      "tag": "First",
      "address": ["10.8.1.23/32"],
      "private_key": "$(key 1)",
      "mtu": 1376,
      "dns": ["1.1.1.1"],
      "peers": [{
        "address": "203.0.113.10",
        "port": 45330,
        "public_key": "$(key 2)",
        "pre_shared_key": "$(key 3)",
        "allowed_ips": ["0.0.0.0/0"],
        "persistent_keepalive_interval": 25
      }],
      "jc": 6, "jmin": 10, "jmax": 50,
      "s1": 112, "s2": 70, "s3": 33, "s4": 9,
      "h1": "1148446321",
      "i1": "<b 0xc0de>"
    },
    "second": {
      "tag": "Second",
      "address": ["10.8.2.23/32"],
      "private_key": "$(key 4)",
      "peers": [{
        "address": "203.0.113.20",
        "port": 45330,
        "public_key": "$(key 5)"
      }]
    }
  }
}
JSON

echo "==> starting the example server"
# Built rather than `go run`, so that the pid this script holds is the server's
# and not a wrapper's: killing the wrapper leaves the server running, holding
# whatever this script's output is piped into and never letting it close.
(cd "$HERE" && go build -o "$WORK/server" .)
"$WORK/server" -config "$WORK/nodes.json" -listen "127.0.0.1:$PORT" >"$WORK/server.log" 2>&1 &
SERVER=$!
for _ in $(seq 1 50); do
  curl -fsS -o /dev/null "http://127.0.0.1:$PORT/sub/$TOKEN" 2>/dev/null && break
  sleep 0.2
done

echo "==> fetching the plain document"
curl -fsS -D "$WORK/headers" -o "$WORK/document.json" "http://127.0.0.1:$PORT/sub/$TOKEN"
grep -qi 'content-type: application/json' "$WORK/headers" \
  || { echo "!! a client that did not ask should get plain sing-box JSON" >&2; exit 1; }

echo "==> and the Caelo document"
curl -fsS -H 'Accept: application/vnd.caelo.subscription+json, application/json' \
  -D "$WORK/caelo-headers" -o "$WORK/caelo.json" "http://127.0.0.1:$PORT/sub/$TOKEN"
grep -qi 'content-type: application/vnd.caelo.subscription' "$WORK/caelo-headers" \
  || { echo "!! asking for the richer document got the plain one" >&2; exit 1; }
python3 -c '
import json, sys
document = json.load(open(sys.argv[1]))
nodes = document["nodes"]
assert document["version"] == 1, "the version has to be stated"
for node in nodes:
    assert node["id"], "every node needs an identity"
    assert "endpoint" in node, "every node carries its own endpoint"
print("    version %d, ids: %s" % (document["version"], ", ".join(n["id"] for n in nodes)))
' "$WORK/caelo.json"

echo "==> version 2, to a client that says it runs VLESS"
curl -fsS -H 'Accept: application/vnd.caelo.subscription+json;version=2, application/vnd.caelo.subscription+json;q=0.9, application/json;q=0.8, text/plain;q=0.7' \
  -H 'X-Caelo-Capabilities: subscription-v2, vless-reality-vision' \
  -D "$WORK/v2-headers" -o "$WORK/v2.json" "http://127.0.0.1:$PORT/sub/$TOKEN"
python3 -c '
import json, sys
document = json.load(open(sys.argv[1]))
assert document["version"] == 2, "a client that asked for version 2 should get it"
kinds = ["uri" if "uri" in n else "endpoint" for n in document["nodes"]]
assert kinds == ["endpoint", "endpoint", "uri"], kinds
assert document["nodes"][2]["protocol"] == "vless"
print("    ids: %s" % ", ".join(n["id"] for n in document["nodes"]))
' "$WORK/v2.json"
python3 -c '
import json, sys
document = json.load(open(sys.argv[1]))
assert all("endpoint" in n for n in document["nodes"]), "version 1 must carry no links"
' "$WORK/caelo.json"

echo "==> a client that runs other variants gets none of these links"
curl -fsS -H 'Accept: application/vnd.caelo.subscription+json;version=2' \
  -H 'X-Caelo-Capabilities: subscription-v2, vless-tls-xhttp' -o "$WORK/v2-other.json" "http://127.0.0.1:$PORT/sub/$TOKEN"
python3 -c '
import json, sys
assert all("endpoint" in n for n in json.load(open(sys.argv[1]))["nodes"])
' "$WORK/v2-other.json"

echo "==> and the plain list another client reads"
curl -fsS -H 'Accept: text/plain' -D "$WORK/links-headers" -o "$WORK/links.b64" "http://127.0.0.1:$PORT/sub/$TOKEN"
grep -qi 'content-type: text/plain' "$WORK/links-headers" \
  || { echo "!! another client should get the list of links" >&2; exit 1; }
python3 -c 'import base64,sys; open(sys.argv[2],"w").write(base64.b64decode(open(sys.argv[1]).read()).decode())' "$WORK/links.b64" "$WORK/links.txt"
while IFS= read -r link; do
  [[ -z "$link" ]] && continue
  printf '%s' "$link" > "$WORK/link.txt"
  echo "--- ${link##*#}"
  (cd "$ROOT/core" && go run ./cmd/caelo-probe -check -config "$WORK/link.txt") | sed 's/^/    /'
done < "$WORK/links.txt"

echo "==> headers"
grep -i -E 'subscription-userinfo|profile-update-interval|profile-title' "$WORK/headers" | sed 's/^/    /'
grep -qi 'subscription-userinfo' "$WORK/headers" \
  || { echo "!! no subscription-userinfo: the client cannot show quota or expiry" >&2; exit 1; }
grep -qi 'profile-update-interval' "$WORK/headers" \
  || { echo "!! no profile-update-interval: the client cannot know when to come back" >&2; exit 1; }

echo "==> an unknown token"
code="$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:$PORT/sub/not-a-real-token-but-long-enough")"
[[ "$code" == "404" ]] || { echo "!! an unknown token answered $code, not 404" >&2; exit 1; }

# Order is the contract's only expression of priority, so the check reads the
# array in order rather than by tag, exactly as the client does.
count="$(python3 -c 'import json,sys; print(len(json.load(open(sys.argv[1]))["endpoints"]))' "$WORK/document.json")"
echo "==> $count endpoints, read in the order they were served"

for index in $(seq 0 $((count - 1))); do
  python3 -c '
import json, sys
document = json.load(open(sys.argv[1]))
json.dump(document["endpoints"][int(sys.argv[2])], open(sys.argv[3], "w"))
' "$WORK/document.json" "$index" "$WORK/endpoint.json"

  tag="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("tag",""))' "$WORK/endpoint.json")"
  echo "--- [$index] $tag"
  (cd "$ROOT/core" && go run ./cmd/caelo-probe -check -config "$WORK/endpoint.json") | sed 's/^/    /'
done

# The app has a reader of its own, and it reads a different thing: the list,
# its order and the names, never what is inside an endpoint. Both halves of the
# client are checked here because a document the core can dial through is no
# use if the app cannot find it in the list.
if command -v dart >/dev/null; then
  echo "==> and the app's reader"
  cat > "$WORK/read.dart" <<'DART'
import 'dart:convert';
import 'dart:io';

import 'subscription.dart';

Future<void> main(List<String> arguments) async {
  final as = arguments.length > 1 ? arguments[1] : 'plain';
  final wantsCaelo = as != 'plain';

  final client = HttpClient();
  final request = await client.getUrl(Uri.parse(arguments.first));
  if (as == 'caelo') {
    request.headers.set('accept', '$caeloDocumentType, application/json');
  }
  if (as == 'v2') {
    request.headers.set('accept', '$caeloDocumentType;version=2, text/plain;q=0.7');
    request.headers.set('x-caelo-capabilities', 'subscription-v2, vless-reality-vision');
  }
  if (as == 'links') request.headers.set('accept', 'text/plain');
  final response = await request.close();
  final body = await response.transform(utf8.decoder).join();

  final usage = SubscriptionUsage.parse(
    response.headers.value('subscription-userinfo'),
  );
  final interval = response.headers.value('profile-update-interval');
  final nodes = readNodes(
    body,
    contentType: response.headers.contentType?.mimeType,
    protocols: const {'amneziawg', 'vless'},
  );

  stdout.writeln('as       $as');
  stdout.writeln('title    ${parseProfileTitle(response.headers.value('profile-title'))}');
  for (final each in nodes) {
    final about = [
      if (each.flag.isNotEmpty) each.flag,
      each.tag.isEmpty ? '(unnamed)' : each.tag,
      if (each.description.isNotEmpty) '— ${each.description}',
      if (each.maintenance) '[out of service]',
    ].join(' ');
    stdout.writeln('node     ${each.id.padRight(12)} ${each.protocol.padRight(9)} $about');
  }
  stdout.writeln('used     ${usage.usedBytes} of ${usage.totalBytes}');
  stdout.writeln('left     ${usage.remainingBytes}');
  stdout.writeln('expires  ${usage.expires}');
  stdout.writeln('interval ${interval}h');

  // The endpoint has to survive the app untouched: it is what reaches the core,
  // and eventually a process running as root.
  final first = nodes.first;
  if (first.protocol == 'amneziawg') {
    final carried = jsonDecode(first.endpoint) as Map<String, dynamic>;
    if (carried['private_key'] == null) {
      stderr.writeln('the app lost a field it was carrying');
      exit(1);
    }
  } else if (!first.endpoint.startsWith('vless://')) {
    stderr.writeln('the app rewrote a link it was carrying');
    exit(1);
  }
  if (wantsCaelo && as == 'v2' && nodes.length != 3) {
    stderr.writeln('version 2 should have carried three nodes');
    exit(1);
  }
  client.close();
}
DART
  cp "$ROOT/lib/core/subscription.dart" "$WORK/subscription.dart"
  dart run "$WORK/read.dart" "http://127.0.0.1:$PORT/sub/$TOKEN" plain | sed 's/^/    /'
  dart run "$WORK/read.dart" "http://127.0.0.1:$PORT/sub/$TOKEN" caelo | sed 's/^/    /'
  dart run "$WORK/read.dart" "http://127.0.0.1:$PORT/sub/$TOKEN" v2 | sed 's/^/    /'
  dart run "$WORK/read.dart" "http://127.0.0.1:$PORT/sub/$TOKEN" links | sed 's/^/    /'
else
  echo "!! no dart on PATH; skipped the app's half" >&2
fi

echo "==> the client understood everything the server served"
