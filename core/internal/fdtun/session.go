// Only the platforms that hand an application a descriptor for a device the
// system opened. Windows has no such arrangement, and without this the
// package half-compiles there: the file that declares adopt is excluded by
// its own constraint and this one is not.
//go:build android || linux || darwin

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
	"sync"
	"time"

	"github.com/amnezia-vpn/amneziawg-go/v3/conn"
	"github.com/amnezia-vpn/amneziawg-go/v3/device"

	"github.com/TeamGDB/Caelo/core/internal/awg"
	"github.com/TeamGDB/Caelo/core/internal/diag"
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

	cfg, err := awg.Parse(configText)
	if err != nil {
		return nil, fmt.Errorf("reading configuration: %w", err)
	}

	// How a descriptor is adopted differs by platform; what happens to it
	// afterwards does not. See adopt_*.go.
	//
	// MTU is not passed: it is not ours to set. Whoever created the device
	// applied it, and on both platforms that is the system.
	tunDevice, err := adopt(fd, cfg.MTU)
	if err != nil {
		return nil, fmt.Errorf("adopting the tun descriptor: %w", err)
	}
	// Не выставляем, но сообщаем. См. mtu.go: с 3.1 от этого числа зависит
	// размер довеска к каждому пакету, и при нуле довесок не ограничен ничем.
	tunDevice = withMTU(tunDevice, cfg.MTU)

	bind := conn.NewDefaultBind()
	dev := device.NewDevice(tunDevice, bind, diag.DeviceLogger())

	if err := dev.IpcSet(cfg.IPC()); err != nil {
		dev.Close()
		return nil, fmt.Errorf("configuring the device: %w", err)
	}
	if err := dev.Up(); err != nil {
		dev.Close()
		return nil, fmt.Errorf("bringing the device up: %w", err)
	}

	// Mobile networks change the source address under a live connection often
	// enough that WireGuard's roaming behaviour, which trusts the address a
	// packet arrived from, works against us here. The reference Android client
	// disables it for the same reason.
	dev.DisableSomeRoamingForBrokenMobileSemantics()

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
// On Android that means VpnService.protect. It never reports failure: a
// descriptor that cannot be found comes back as -1 and the caller skips it.
// The reference Android client does the same, and for good reason — a device
// with no IPv6 has no v6 socket, and treating that as a broken tunnel would
// refuse to connect on a working network.
//
// The tunnel survives without it in the usual case anyway, because the app
// excludes itself from its own routes. Protecting the sockets is the belt to
// that pair of braces.
//
// The sockets only exist once the device is up, so this cannot happen before
// Start. The handshake is retried, so protecting immediately afterwards is in
// time: the first attempt may be lost, and the second will not be.
func (s *Session) SocketFds() (v4 int, v6 int) {
	s.mu.Lock()
	bind := s.bind
	s.mu.Unlock()

	peeker, ok := bind.(conn.PeekLookAtSocketFd)
	if !ok {
		return -1, -1
	}

	v4, err := peeker.PeekLookAtSocketFd4()
	if err != nil {
		v4 = -1
	}
	v6, err = peeker.PeekLookAtSocketFd6()
	if err != nil {
		v6 = -1
	}
	return v4, v6
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
