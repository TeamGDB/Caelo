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
      "expires": "2030-01-01T00:00:00Z",
      "quota_bytes": 107374182400,
      "used_bytes": 44040192,
      "nodes": ["first", "second"]
    }
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

echo "==> fetching"
curl -fsS -D "$WORK/headers" -o "$WORK/document.json" "http://127.0.0.1:$PORT/sub/$TOKEN"

echo "==> headers"
grep -i -E 'subscription-userinfo|profile-update-interval' "$WORK/headers" | sed 's/^/    /'
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
  final client = HttpClient();
  final request = await client.getUrl(Uri.parse(arguments.first));
  final response = await request.close();
  final body = await response.transform(utf8.decoder).join();

  final usage = SubscriptionUsage.parse(
    response.headers.value('subscription-userinfo'),
  );
  final interval = response.headers.value('profile-update-interval');
  final nodes = readNodes(body);

  stdout.writeln('nodes    ${nodes.map((n) => "${n.position}:${n.tag}").join(", ")}');
  stdout.writeln('used     ${usage.usedBytes} of ${usage.totalBytes}');
  stdout.writeln('left     ${usage.remainingBytes}');
  stdout.writeln('expires  ${usage.expires}');
  stdout.writeln('interval ${interval}h');

  // The endpoint has to survive the app untouched: it is what reaches the core,
  // and eventually a process running as root.
  final carried = jsonDecode(nodes.first.endpoint) as Map<String, dynamic>;
  if (carried['private_key'] == null) {
    stderr.writeln('the app lost a field it was carrying');
    exit(1);
  }
  client.close();
}
DART
  cp "$ROOT/lib/core/subscription.dart" "$WORK/subscription.dart"
  dart run "$WORK/read.dart" "http://127.0.0.1:$PORT/sub/$TOKEN" | sed 's/^/    /'
else
  echo "!! no dart on PATH; skipped the app's half" >&2
fi

echo "==> the client understood everything the server served"
