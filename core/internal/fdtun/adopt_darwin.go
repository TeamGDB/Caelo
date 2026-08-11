//go:build darwin

package fdtun

import (
	"fmt"
	"os"

	"github.com/amnezia-vpn/amneziawg-go/v3/tun"
	"golang.org/x/sys/unix"
)

// adopt takes over a descriptor NEPacketTunnelProvider created.
//
// Apple has no unmonitored constructor and does not need one: the descriptor is
// a real utun socket, so the ordinary path works — the name comes from a
// getsockopt rather than the netlink machinery Linux would have reached for.
//
// Two details are not optional, and both were learned the hard way.
//
// The descriptor is duplicated. The system owns the original and goes on using
// it; os.NewFile takes ownership of whatever it is handed, so closing the
// device would close the system's descriptor out from under it.
//
// The MTU is deliberately not passed on. A non-zero value makes the constructor
// set the interface MTU with an ioctl, and a Network Extension is not permitted
// to do that — the call fails and adoption fails with it. The MTU is already
// set, by NEPacketTunnelNetworkSettings, from the same configuration.
func adopt(fd int, _ int) (tun.Device, error) {
	duplicate, err := unix.Dup(fd)
	if err != nil {
		return nil, fmt.Errorf("duplicating the descriptor: %w", err)
	}

	if err := unix.SetNonblock(duplicate, true); err != nil {
		unix.Close(duplicate)
		return nil, fmt.Errorf("setting the descriptor non-blocking: %w", err)
	}

	device, err := tun.CreateTUNFromFile(os.NewFile(uintptr(duplicate), "utun"), 0)
	if err != nil {
		unix.Close(duplicate)
		return nil, err
	}
	return device, nil
}
