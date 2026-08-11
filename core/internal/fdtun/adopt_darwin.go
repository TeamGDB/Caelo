//go:build darwin

package fdtun

import (
	"os"

	"github.com/amnezia-vpn/amneziawg-go/v3/tun"
)

// adopt takes over a descriptor NEPacketTunnelProvider created.
//
// Apple has no unmonitored constructor and does not need one: the descriptor
// is a real utun socket, so the ordinary path works — the name comes from a
// getsockopt rather than the netlink machinery Linux would have reached for.
//
// os.NewFile takes ownership, so closing the device closes the descriptor.
func adopt(fd int, mtu int) (tun.Device, error) {
	return tun.CreateTUNFromFile(os.NewFile(uintptr(fd), "utun"), mtu)
}
