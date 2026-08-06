# Attribution

Caelo is built on other people's work. This file records what came from where, so that
copyright holders are credited and license obligations stay traceable.

Every entry names the upstream project, its license, the exact commit or tag the material
came from, and what we changed. When code is copied into this tree, its original copyright
headers are preserved and an `SPDX-License-Identifier` line is added or kept.

## Dependencies

These are consumed as ordinary dependencies, not copied into this tree.

| Project | License | Version | Notes |
| --- | --- | --- | --- |
| [sing-box](https://github.com/SagerNet/sing-box) | GPL-3.0-or-later, with an additional §7 clause restricting use of the name and implied association | v1.13.16 | Imported as a Go module by `caelo-core`. No fork; Caelo registers its own protocol types through the public registry API. |
| [amneziawg-go](https://github.com/amnezia-vpn/amneziawg-go) | MIT | see `caelo-core/go.mod` | Source of the AmneziaWG obfuscation layer. |
| [wireguard-go](https://git.zx2c4.com/wireguard-go/) | MIT | via `sagernet/wireguard-go` | Upstream of both forks below. |

## Forks

| Fork | Upstream | Base | What we changed |
| --- | --- | --- | --- |
| _(pending)_ | [`sagernet/wireguard-go`](https://github.com/sagernet/wireguard-go) | _(pin the commit here when the fork is created)_ | AmneziaWG obfuscation ported from `amneziawg-go`, kept as separate commits behind a build tag so rebases onto upstream stay mechanical. |

## Copied material

None yet. Anything copied file-by-file gets a row here with the source path, the upstream
commit, and the license it arrived under.

## Projects we learned from but did not copy

[Hiddify](https://github.com/hiddify/hiddify-app) solved several of the same problems
first, and reading their code informed our own design — particularly the shape of a
core↔UI contract and the ergonomics of subscription handling.

**No Hiddify code, configuration, `.proto` definition or build script is used in Caelo.**
Hiddify is distributed under GPLv3 with additional §7 conditions that include a
non-commercial restriction and a requirement that derivative repositories be GitHub forks
of theirs. Those terms are incompatible with shipping Caelo as free software under a plain
GPLv3, so we reimplemented from our own understanding rather than reusing their material.

If you contribute, the same applies: study anything you like, copy nothing.

## Third-party licenses

The full dependency license inventory is generated during release rather than maintained
by hand. See `THIRD_PARTY_LICENSES.md` in the release artifacts.
