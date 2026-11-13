//go:build darwin || linux || windows

package systunnel

import (
	"context"
	"errors"
	"fmt"
	"net/netip"
	"time"

	"github.com/TeamGDB/Caelo/core/internal/protocol"
	"github.com/TeamGDB/Caelo/core/internal/system"
)

// AliveTimeout is how long a new tunnel of a registered protocol has to carry
// a request before Start gives up on it. Longer than the handshake timeout:
// what is waited for is a whole request through the server and out, not one
// packet and its answer.
const AliveTimeout = 15 * time.Second

// startRegistered brings up a node of a registered protocol and points the
// machine at it. Called with c.mu held and nothing up.
func (c *Controller) startRegistered(node protocol.Config) (*Status, error) {
	if !registeredSupported {
		return nil, errors.New("this protocol runs through the system extension on this platform, not this tool")
	}

	// The server's address is fixed now, and the tunnel dials exactly that
	// one: a name resolved again later could be another address of a CDN,
	// outside the pinned route and into the tunnel that needs it.
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	pinned, endpointHost, err := node.Pin(ctx)
	cancel()
	if err != nil {
		return nil, err
	}
	if addr, err := netip.ParseAddr(endpointHost); err != nil || !addr.Unmap().Is4() {
		// The routing this pins with is IPv4; IPv6 is blocked while the
		// tunnel is up, so a server reachable only over it is unreachable.
		return nil, fmt.Errorf("the server has no IPv4 address")
	}

	description := pinned.Describe()
	address := ""
	for _, prefix := range description.Addresses {
		if p, err := netip.ParsePrefix(prefix); err == nil && p.Addr().Is4() {
			address = p.Addr().String()
			break
		}
	}
	if address == "" {
		return nil, errors.New("the configuration has no IPv4 tunnel address")
	}

	state, err := system.Snapshot()
	if err != nil {
		return nil, err
	}

	tunnel, name, err := pinned.Create(deviceName, description.MTU)
	if err != nil {
		return nil, fmt.Errorf("creating the tunnel interface: %w", err)
	}

	network := system.Config{
		Interface:    name,
		Handle:       registeredHandle(name),
		Address:      address,
		MTU:          description.MTU,
		EndpointHost: endpointHost,
		DNS:          description.DNS,
	}
	if err := system.Apply(state, network); err != nil {
		_ = system.Restore(state, network)
		tunnel.Close()
		return nil, err
	}

	// As with AmneziaWG (#117): nothing is reported up until the server has
	// carried traffic. After the routes, so that what is proven is the way
	// traffic will actually go.
	if !tunnel.WaitAlive(AliveTimeout) {
		_ = system.Restore(state, network)
		tunnel.Close()
		return nil, errors.New("the server did not carry a request")
	}

	c.tunnel = tunnel
	c.state = state
	c.network = network
	c.status = Status{
		Up:        true,
		Interface: name,
		Endpoint:  description.Endpoint,
		Protocol:  description.Label,
		SinceUnix: time.Now().Unix(),
	}
	status := c.status
	return &status, nil
}
