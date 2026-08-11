//go:build darwin

package systunnel

import "github.com/amnezia-vpn/amneziawg-go/v3/tun"

// deviceName is a prefix on macOS: the kernel appends the first free number,
// which is why the controller asks the device what it ended up being called.
const deviceName = "utun"

// deviceHandle is only meaningful on Windows, where an adapter is identified by
// LUID rather than by name. Everything here takes the name.
func deviceHandle(tun.Device) uint64 { return 0 }
