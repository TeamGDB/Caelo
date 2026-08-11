//go:build android || linux

package fdtun

import "github.com/amnezia-vpn/amneziawg-go/v3/tun"

// adopt takes over a descriptor VpnService created.
//
// Unmonitored on purpose: the ordinary constructor sets up netlink monitoring
// and looks the interface up by index, and neither is available here. The app
// does not own that interface and cannot see it in the ways those calls
// expect.
func adopt(fd int, _ int) (tun.Device, error) {
	device, _, err := tun.CreateUnmonitoredTUNFromFD(fd)
	return device, err
}
