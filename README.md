# Caelo

A VPN client for subscription links. Paste a link — it works.

No accounts, no ads, no telemetry. Free software under the GPLv3.

> **Status: early development.** Nothing here is usable yet. There are no releases.

## What it is

Caelo speaks [AmneziaWG](https://docs.amnezia.org/documentation/amnezia-wg/) with the
full obfuscation parameter set (`Jc`/`Jmin`/`Jmax`, `S1`–`S4`, `H1`–`H4`, and AWG 2.0
signature packets `I1`–`I5`), plus VLESS/REALITY and whatever else comes along for the
ride from sing-box. Which protocol you end up on is not a question the app asks you.

## Repositories

| Repository | What it holds |
| --- | --- |
| [`TeamGDB/Caelo`](https://github.com/TeamGDB/Caelo) | This one — the app. Flutter UI, platform runners, builds, releases. |
| [`TeamGDB/caelo-core`](https://github.com/TeamGDB/caelo-core) | The Go core: subscriptions, node selection, state, statistics. |

## Architecture

All the logic lives in the Go core: subscription parsing and refresh, node probing and
selection, connection state, statistics, scheduling. The Flutter front end is deliberately
thin — a list, a button, a settings screen — and talks to the core over gRPC, subscribing
to state changes rather than polling.

The core does **not** fork sing-box. sing-box exposes a public protocol registry, so Caelo
imports it as an ordinary Go module and registers its own `amneziawg` endpoint type from
its own tree. Upgrading sing-box is a version bump, not a rebase.

sing-box is pinned to **v1.13.16**.

The one fork we do carry is of `sagernet/wireguard-go`, because AmneziaWG's obfuscation
lives in the WireGuard device layer and cannot be added from outside it. That fork tracks
upstream with the obfuscation patch kept as separate commits so rebasing stays mechanical.

## Platforms

macOS first, iOS second (sharing the same NetworkExtension), then Windows, Linux and
Android. Distribution is via GitHub Releases; macOS builds are signed with a Developer ID
and notarized.

## Building

Not yet documented — there is nothing to build. This section lands with the first working
core.

## License

GPL-3.0-or-later. See [LICENSE](LICENSE).

Caelo builds on [sing-box](https://github.com/SagerNet/sing-box) and
[AmneziaWG](https://github.com/amnezia-vpn/amneziawg-go); see [ATTRIBUTION.md](ATTRIBUTION.md)
for what came from where. Neither project endorses Caelo or is affiliated with it.

## Security

Found a vulnerability? Please read [SECURITY.md](SECURITY.md) — do not open a public issue.
