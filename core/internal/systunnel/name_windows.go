//go:build windows

package systunnel

import "github.com/amnezia-vpn/amneziawg-go/v3/tun"

// deviceName is what the adapter is called in Network Connections. Taken
// literally, and visible to whoever opens that window, so it is the product's
// name rather than an abbreviation.
const deviceName = "Caelo"

// deviceHandle returns the adapter's LUID.
//
// Windows identifies an adapter by LUID in every call that configures one, and
// a name is not accepted anywhere useful. Names are also not unique enough to
// resolve back safely: two adapters can carry the same alias, and picking the
// wrong one means configuring somebody else's network card.
func deviceHandle(device tun.Device) uint64 {
	if native, ok := device.(*tun.NativeTun); ok {
		return native.LUID()
	}
	return 0
}
