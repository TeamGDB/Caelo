package vless

import (
	"context"
	"fmt"
	"net"
	"net/netip"
	"os"
	"runtime"
	"runtime/debug"
	"strconv"
	"sync"

	"github.com/xtls/xray-core/common/platform"
	"github.com/xtls/xray-core/core"

	"github.com/TeamGDB/Caelo/core/internal/protocol"
)

func init() {
	protocol.Register(protocol.Protocol{
		Name:     Scheme,
		Claims:   Claims,
		Parse:    parseConfig,
		Variants: Variants,
		Version:  func() string { return "Xray-core " + core.Version() },
	})
}

// The device a VLESS tunnel runs on. Nothing on the far side sees these: a
// VLESS server is a proxy, not a peer on a network, so the addresses only
// have to be private, unlikely to collide with the network the device is on,
// and present in both families so that IPv6 is carried rather than leaked
// around the tunnel.
var (
	tunnelAddresses = []string{"172.19.0.1/30", "fdfe:dcba:9876::1/126"}
	tunnelRoutes    = []string{"0.0.0.0/0", "::/0"}
	// Resolution has to happen inside the tunnel. Queries go to this
	// address through the device, and out through the server like anything
	// else.
	tunnelDNS = []string{"1.1.1.1", "1.0.0.1"}
)

// TunnelMTU is the device's MTU. There is no encapsulation at the IP layer
// to make room for — packets end at the device and are carried as a stream —
// so it is Ethernet's.
const TunnelMTU = 1500

// iosMemoryLimit is the Go heap the iOS extension aims to stay under.
const iosMemoryLimit = 30 << 20

// tunName is what the device is called where Xray names it.
const tunName = "caelo"

type config struct {
	link *Link
	// address is the resolved server address, once pinned.
	address       string
	ipv6Checked   bool
	ipv6Available bool
}

func parseConfig(text string) (protocol.Config, error) {
	link, err := Parse(text)
	if err != nil {
		return nil, err
	}
	return &config{link: link}, nil
}

func (c *config) Describe() protocol.Description { return c.describeFor(runtime.GOOS) }

func (c *config) describeFor(platformName string) protocol.Description {
	d := protocol.Description{
		Protocol:   Scheme,
		Variant:    c.link.Variant(),
		Label:      "VLESS",
		Name:       c.link.Name,
		Addresses:  append([]string(nil), tunnelAddresses...),
		MTU:        TunnelMTU,
		DNS:        append([]string(nil), tunnelDNS...),
		AllowedIPs: append([]string(nil), tunnelRoutes...),
		Endpoint:   c.link.Endpoint(),
	}
	if c.ipv6Checked {
		available := c.ipv6Available
		d.IPv6Available = &available
	}
	// На Android отсутствие семейства в Builder блокирует его целиком, в том
	// числе обход через Wi-Fi. Apple сохраняет маршрут-перехват с отказом в ядре.
	if platformName == "android" && !c.ipv6Available {
		d.Addresses = d.Addresses[:1]
		d.AllowedIPs = d.AllowedIPs[:1]
	}
	return d
}

func (c *config) Pin(ctx context.Context) (protocol.Config, string, error) {
	if c.address != "" {
		return c, c.address, nil
	}
	if addr, err := netip.ParseAddr(c.link.Host); err == nil {
		return c, addr.String(), nil
	}
	addrs, err := net.DefaultResolver.LookupNetIP(ctx, "ip", c.link.Host)
	if err != nil || len(addrs) == 0 {
		return nil, "", fmt.Errorf("resolving the server's name: %w", err)
	}
	// IPv4 first: it is what every host's routing pins reliably, and a
	// network without IPv6 is far more common than one without IPv4.
	chosen := addrs[0]
	for _, addr := range addrs {
		if addr.Unmap().Is4() {
			chosen = addr.Unmap()
			break
		}
	}
	pinned := *c
	pinned.address = chosen.String()
	return &pinned, chosen.String(), nil
}

