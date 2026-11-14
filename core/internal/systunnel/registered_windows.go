//go:build windows

package systunnel

import (
	"net"
	"time"

	"golang.zx2c4.com/wireguard/windows/tunnel/winipcfg"
)

// handleRequired: the platform configures the device by handle, not name.
const handleRequired = true

const registeredSupported = true

// registeredHandle finds the LUID of the adapter Xray created.
//
// By name, which the comment on deviceHandle warns against for adapters in
// general. Here the name is one this service just created and owns, and the
// adapter Xray made is not reachable any other way from outside it. It can
// take a moment to appear.
func registeredHandle(name string) uint64 {
	deadline := time.Now().Add(3 * time.Second)
	for {
		if iface, err := net.InterfaceByName(name); err == nil {
			if luid, err := winipcfg.LUIDFromIndex(uint32(iface.Index)); err == nil {
				return uint64(luid)
			}
		}
		if time.Now().After(deadline) {
			return 0 // reported by startRegistered
		}
		time.Sleep(100 * time.Millisecond)
	}
}
