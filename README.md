# Caelo

A VPN client for subscription links. Paste a link — it works.

No accounts, no ads, no telemetry. Free software under the GPLv3.

> **Status: early development.** Nothing here is usable yet. There are no releases.

## What it is

Caelo speaks [AmneziaWG](https://docs.amnezia.org/documentation/amnezia-wg/) with the
full obfuscation parameter set (`Jc`/`Jmin`/`Jmax`, `S1`–`S4`, `H1`–`H4`, and AWG 2.0
signature packets `I1`–`I5`), plus VLESS/REALITY and whatever else comes along for the
ride from sing-box. Which protocol you end up on is not a question the app asks you.

## Layout

| Path | What it holds |
| --- | --- |
| `lib/`, `macos/`, `android/` | The app. Flutter interface, platform runners, builds, releases. |
| [`core/`](core) | The Go core: the tunnel, subscriptions, node selection, state, statistics. |

The core lived in its own repository until it did not earn the split. Two
repositories meant a deploy key, a cross-repo checkout, and a build that could
produce an app with no core in it; one means neither can drift from the other
and a single commit can change both sides of the FFI boundary at once.

## Architecture

All the logic lives in the Go core: subscription parsing and refresh, node probing and
selection, connection state, statistics, scheduling. The Flutter front end is deliberately
thin — a list, a button, a settings screen — and talks to the core over gRPC, subscribing
to state changes rather than polling.

**Caelo forks nothing.** sing-box exposes a public protocol registry, so the core imports
it as an ordinary Go module and registers its own `amneziawg` endpoint from its own tree.
AmneziaWG comes from `amneziawg-go`, also as an ordinary module. Both upstreams are
upgraded by bumping a version, and there is no patch series to rebase.

The alternative was forking `sagernet/wireguard-go` and porting the obfuscation into it.
Measured against their common upstream, that fork and `amneziawg-go` have diverged by
comparable amounts — roughly 1700 and 1800 substantive lines — so reconciling them is real
work in either direction, and it would be work we redo on every AmneziaWG release.
`amneziawg-go` also keeps upstream's `NewDevice` and `NewStdNetBind` signatures, where
SagerNet's fork couples them to sing-box's own service and pause machinery. AmneziaWG is
the reason this project exists, so it is the dependency that stays fresh.

What that costs us is the plumbing SagerNet's fork provided: a `conn.Bind` and a netstack
`tun.Device`. Both live in `core/` as our own code, under our own tests.

Pinned versions:

| Dependency | Version |
| --- | --- |
| sing-box | v1.13.16 |
| amneziawg-go | v3.0.20260805 |

## Platforms

macOS first, iOS second (sharing the same NetworkExtension), then Windows, Linux and
Android. Distribution is via GitHub Releases; macOS builds are signed with a Developer ID
and notarized.

## Building

One script per platform. Each builds the core first, puts it where that platform's loader
will find it, and then builds the app.

```bash
./scripts/build-macos.sh debug     # universal dylib in Contents/Frameworks
./scripts/build-android.sh debug   # one .so per ABI, packed into the APK
./scripts/build-ios.sh release     # static xcframework linked into the binary
./scripts/build-linux.sh debug     # .so in the bundle's lib/
./scripts/build-windows.sh debug   # .dll beside the executable
```

Android needs an NDK; the script finds one under the SDK Flutter already knows about, or
takes `ANDROID_NDK_HOME`. iOS debug builds use a JIT and will not launch without the
tooling attached, so release is the default there.

Any of them can be run without a core — `flutter build <platform>` on its own still builds
the interface. The app then reports that the core is not there rather than pretending
otherwise.

## Packaging

`packaging/` turns a build into the shapes people install. The Package workflow runs all of
it on every dispatch, so the packaging is exercised continuously rather than discovered to
be broken on the day of a release.

| Platform | Formats |
| --- | --- |
| Android | one APK per ABI, a universal APK for sideloading, and an `.aab` |
| Linux | `.tar.gz`, `.deb`, `.rpm`, AppImage |
| macOS | `.dmg`, `.pkg` |
| Windows | portable `.zip`, Inno Setup installer |

Four Linux formats because "Linux" is not one thing: Debian and Fedora each want their own,
the AppImage runs where neither is wanted, and the tarball is for people who would rather
unpack it themselves.

Nothing produced there is signed or notarised. That belongs with the signing identity and
comes with the first real release; an unsigned build must never be handed out as one.

Both scripts build the core from `core/` first, so a clean checkout is all either needs.

## License

GPL-3.0-or-later. See [LICENSE](LICENSE).

Caelo builds on [sing-box](https://github.com/SagerNet/sing-box) and
[AmneziaWG](https://github.com/amnezia-vpn/amneziawg-go); see [ATTRIBUTION.md](ATTRIBUTION.md)
for what came from where. Neither project endorses Caelo or is affiliated with it.

## Security

Found a vulnerability? Please read [SECURITY.md](SECURITY.md) — do not open a public issue.