func (c *config) Dial() (protocol.Dialer, error) {
	in, err := start(c.link, options{address: c.address})
	if err != nil {
		return nil, err
	}
	return dialer{in}, nil
}

type dialer struct{ *instance }

func (d dialer) DialContext(ctx context.Context, network, address string) (net.Conn, error) {
	return d.instance.Dial(ctx, network, address)
}

// tunFdMu serialises handing a descriptor to Xray. Xray takes it from the
// environment, which belongs to the whole process, and two tunnels starting
// at once would otherwise each read the other's.
var tunFdMu sync.Mutex

func (c *config) Attach(fd int, mtu int) (_ protocol.Tunnel, resultErr error) {
	originalFD := fd
	defer func() {
		if resultErr != nil && runtime.GOOS == "android" {
			closeFd(originalFD)
		}
	}()
	if mtu <= 0 {
		mtu = TunnelMTU
	}
	if runtime.GOOS == "ios" {
		// The packet tunnel extension is killed outright past about 50 MB.
		// A soft limit well below that makes the collector work harder as
		// the heap approaches it, instead of letting it grow until the
		// system ends the tunnel — and with it, every connection.
		debug.SetMemoryLimit(iosMemoryLimit)
	}

	tunFdMu.Lock()
	defer tunFdMu.Unlock()

	var guard packetGuard
	// Android после Prepare блокирует неподтверждённое семейство в Builder.
	// При прямом вызове без Prepare нужен тот же перехват, что и на Apple.
	if !c.ipv6Available && (runtime.GOOS == "darwin" || runtime.GOOS == "ios" || (runtime.GOOS == "android" && !c.ipv6Checked)) {
		prefix := 4
		if runtime.GOOS == "android" {
			prefix = 0
		}
		var err error
		guard, err = newIPv6Guard(fd, prefix)
		if err != nil {
			return nil, fmt.Errorf("creating IPv6 guard: %w", err)
		}
		fd = guard.FD()
		defer func() {
			if resultErr != nil {
				guard.Close()
			}
		}()
	}
	if err := os.Setenv(platform.TunFdKey, strconv.Itoa(fd)); err != nil {
		return nil, fmt.Errorf("handing the device to Xray: %w", err)
	}
	// Taken away again once Xray has read it: a probe or a later tunnel
	// that found it still set would try to read packets from a descriptor
	// that is not theirs.
	defer os.Unsetenv(platform.TunFdKey)

	in, err := start(c.link, options{
		address: c.address,
		tun:     &tunOptions{Name: tunName, MTU: mtu},
	})
	if err != nil {
		return nil, err
	}
	var tunnel protocol.Tunnel = in
	if guard != nil {
		tunnel = &guardedTunnel{instance: in, guard: guard}
	}
	if runtime.GOOS == "android" {
		return &ownedFd{Tunnel: tunnel, fd: originalFD}, nil
	}
	return tunnel, nil
}

// ownedFd is a tunnel that also closes the descriptor it was given.
type ownedFd struct {
	protocol.Tunnel
	fd   int
	once sync.Once
}

func (o *ownedFd) Close() {
	o.once.Do(func() {
		o.Tunnel.Close()
		closeFd(o.fd)
	})
}

func (c *config) Create(name string, mtu int) (protocol.Tunnel, string, error) {
	if mtu <= 0 {
		mtu = TunnelMTU
	}
	tunFdMu.Lock()
	defer tunFdMu.Unlock()
	// Whatever a previous Attach left would make Xray read someone else's
	// device instead of creating its own.
	os.Unsetenv(platform.TunFdKey)

	in, err := start(c.link, options{
		address: c.address,
		tun:     &tunOptions{Name: name, MTU: mtu},
	})
	if err != nil {
		return nil, "", err
	}
	return in, name, nil
}
