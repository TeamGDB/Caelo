# Attribution

What came from where, so credit is given and licence obligations stay traceable. The app
repository keeps [its own copy](https://github.com/TeamGDB/Caelo/blob/main/ATTRIBUTION.md)
covering the interface side.

## Dependencies

Consumed as published. Nothing below is copied into this tree.

| Project | Licence | Version | Notes |
| --- | --- | --- | --- |
| [amneziawg-go](https://github.com/amnezia-vpn/amneziawg-go) | MIT | v3.0.20260805 | The AmneziaWG implementation, including the obfuscation layer and the gVisor netstack device. |
| [wireguard-go](https://git.zx2c4.com/wireguard-go/) | MIT | via `amneziawg-go` | Upstream of the above; its copyright notices travel with that dependency. |
| [sing-box](https://github.com/SagerNet/sing-box) | GPL-3.0-or-later, with an additional §7 clause restricting use of the name and implied association | v1.13.16 | Everything that is not AmneziaWG. Added to `go.mod` with the endpoint registration. |
| [gVisor](https://github.com/google/gvisor) | Apache-2.0 | via `amneziawg-go` | Userspace network stack. |

## Forks

None, by design.

## Copied material

None. Anything copied file-by-file gets a row here with the source path, the upstream
commit, and the licence it arrived under — with its copyright header preserved and an
`SPDX-License-Identifier` added.
