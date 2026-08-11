//go:build darwin

// Package systunnel owns a tunnel that carries the whole machine's traffic.
//
// Unlike the in-process tunnel in package tunnel, this creates a real utun
// interface and takes over routing, so every application goes through it. That
// needs root, which is why the only things that use it are a command run under
// sudo and a launchd helper.
package systunnel

import (
	"fmt"
	"net"
	"sync"
	"time"

	"github.com/amnezia-vpn/amneziawg-go/v3/conn"
	"github.com/amnezia-vpn/amneziawg-go/v3/device"
	"github.com/amnezia-vpn/amneziawg-go/v3/tun"

	"github.com/TeamGDB/Caelo/core/internal/awg"
	"github.com/TeamGDB/Caelo/core/internal/diag"
	"github.com/TeamGDB/Caelo/core/internal/system"
)

// Status describes what the controller is currently doing.
type Status struct {
	Up         bool   `json:"up"`
	Interface  string `json:"interface,omitempty"`
	Endpoint   string `json:"endpoint,omitempty"`
	Protocol   string `json:"protocol,omitempty"`
	Obfuscated bool   `json:"obfuscated,omitempty"`
	SinceUnix  int64  `json:"since_unix,omitempty"`
}

// Controller brings the machine's traffic in and out of a tunnel. It is safe
// for concurrent use: the caller is a socket server handling one request while
// another is still in flight.
type Controller struct {
	mu sync.Mutex

	device  *device.Device
	state   *system.State
	network system.Config
	status  Status
}

// New returns a Controller with nothing up.
func New(verbose bool) *Controller {
	diag.SetVerbose(verbose)
	return &Controller{}
}

// Start brings the tunnel up and points the machine at it.
//
// Any tunnel already up is torn down first. Two tunnels would mean two sets of
// routes fighting over the same default, and whichever lost would leave its
// routes behind.
func (c *Controller) Start(configText string) (*Status, error) {
	c.mu.Lock()
	defer c.mu.Unlock()

	if c.device != nil {
		c.stopLocked()
	}

	cfg, err := awg.ParseConfig(configText)
	if err != nil {
		return nil, fmt.Errorf("reading configuration: %w", err)
	}

	endpointHost, err := EndpointAddress(cfg.Peer.Endpoint)
	if err != nil {
		return nil, err
	}

	// Snapshot before anything is touched, so there is always something to
	// restore from even if the first change fails.
	state, err := system.Snapshot()
	if err != nil {
		return nil, err
	}

	tunDevice, err := tun.CreateTUN("utun", cfg.MTU)
	if err != nil {
		return nil, fmt.Errorf("creating a utun interface: %w", err)
	}
	name, err := tunDevice.Name()
	if err != nil {
		tunDevice.Close()
		return nil, fmt.Errorf("naming the utun interface: %w", err)
	}

	dev := device.NewDevice(tunDevice, conn.NewDefaultBind(), diag.DeviceLogger())

	fail := func(err error) (*Status, error) {
		dev.Close()
		return nil, err
	}

	if err := dev.IpcSet(cfg.IPC()); err != nil {
		return fail(fmt.Errorf("configuring the device: %w", err))
	}
	if err := dev.Up(); err != nil {
		return fail(fmt.Errorf("bringing the device up: %w", err))
	}

	dns := []string{"1.1.1.1"}
	if len(cfg.DNS) > 0 {
		dns = dns[:0]
		for _, addr := range cfg.DNS {
			dns = append(dns, addr.String())
		}
	}

	network := system.Config{
		Interface:    name,
		Address:      cfg.Addresses[0].String(),
		MTU:          cfg.MTU,
		EndpointHost: endpointHost,
		DNS:          dns,
	}

	if err := system.Apply(state, network); err != nil {
		// Apply changes things before it fails. Unwinding here rather than
		// leaving it to the caller means a failed Start cannot leave the
		// machine half-rerouted.
		_ = system.Restore(state, network)
		return fail(err)
	}

	protocol := "AmneziaWG"
	if len(cfg.Obfuscation) == 0 {
		protocol = "WireGuard"
	}

	c.device = dev
	c.state = state
	c.network = network
	c.status = Status{
		Up:         true,
		Interface:  name,
		Endpoint:   cfg.Peer.Endpoint,
		Protocol:   protocol,
		Obfuscated: len(cfg.Obfuscation) > 0,
		SinceUnix:  time.Now().Unix(),
	}

	status := c.status
	return &status, nil
}

// Stop tears the tunnel down and restores the machine's routing.
//
// Calling it with nothing up is not an error: the caller asked for a state, and
// that state is what they get.
func (c *Controller) Stop() error {
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.stopLocked()
}

func (c *Controller) stopLocked() error {
	if c.device == nil {
		return nil
	}

	// Routing comes back first. If closing the device panicked or hung, the
	// machine would otherwise be left pointing at an interface that is gone,
	// which is indistinguishable from having no network at all.
	err := system.Restore(c.state, c.network)

	c.device.Close()
	c.device = nil
	c.state = nil
	c.status = Status{}

	return err
}

// Status reports what is up without disturbing it.
func (c *Controller) Status() Status {
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.status
}

// EndpointAddress resolves the host part of an endpoint to an address that can
// be pinned to the physical route.
func EndpointAddress(endpoint string) (string, error) {
	if endpoint == "" {
		return "", fmt.Errorf("the configuration has no Endpoint")
	}

	host, _, err := net.SplitHostPort(endpoint)
	if err != nil {
		return "", fmt.Errorf("endpoint %q is not host:port: %w", endpoint, err)
	}
	if ip := net.ParseIP(host); ip != nil {
		return host, nil
	}

	// Resolved now, while the ordinary resolver still works. Once the tunnel is
	// up, resolution goes through it, and looking the endpoint up then would
	// need the tunnel that needs the endpoint.
	addrs, err := net.LookupHost(host)
	if err != nil {
		return "", fmt.Errorf("resolving endpoint %q: %w", host, err)
	}
	for _, addr := range addrs {
		if ip := net.ParseIP(addr); ip != nil && ip.To4() != nil {
			return addr, nil
		}
	}
	return "", fmt.Errorf("endpoint %q has no IPv4 address", host)
}
