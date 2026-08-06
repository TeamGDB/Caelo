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
| `internal/tunnel` | A tunnel that stays up, for the app to drive |
| `internal/system` | Taking over the machine's routing and DNS, and putting them back |
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

This is the hands-on path. For the app to do the same thing from its button, see the
helper below. What ships is a NetworkExtension — a user-facing application has no business
asking anyone to type `sudo`.

## caelo-helper

The privileged half, so the app's button can route the whole machine without the app
itself ever running as root.

```bash
make helper
sudo ./deploy/macos/install-helper.sh install
```

It installs as a launchd daemon and listens on `/var/run/caelo-helper.sock`. Remove it
with `sudo ./deploy/macos/install-helper.sh uninstall`; routing is restored as it stops.

The helper runs as root, so what matters is what it refuses:

- **One user.** The uid allowed to talk to it is fixed at install time — whoever ran the
  installer. It refuses to start at all without one, because defaulting to "anyone" would
  hand root to every process on the machine and would work, so nobody would notice.
- **Asked, not told.** The peer's uid comes from the kernel via `LOCAL_PEERCRED`, not from
  anything the caller sends, so a caller cannot claim to be someone else. The socket is
  also `0600` and owned by that user: permissions stop the connection being made, the
  credential check stops it being served.
- **Configuration by value, not by path.** `connect` carries the `.conf` over the socket.
  Handing a root process a filename would turn `connect` into "read any file on this
  machine".
- **Four commands.** `connect`, `disconnect`, `status`, `version`. Anything else is refused
  without a hint as to what would have worked.
- **Root-owned binary**, mode `544`. A helper its own user could overwrite would be a way
  to *become* root rather than a way to avoid asking for it.

The tunnel belongs to the helper, not to the app. Quitting Caelo does not drop it, and a
crash does not leave the machine routed through an interface nobody is holding open. The
app asks on launch what is already up rather than assuming.

None of this makes a resident root daemon free. It is the reason the NetworkExtension is
the destination and this is the way station.

## Building and testing

```bash
go test ./...
```

## Licence

GPL-3.0-or-later. See [LICENSE](LICENSE).
