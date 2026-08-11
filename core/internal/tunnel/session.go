// Package tunnel keeps a single AmneziaWG tunnel up for as long as it is
// wanted, and lets callers send traffic through it.
//
// Everything runs in userspace on a gVisor netstack. That means no privileges
// and no interface on the host — and also that traffic from other applications
// is not routed through it. Routing the whole machine needs a system tunnel
// device, which on macOS means a NetworkExtension. Until that exists, this is
// a real tunnel that only this process can use.
package tunnel

import (
	"context"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/netip"
	"strings"
	"sync"
	"time"

	"github.com/amnezia-vpn/amneziawg-go/v3/conn"
	"github.com/amnezia-vpn/amneziawg-go/v3/device"
	"github.com/amnezia-vpn/amneziawg-go/v3/tun/netstack"

	"github.com/TeamGDB/Caelo/core/internal/awg"
	"github.com/TeamGDB/Caelo/core/internal/diag"
)

// ErrNotConnected is returned by operations that need a live tunnel.
var ErrNotConnected = errors.New("no tunnel is up")

// Session is one tunnel. It is safe to use from multiple goroutines, which
// matters because the caller is a user interface: a second tap on the button
// arrives while the first is still being handled.
type Session struct {
	mu sync.Mutex

	device   *device.Device
	net      *netstack.Net
	endpoint string
	upSince  time.Time
}

// New returns a Session with no tunnel up.
func New() *Session { return &Session{} }

// Info describes a live tunnel.
type Info struct {
	Endpoint   string `json:"endpoint"`
	MTU        int    `json:"mtu"`
	Obfuscated bool   `json:"obfuscated"`
	Protocol   string `json:"protocol"`
}

// Connect brings up the tunnel described by configText, replacing any tunnel
// already up.
//
// It returns once the device is configured and running, which is not the same
// as the handshake having completed — WireGuard has no connect step, and the
// first packet is what proves the peer is there. Callers that need to know
// whether traffic really flows should follow this with Check.
func (s *Session) Connect(configText string) (*Info, error) {
	cfg, err := awg.Parse(configText)
	if err != nil {
		return nil, fmt.Errorf("reading configuration: %w", err)
	}

	dns := cfg.DNS
	if len(dns) == 0 {
		// Resolution happens inside the tunnel, so a resolver reachable only
		// from there is the point rather than a limitation.
		dns = []netip.Addr{netip.MustParseAddr("1.1.1.1")}
	}

	tun, tnet, err := netstack.CreateNetTUN(cfg.Addresses, dns, cfg.MTU)
	if err != nil {
		return nil, fmt.Errorf("creating netstack device: %w", err)
	}

	dev := device.NewDevice(tun, conn.NewDefaultBind(), diag.DeviceLogger())

	if err := dev.IpcSet(cfg.IPC()); err != nil {
		dev.Close()
		return nil, fmt.Errorf("configuring device: %w", err)
	}
	if err := dev.Up(); err != nil {
		dev.Close()
		return nil, fmt.Errorf("bringing device up: %w", err)
	}

	s.mu.Lock()
	previous := s.device
	s.device = dev
	s.net = tnet
	s.endpoint = cfg.Peer.Endpoint
	s.upSince = time.Now()
	s.mu.Unlock()

	// Closed after the swap, not before: a failed Connect should leave the
	// tunnel that was already working alone.
	if previous != nil {
		previous.Close()
	}

	protocol := "AmneziaWG"
	if len(cfg.Obfuscation) == 0 {
		protocol = "WireGuard"
	}

	return &Info{
		Endpoint:   cfg.Peer.Endpoint,
		MTU:        cfg.MTU,
		Obfuscated: len(cfg.Obfuscation) > 0,
		Protocol:   protocol,
	}, nil
}

// Reachability is what a Check found.
type Reachability struct {
	Address   string `json:"address"`
	Status    string `json:"status"`
	ElapsedMs int64  `json:"elapsed_ms"`
}

// Check fetches url through the live tunnel and reports what came back.
//
// The response body is the evidence: if it names the endpoint rather than the
// caller, traffic really left through the tunnel. Latency is measured for the
// whole request, so it is a usable number to show a person and not a
// round-trip time.
func (s *Session) Check(url string, timeout time.Duration) (*Reachability, error) {
	s.mu.Lock()
	tnet := s.net
	s.mu.Unlock()

	if tnet == nil {
		return nil, ErrNotConnected
	}
	if url == "" {
		url = "https://ifconfig.me/ip"
	}
	if timeout <= 0 {
		timeout = 20 * time.Second
	}

	ctx, cancel := context.WithTimeout(context.Background(), timeout)
	defer cancel()

	client := &http.Client{Transport: &http.Transport{DialContext: tnet.DialContext}}

	request, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return nil, err
	}

	started := time.Now()
	response, err := client.Do(request)
	if err != nil {
		return nil, fmt.Errorf("reaching %s through the tunnel: %w", url, err)
	}
	defer response.Body.Close()

	body, err := io.ReadAll(io.LimitReader(response.Body, 4096))
	if err != nil {
		return nil, fmt.Errorf("reading response: %w", err)
	}

	return &Reachability{
		Address:   strings.TrimSpace(string(body)),
		Status:    response.Status,
		ElapsedMs: time.Since(started).Milliseconds(),
	}, nil
}

// Disconnect tears the tunnel down. Calling it with nothing up is not an error;
// the caller asked for a state, and that state is what they get.
func (s *Session) Disconnect() {
	s.mu.Lock()
	dev := s.device
	s.device = nil
	s.net = nil
	s.endpoint = ""
	s.mu.Unlock()

	if dev != nil {
		dev.Close()
	}
}

// Up reports whether a tunnel is currently up, and to where.
func (s *Session) Up() (bool, string) {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.device != nil, s.endpoint
}
