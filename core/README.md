# core

The engine behind Caelo: the tunnel, subscriptions, node selection, connection state,
statistics, scheduling.

It is a Go module inside the application's repository rather than beside it. The FFI
surface between the two changes often enough that having to land it in two repositories,
in order, was the more expensive arrangement.

> **Status: early development.** The AmneziaWG transport works end to end. Nothing above
> it exists yet.

## Design

What lives here is everything about a configuration: what is in one, whether it carries
traffic, and how to raise it. One at a time.

What does not live here is subscriptions. A subscription is a way of delivering a document
— a link, a request, a refresh interval, a cached last-good copy, a remaining-traffic
header, several sources merged. A tunnel executes none of it, and the app is where the user
edits it, so that is where it belongs. Nor does the order in which nodes are tried: it
comes from the server, and a client that recomputed it would be guessing at something it
was told.

What must stay in one place is connection state, because state kept in two will eventually
disagree with itself about what is connected.

**Nothing will be forked.** [sing-box](https://github.com/SagerNet/sing-box) is to be
imported as an ordinary Go module, with Caelo registering its own protocol types through
its public registry.
AmneziaWG comes from [amneziawg-go](https://github.com/amnezia-vpn/amneziawg-go), also as
published. Upgrading either is a version bump. See
[ATTRIBUTION.md](ATTRIBUTION.md) for licences and
[the app's README](../README.md#architecture) for why the alternative —
forking `sagernet/wireguard-go` and porting the obfuscation in — was rejected.

Pinned versions:

| Dependency | Version |
| --- | --- |
| amneziawg-go | v3.0.20260805 |
| sing-box | v1.13.16 — added back to `go.mod` with the endpoint registration |

`go mod tidy` drops a module nothing imports, so sing-box is absent from `go.mod` until the
code that registers the `amneziawg` endpoint lands. Pinning a dependency the build does not
use would only record an intention that nothing verifies.

## Layout

| Path | What it is |
| --- | --- |
| `internal/awg` | AmneziaWG configuration: parsing `.conf`, rendering the device's UAPI form |
| `internal/tunnel` | A tunnel that stays up, for the app to drive |
| `internal/probe` | One tunnel on a userspace stack, one request through it, nothing on the host |
| `internal/system` | Taking over the machine's routing and DNS, and putting them back |
| `internal/systunnel` | A tunnel that carries the whole machine, for whoever holds the privilege |
| `internal/ipc` | The four commands the app may ask the privileged service for |
| `cmd/caelo-service` | The privileged half on Linux. Started by its socket, gone when idle |
| `cmd/caelo-probe` | Brings up one tunnel and makes one request through it |
| `cmd/caelo-tun` | Routes the whole machine through a tunnel. Needs root |
| `libcaelo` | The core as a C shared library, for the desktop apps |

## caelo-probe

The smallest thing that proves the transport works. It runs entirely in userspace on a
gVisor netstack, so it needs no privileges and creates no interface on the host — nothing
outside the process is routed through the tunnel.

```bash
go run ./cmd/caelo-probe -config /path/to/tunnel.conf
```

```
endpoint    203.0.113.10:45330
address     [10.8.1.23]
mtu         1376
obfuscation jc=6 jmin=10 jmax=50 s1=112 s2=70 s3=33 s4=9
signatures  i1 (310 bytes of chain)

https://ifconfig.me/ip → 200 OK in 7.3s
203.0.113.10
```

If the address it prints is the endpoint's rather than yours, traffic went through the
tunnel. Add `-v` to watch the handshake.

The same thing is available to the app as `caelo_probe(config, url, timeoutMs)`. That is
how a list of candidates is worked down: connecting each one for real to find out would
raise and drop a *system* tunnel per candidate, which on iOS and Android restarts the
tunnel extension and drops every connection on the device each time round. It is also a
stronger answer than a ping — a server can answer ICMP and still refuse the handshake, and
an obfuscated endpoint is supposed to ignore anything that is not the right first packet.
Only a reply that came back through the tunnel proves the node works.

The server list uses the separate
`caelo_measure_latency(config, url, timeoutMs)` call. It performs the same
proving request first and then reports a second, warm HTTPS round trip as
`latency_ms`. This deliberately is not called ICMP ping: the value describes
real traffic through an established AmneziaWG/WireGuard tunnel, while
`caelo_probe.elapsed_ms` keeps its original cold availability semantics.

Junk packets, header magic ranges and signature packets are passed to the device layer as
the strings they arrived as. That grammar already has one implementation and does not need
a second one here to disagree with it.

**Never point this at a config you care about keeping private from your shell history, and
never commit one.** Keep real configs outside the working tree.

## caelo-tun

The same tunnel, but on a real `utun` interface with the default route pointed at it, so
every application on the machine goes through it. This needs root.

```bash
make tun
sudo ./build/caelo-tun -config /path/to/tunnel.conf -duration 60s
```

Use `-duration` while developing. The tunnel tears itself down after that long whatever
else happens, so a mistake costs you a minute rather than your network. Without it, the
tunnel runs until Ctrl-C.

What it changes, and puts back on exit — including on Ctrl-C and SIGTERM:

- creates a `utun` interface with the tunnel's address and MTU;
- pins a host route to the endpoint via the original gateway, so the tunnel's own packets
  do not get routed into the tunnel;
- adds `0.0.0.0/1` and `128.0.0.0/1` pointing at the interface. Two halves rather than
  overwriting the default route: they are more specific, so they win while they exist and
  leave nothing to rebuild when they go;
- sets DNS on the active network service;
- **switches IPv6 off.** This configuration has no v6 address inside the tunnel, so v6
  traffic would leave outside it. A tunnel that quietly carries half your traffic in the
  clear is worse than no tunnel, because you would not think to check.

If restoring fails it says so loudly and names what did not come back, because someone
whose network is broken needs to know what to undo by hand.

This is the hands-on path, and the only one: what ships is a NetworkExtension, where the
system owns the tunnel and no part of Caelo runs as root at all. A user-facing application
has no business asking anyone to type `sudo`.

## Building and testing

```bash
go test ./...
```

## Licence

GPL-3.0-or-later. See [LICENSE](LICENSE).
