//go:build android || linux

// Package fdtun runs a tunnel on a device the host platform created.
//
// On Android an application cannot open a tun device itself: the system does
// it, through VpnService, and hands back a file descriptor. Routing, addresses,
// MTU and DNS are configured on that side too. So unlike the macOS path, this
// package does not touch the machine's networking at all — it is handed a
// device that is already wired up and runs AmneziaWG over it.
package fdtun

import (
	"fmt"
	"os"
	"sync"
	"time"

	"github.com/amnezia-vpn/amneziawg-go/v3/conn"
	"github.com/amnezia-vpn/amneziawg-go/v3/device"
	"github.com/amnezia-vpn/amneziawg-go/v3/tun"

	"github.com/TeamGDB/Caelo/core/internal/awg"
)

// Status describes a live tunnel.
type Status struct {
	Up         bool   `json:"up"`
	Endpoint   string `json:"endpoint,omitempty"`
	Protocol   string `json:"protocol,omitempty"`
	Obfuscated bool   `json:"obfuscated,omitempty"`
	SinceUnix  int64  `json:"since_unix,omitempty"`
}

// Session is one tunnel on a host-provided device.
type Session struct {
	mu sync.Mutex

	device *device.Device
	bind   conn.Bind
	status Status
}

// New returns a Session with nothing up.
func New() *Session { return &Session{} }

// Start runs AmneziaWG over the tun device behind fd.
//
// The descriptor is taken over: it is closed when the tunnel stops, and the
// caller must not close it itself. Handing the same descriptor in twice would
// leave two devices reading one queue, each seeing half the packets.
func (s *Session) Start(fd int, configText string) (*Status, error) {
	s.mu.Lock()
	defer s.mu.Unlock()

	if s.device != nil {
		s.stopLocked()
	}

	cfg, err := awg.ParseConfig(configText)
	if err != nil {
		return nil, fmt.Errorf("reading configuration: %w", err)
	}

	// os.NewFile takes ownership, so the device's Close closes the descriptor.
	tunDevice, err := tun.CreateTUNFromFile(os.NewFile(uintptr(fd), "tun"), cfg.MTU)
	if err != nil {
		return nil, fmt.Errorf("adopting the tun descriptor: %w", err)
	}

	bind := conn.NewDefaultBind()
	dev := device.NewDevice(tunDevice, bind, device.NewLogger(device.LogLevelError, "caelo "))

	if err := dev.IpcSet(cfg.IPC()); err != nil {
		dev.Close()
		return nil, fmt.Errorf("configuring the device: %w", err)
	}
	if err := dev.Up(); err != nil {
		dev.Close()
		return nil, fmt.Errorf("bringing the device up: %w", err)
	}

	protocol := "AmneziaWG"
	if len(cfg.Obfuscation) == 0 {
		protocol = "WireGuard"
	}

	s.device = dev
	s.bind = bind
	s.status = Status{
		Up:         true,
		Endpoint:   cfg.Peer.Endpoint,
		Protocol:   protocol,
		Obfuscated: len(cfg.Obfuscation) > 0,
		SinceUnix:  time.Now().Unix(),
	}

	status := s.status
	return &status, nil
}

// SocketFds returns the descriptors of the sockets carrying tunnel traffic, so
// the host can exclude them from its own routing.
//
// On Android that means VpnService.protect. Without it the encrypted packets
// would be routed back into the tunnel they belong to, and nothing would ever
// reach the server.
//
// The sockets only exist once the device is up, so this cannot be done before
// Start. The handshake is retried, so protecting immediately afterwards is in
// time — the first attempt may be lost, and the second will not be.
func (s *Session) SocketFds() (v4 int, v6 int, err error) {
	s.mu.Lock()
	bind := s.bind
	s.mu.Unlock()

	if bind == nil {
		return -1, -1, fmt.Errorf("no tunnel is up")
	}

	peeker, ok := bind.(conn.PeekLookAtSocketFd)
	if !ok {
		return -1, -1, fmt.Errorf("this bind does not expose its sockets")
	}

	// A machine with no IPv6 has no v6 socket, and that is not a failure.
	// Reporting -1 lets the caller skip it rather than abandon the tunnel.
	v4, errV4 := peeker.PeekLookAtSocketFd4()
	if errV4 != nil {
		v4 = -1
	}
	v6, errV6 := peeker.PeekLookAtSocketFd6()
	if errV6 != nil {
		v6 = -1
	}
	if v4 < 0 && v6 < 0 {
		return -1, -1, fmt.Errorf("neither socket could be found: %v, %v", errV4, errV6)
	}
	return v4, v6, nil
}

// Stop tears the tunnel down and closes the descriptor it was given.
func (s *Session) Stop() {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.stopLocked()
}

func (s *Session) stopLocked() {
	if s.device == nil {
		return
	}
	s.device.Close()
	s.device = nil
	s.bind = nil
	s.status = Status{}
}

// Status reports what is up without disturbing it.
func (s *Session) Status() Status {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.status
}
