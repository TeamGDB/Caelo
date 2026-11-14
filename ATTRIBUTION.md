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
| [Xray-core](https://github.com/XTLS/Xray-core) | MPL-2.0 | v26.11.9 | VLESS (REALITY, TLS, Vision, XHTTP) and its TUN input, imported as a Go module by the core and used as published. MPL-2.0 is file-level copyleft compatible with GPL-3.0: its files stay under MPL in a larger GPL work. Updated with `scripts/update-xray.sh`. |
| [amneziawg-go](https://github.com/amnezia-vpn/amneziawg-go) | MIT | v3.1.20260814 | The AmneziaWG implementation, used as published. |
| [wireguard-go](https://git.zx2c4.com/wireguard-go/) | MIT | via `amneziawg-go` | Upstream of `amneziawg-go`; its copyright notices travel with that dependency. |
| [file_selector](https://github.com/flutter/packages/tree/main/packages/file_selector/file_selector) | BSD-3-Clause | 1.1.0 | Used as published to open the operating system file picker for local `.conf` import. |
| [device_info_plus](https://github.com/fluttercommunity/plus_plugins/tree/main/packages/device_info_plus/device_info_plus) | BSD-3-Clause | 13.3.0 | Used as published to read the device's own name and OS version for the subscription's list of devices. |
| [app_links](https://github.com/llfbandit/app_links) | Apache-2.0 | 7.2.2 | Used as published to receive `caelo://add` links on Android, iOS, macOS, Windows and Linux (#163). On Windows its `SendAppLinkToInstance` hands a link to the window already open. |
| [mobile_scanner](https://github.com/juliansteenbakker/mobile_scanner) | BSD-3-Clause | 7.4.2 | Used as published to read a subscription's QR code with the camera at sign-in. On Android it bundles Google ML Kit's barcode model, which runs on the device. |
| [Sparkle](https://github.com/sparkle-project/Sparkle) | MIT, with BSD-2-Clause components (`bsdiff`/`bspatch`) | 2.9.x | The macOS updater, used as published. Its own signature check is left in place and supplemented rather than replaced: see `docs/updates.md`. |

## Forks

None. Caelo carries no patch series against any upstream, by design — see the architecture
note in the README for why the alternative was rejected.

## Copied material

| What | From | License | Where |
| --- | --- | --- | --- |
| The declarations of `ctl_info`, `sockaddr_ctl` and `CTLIOCGINFO`, and the approach of locating the tunnel's descriptor by scanning for a utun control socket | [wireguard-apple](https://github.com/WireGuard/wireguard-apple) | MIT | `ios/CaeloPacketTunnel/CaeloPacketTunnel-Bridging-Header.h`, `PacketTunnelProvider.swift` |
| Flag glyphs: the regional-indicator part of the Twemoji Mozilla font (`Twemoji.Mozilla.ttf`, release v0.7.0), cut with `pyftsubset` to U+1F1E6–U+1F1FF and the ligatures that join them (#168) | [twemoji-colr](https://github.com/mozilla/twemoji-colr), artwork from [Twemoji](https://github.com/twitter/twemoji) © Twitter, Inc and other contributors | Artwork CC-BY-4.0; the font build Apache-2.0 | `assets/fonts/CaeloFlags.ttf`, see `assets/fonts/README.md` |

`<sys/kern_control.h>` is not in the iOS SDK, so those three declarations have
to be reproduced by anyone who needs them; the ABI is public and stable. The
scanning approach is theirs, and it exists because the documented-looking
alternative — reading `packetFlow`'s `socket.fileDescriptor` key path — is
undocumented and stops working.

Anything else copied file-by-file gets a row above, with the source path, the upstream
commit, and the license it arrived under.

If the netstack `tun.Device` in `core/` ends up adapted from sing-box's
`transport/wireguard/device_stack.go` rather than written from scratch, it belongs in this
section with the commit it came from. Both projects are GPL-3.0-or-later, so the reuse is
permitted; the attribution is still owed.


## Third-party licenses

The full dependency license inventory is generated during release rather than maintained
by hand. See `THIRD_PARTY_LICENSES.md` in the release artifacts.
