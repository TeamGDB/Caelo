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
| [sing-box](https://github.com/SagerNet/sing-box) | GPL-3.0-or-later, with an additional §7 clause restricting use of the name and implied association | v1.13.16 | Imported as a Go module by the core. Caelo registers its own protocol types through the public registry API. |
| [amneziawg-go](https://github.com/amnezia-vpn/amneziawg-go) | MIT | v3.0.20260805 | The AmneziaWG implementation, used as published. |
| [wireguard-go](https://git.zx2c4.com/wireguard-go/) | MIT | via `amneziawg-go` | Upstream of `amneziawg-go`; its copyright notices travel with that dependency. |

## Forks

None. Caelo carries no patch series against any upstream, by design — see the architecture
note in the README for why the alternative was rejected.

## Copied material

None yet. Anything copied file-by-file gets a row here with the source path, the upstream
commit, and the license it arrived under.

If the netstack `tun.Device` in `core/` ends up adapted from sing-box's
`transport/wireguard/device_stack.go` rather than written from scratch, it belongs in this
section with the commit it came from. Both projects are GPL-3.0-or-later, so the reuse is
permitted; the attribution is still owed.


## Third-party licenses

The full dependency license inventory is generated during release rather than maintained
by hand. See `THIRD_PARTY_LICENSES.md` in the release artifacts.
