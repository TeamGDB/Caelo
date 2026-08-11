//go:build linux

package systunnel

import "github.com/amnezia-vpn/amneziawg-go/v3/tun"

// deviceName is taken literally on Linux. Named for the application rather than
// given a tun0 that anything else on the machine might also have chosen.
const deviceName = "caelo0"

// deviceHandle is only meaningful on Windows, where an adapter is identified by
// LUID rather than by name. Everything here takes the name.
func deviceHandle(tun.Device) uint64 { return 0 }
