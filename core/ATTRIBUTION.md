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
| [wireguard-windows](https://git.zx2c4.com/wireguard-windows/) | MIT | v1.0.1 | Only `tunnel/winipcfg`: addresses, routes, MTU and DNS on a Windows adapter through the IP Helper API. Used so that none of that is done by parsing the output of `netsh`, which prints in the machine's own language. |
| [go-winio](https://github.com/Microsoft/go-winio) | MIT | v0.6.2 | Named pipes on Windows, with a security descriptor. The pipe is what decides who may drive the tunnel there. |

## Wintun

The Windows tunnel adapter. Not a Go dependency and not in this tree: `wintun.dll` is
fetched at packaging time from [wintun.net](https://www.wintun.net/) against a pinned
version and SHA-256, and shipped beside `caelo-service.exe`.

| What | Licence |
| --- | --- |
| [Wintun](https://git.zx2c4.com/wintun/) source | GPL-2.0 |
| The prebuilt `wintun.dll` from wintun.net/builds | WireGuard LLC's own [Prebuilt Binaries License](https://git.zx2c4.com/wintun/tree/prebuilt-binaries-license.txt) |

The prebuilt licence is not a free-software one. It permits redistribution only
"insofar as the Software is distributed alongside other software that uses the Software
only via the Permitted API", and forbids reverse engineering, removing its notices, and
using WireGuard's or Wintun's names to imply endorsement. Caelo uses only the documented
API, through `golang.zx2c4.com/wintun`, and ships the DLL unmodified.

It is aggregated with Caelo rather than combined into it: a separate program, loaded at
run time, distributed alongside. Nothing in this repository is a derivative of it, and no
part of Caelo's own GPL-3.0-or-later licensing extends to it or is restricted by it.

## Forks

None, by design.

## Copied material

None. Anything copied file-by-file gets a row here with the source path, the upstream
commit, and the licence it arrived under — with its copyright header preserved and an
`SPDX-License-Identifier` added.
