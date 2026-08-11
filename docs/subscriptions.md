# Subscriptions

A subscription is a URL that returns a list of nodes. Paste it once and the client keeps
it current; that is the whole product, and this is the contract both halves of it speak.

Written for two audiences: whoever implements a server, and whoever changes the client
and needs to know what they may not break. The example in
[`examples/subscription-server`](../examples/subscription-server) is this document in
Go — it imports nothing of Caelo's, because anybody implementing this will write their
own types in whatever language their service is in.

## The request

```
GET https://example.com/sub/<token>
```

The token is the whole credential, and a server that needs more than one round trip to
answer is a server that will be slow on the network these users are on.

The client sends two headers:

```
User-Agent: Caelo/<version>
Accept: application/vnd.caelo.subscription+json, application/json
```

Servers that vary their answer by client are the reason the first exists; servers that
reject unfamiliar ones break for every client but the two they tested.

The second is how a server offers more than the plain document without breaking anyone.
A server that understands it may answer with the [Caelo document](#the-caelo-document);
one that does not answers with plain sing-box JSON and everything still works. **The
client decides which it got by the response's `Content-Type`, not by what it asked for**,
so a server may ignore the header entirely.

## The response

Plain [sing-box](https://sing-box.sagernet.org) JSON, `Content-Type: application/json`.

```json
{
  "endpoints": [
    {
      "type": "amneziawg",
      "tag": "Frankfurt",
      "address": ["10.8.1.23/32"],
      "private_key": "yBk…=",
      "mtu": 1376,
      "dns": ["1.1.1.1"],
      "peers": [
        {
          "address": "203.0.113.10",
          "port": 45330,
          "public_key": "Kx1…=",
          "pre_shared_key": "9pQ…=",
          "allowed_ips": ["0.0.0.0/0"],
          "persistent_keepalive_interval": 25
        }
      ],
      "jc": 6, "jmin": 10, "jmax": 50,
      "s1": 112, "s2": 70, "s3": 33, "s4": 9,
      "h1": "1148446321",
      "i1": "<b 0xc0de>"
    }
  ]
}
```

**There is no Caelo extension anywhere in this document, and there will not be.**
sing-box decodes its configuration with `DisallowUnknownFields`, so a block beside
`endpoints` would make the document invalid sing-box JSON — which is the one property
the canonical format was chosen for. Everything the client needs is already expressible:

| What | Where |
| --- | --- |
| Which node to try first | The order of `endpoints`. First is first. |
| What to call a node | Its `tag` |
| Traffic used and left, expiry | The `subscription-userinfo` response header |
| How often to come back | The `profile-update-interval` response header |

### The AmneziaWG endpoint

sing-box's WireGuard endpoint, field for field, plus the obfuscation set. When the type
is registered with sing-box's endpoint registry, that registration will describe what is
already being served rather than change it.

`peers` is a list because sing-box's is. AmneziaWG describes exactly one, and the client
refuses a document that carries more rather than silently using the first.

Keys are base64, as in a `.conf`. `address` carries a prefix length; the client drops it,
because a tunnel address is a host address whatever the notation says.

Obfuscation values may be written as numbers or as strings — `"jc": 6` and `"jc": "6"`
are the same thing. `jc`, `jmin`, `jmax` and `s1`–`s4` are counts; `h1`–`h4` may be
ranges and `i1`–`i5` are packet descriptions, and all of them reach the device layer as
text regardless. A server's choice of quoting should not decide whether a tunnel comes
up.

Omit what does not apply. A node with no obfuscation fields is plain WireGuard and works.

## The Caelo document

Optional, and only what the plain document cannot carry: an identity for each node, and
what to show about it.

```
Content-Type: application/vnd.caelo.subscription+json
```

```json
{
  "version": 1,
  "nodes": [
    {
      "id": "fra-01",
      "country": "DE",
      "description": "Best for video",
      "maintenance": false,
      "endpoint": { "type": "amneziawg", "tag": "Frankfurt", "…": "…" }
    }
  ]
}
```

Each node carries its own endpoint. The alternative — a table of metadata beside the
`endpoints` array — needs a key to join them on, and the only candidate is the `tag`,
which is exactly the unreliable thing an identity is being added to replace.

| Field | |
| --- | --- |
| `version` | This document's shape. `1` today. A client that does not know a version reads the endpoints and ignores everything else, rather than refusing a subscription over a field it did not recognise. |
| `id` | **Stable for the same node across refreshes.** Not the tag, not the position: both change. This is what a client's "use this one" is remembered by, and a server that renumbers them will silently unpin everybody. |
| `country` | ISO 3166-1 alpha-2, uppercase. A flag is built from it by the client; sending an emoji is sending a picture that a client cannot sort by. |
| `description` | One short line, in the subscriber's language if the server knows it. Not a place for terms of service. |
| `maintenance` | The server saying "not this one, for now". The client skips it when choosing and may still show it, greyed. Absent means usable. |
| `endpoint` | The same object the plain document carries, unchanged. |

Everything except `endpoint` is optional.

**Order still decides priority**, here as in the plain document.

**Latency is never sent.** It depends on where the client is standing, and a number
measured somewhere else is worse than no number: it looks authoritative and is not. The
client measures for itself, by probing.

### Identity without the Caelo document

A plain sing-box subscription has no identity to give. The client makes one, in this
order, and the rule is written down because it decides whose choice survives a refresh:

1. the `id` from the Caelo document;
2. otherwise the `tag`, if it is not empty and no other node in the document shares it;
3. otherwise the position, which is stable only until the server reorders.

A node manually chosen under rule 3 loses that choice when the list is reordered. That is
a real limitation of plain subscriptions rather than something the client can fix, and
it is the reason the Caelo document exists.

### Headers

```
subscription-userinfo: upload=0; download=44040192; total=107374182400; expire=1798761600
profile-update-interval: 12
```

Both are the conventions the V2Ray and Clash ecosystems already use, followed rather
than reinvented so that a Caelo subscription can be read by other clients and a
subscription written for them can be read by Caelo. Bytes for the counters, Unix seconds
for `expire`, hours for the interval. Any field may be absent; `expire=0` means no
expiry.

## What the client does with it

**Order is obeyed, not recalculated.** The server knows which node it wants used; a
client that re-sorts by its own measurements is overriding a decision it was told. The
client works down the list and stops at the first node that carries traffic.

**Candidates are probed, not connected.** `caelo_probe` brings one node up on a
userspace stack inside the app's own process — no interface, no routes, nothing else on
the machine touched — so working down a list does not raise and drop a system tunnel per
candidate. On iOS and Android that would restart the tunnel extension and drop every
connection on the device, once per candidate.

**The last answer that worked is kept.** A subscription that is unreachable, or that
answers with something unparseable, leaves the previous list in place and the client
keeps working. Whatever else is failing, the VPN is what someone is trying to use to fix
it.

**Local choices survive an update.** A node the user picked by hand stays picked if it is
still in the list; nothing the server sends silently overrides a decision the person made.

## Revocation

Stop serving the token: return `404` or `403`, and the client reports the subscription as
gone rather than as a network error.

Revocation of a *node* is removing it from the list, but that only takes effect when the
client next refreshes and cannot interrupt a tunnel already up. Anything stronger has to
happen on the server: rotate the peer's key, or stop accepting the handshake. A
subscription format cannot revoke access to a server that is still willing to talk.

## For whoever writes a server

The token is a bearer credential in a URL. URLs end up in shell history, in browser
history, in screenshots, and in the logs of any proxy in front of the server.

- Serve over HTTPS only. The document contains private keys.
- Make tokens long and random. There is no second factor here.
- Do not log the query string or the path.
- Rate-limit by token. A token that is being enumerated looks exactly like a token that
  is being used.
- Return the same `404` for an unknown token as for a revoked one. The difference is
  information nobody outside the service needs.

## For whoever changes the client

What arrives here is a document from outside that produces a configuration a privileged
process will act on. Two rules follow, and neither is optional:

- **The app never parses a configuration.** It reads the list, its order and the tags,
  and hands one endpoint object to the core. Everything about what a node *is* — keys,
  addresses, MTU, obfuscation — belongs to the core, next to the code that dials with it.
  A second implementation in Dart would eventually disagree with the one that connects,
  and only one of the two would be tested.
- **The privileged half treats what arrives as hostile.** `caelo_describe` before
  `caelo_connect` is where a document gets checked, and the service parses rather than
  trusts. It is a root process reading input that came from a link somebody was sent.
