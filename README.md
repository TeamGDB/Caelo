# caelo-core

The engine behind [Caelo](https://github.com/TeamGDB/Caelo): subscriptions, node
selection, connection state, statistics, scheduling.

> **Status: early development.** The AmneziaWG transport works end to end. Nothing above
> it exists yet.

## Design

Everything that decides anything lives here. The app is a list, a button and a settings
screen; it asks the core to connect and is told what happened. Any logic that exists in
both places is logic that will eventually disagree with itself about what is connected.

**Nothing is forked.** [sing-box](https://github.com/SagerNet/sing-box) is imported as an
ordinary Go module and Caelo registers its own protocol types through its public registry.
AmneziaWG comes from [amneziawg-go](https://github.com/amnezia-vpn/amneziawg-go), also as
published. Upgrading either is a version bump. See
[ATTRIBUTION.md](ATTRIBUTION.md) for licences and
[the app's README](https://github.com/TeamGDB/Caelo#architecture) for why the alternative —
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
| `cmd/caelo-probe` | Brings up one tunnel and makes one request through it |

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

Junk packets, header magic ranges and signature packets are passed to the device layer as
the strings they arrived as. That grammar already has one implementation and does not need
a second one here to disagree with it.

**Never point this at a config you care about keeping private from your shell history, and
never commit one.** Keep real configs outside the working tree.

## Building and testing

```bash
go test ./...
```

## Licence

GPL-3.0-or-later. See [LICENSE](LICENSE).
