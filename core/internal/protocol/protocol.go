// Package protocol is where a kind of node other than AmneziaWG plugs in.
//
// The core started with one protocol and everything in it was written for
// that one: the probe, the tunnels on a host's device and on the machine's,
// the description a host builds its device from. A second protocol could have
// been threaded through each of those by hand, and so could a third, and by
// then every package would know every protocol.
//
// Instead a protocol registers itself here with what the rest of the core
// asks of any node — describe yourself, carry traffic in this process, run
// over this device — and each of those places asks the registry first. A
// configuration nothing here claims is AmneziaWG, read and run exactly as it
// was before this package existed: that path is the one people are connected
// through today, and it is not rewritten to make room.
//
// Adding a protocol is a package that implements Config and calls Register
// from init, and a line in internal/protocol/all.
package protocol

import (
	"context"
	"errors"
	"net"
	"sort"
	"sync"
	"time"
)

// AmneziaWG is the protocol nothing registers: the one the core was built
// around, reached when no registered protocol claims a configuration.
const AmneziaWG = "amneziawg"

// Protocol is one kind of configuration.
type Protocol struct {
	// Name is how the protocol is called in documents and capabilities:
	// lower case, no spaces.
	Name string

	// Claims says whether text is meant for this protocol, without checking
	// it. A configuration claimed and then refused is refused with this
	// protocol's reason, rather than handed to another that would fail it
	// for a reason that makes no sense to anyone.
	Claims func(text string) bool

	// Parse reads and checks a configuration.
	Parse func(text string) (Config, error)

	// Variants are the kinds of connection this protocol carries, as a
	// subscription is told them. Declared only for what has been run.
	Variants []string

	// Version is what implements it, for diagnostics: "Xray-core 26.11.9".
	Version func() string
}

// Config is one node, checked and ready to run.
type Config interface {
	// Describe reports what a host needs to build a device for this node.
	// Nothing is resolved or dialled.
	Describe() Description

	// Pin resolves the server's name now, while the machine's own resolver
	// still answers, and returns a configuration that dials only that
	// address, with the address. Hosts that route the server around the
	// tunnel need the address the tunnel will actually use.
	Pin(ctx context.Context) (Config, string, error)

	// Dial runs the node inside this process with no device: nothing on the
	// machine is touched and nothing but this process's own requests cross
	// it. For probing candidates and the in-process tunnel.
	Dial() (Dialer, error)

	// Attach runs the node over a tun device the host created.
	//
	// fd is handed over as the platform hands it: on Android it becomes the
	// tunnel's to close, on Apple platforms it stays the system's and a
	// duplicate is used. mtu is what the host set.
	Attach(fd int, mtu int) (Tunnel, error)

	// Create makes a device of the node's own, named name, for hosts that
	// cannot pass a descriptor (Windows). The returned interface name is
	// what the system calls it.
	Create(name string, mtu int) (Tunnel, string, error)
}

// Description is what a host builds its device from, and what is shown.
type Description struct {
	Protocol string `json:"protocol"`
	// Variant is the kind of connection, as capabilities spell it.
	Variant string `json:"variant,omitempty"`
	// Label is what to show a person: "VLESS".
	Label string `json:"label"`
	// Name is what the configuration calls the node, if anything.
	Name string `json:"name,omitempty"`

	// Addresses are the device's own, with a prefix length.
	Addresses []string `json:"addresses"`
	MTU       int      `json:"mtu"`
	DNS       []string `json:"dns"`
	// AllowedIPs are the routes into the device.
	AllowedIPs []string `json:"allowed_ips"`

	// Endpoint is the server as host:port, as the configuration wrote it.
	Endpoint string `json:"endpoint"`
	// Obfuscated is AmneziaWG's word, kept so that a host reading it from
	// either protocol gets an answer.
	Obfuscated bool `json:"obfuscated"`
}

// Dialer carries this process's own connections through a node.
type Dialer interface {
	DialContext(ctx context.Context, network, address string) (net.Conn, error)
	// WaitAlive proves the server carries traffic, or gives up.
	WaitAlive(timeout time.Duration) bool
	Close()
}

// Tunnel is a node running over a device.
type Tunnel interface {
	// LastAlive is when the server last proved itself there; zero if never.
	// What a handshake time is for AmneziaWG.
	LastAlive() time.Time
	// WaitAlive returns once the server has carried traffic, or false.
	WaitAlive(timeout time.Duration) bool
	Close()
}

var (
	mu        sync.RWMutex
	protocols = map[string]Protocol{}
)

// Register adds a protocol. Called from init; a name registered twice is a
// programming error and panics, as two packages answering for one protocol
// would otherwise be settled by link order.
func Register(p Protocol) {
	if p.Name == "" || p.Name == AmneziaWG || p.Claims == nil || p.Parse == nil {
		panic("protocol: incomplete registration for " + p.Name)
	}
	mu.Lock()
	defer mu.Unlock()
	if _, dup := protocols[p.Name]; dup {
		panic("protocol: " + p.Name + " registered twice")
	}
	protocols[p.Name] = p
}

// Find returns the protocol that claims text, if one does.
func Find(text string) (Protocol, bool) {
	mu.RLock()
	defer mu.RUnlock()
	for _, name := range sortedLocked() {
		if p := protocols[name]; p.Claims(text) {
			return p, true
		}
	}
	return Protocol{}, false
}

// ErrNotClaimed means no registered protocol claims a configuration: it is
// AmneziaWG's, or nobody's.
var ErrNotClaimed = errors.New("no registered protocol claims this configuration")

// Parse reads text with whichever protocol claims it.
func Parse(text string) (Config, error) {
	p, ok := Find(text)
	if !ok {
		return nil, ErrNotClaimed
	}
	return p.Parse(text)
}

// All lists the registered protocols, by name.
func All() []Protocol {
	mu.RLock()
	defer mu.RUnlock()
	out := make([]Protocol, 0, len(protocols))
	for _, name := range sortedLocked() {
		out = append(out, protocols[name])
	}
	return out
}

func sortedLocked() []string {
	names := make([]string, 0, len(protocols))
	for name := range protocols {
		names = append(names, name)
	}
	sort.Strings(names)
	return names
}

// Names lists every protocol this build runs, AmneziaWG first.
func Names() []string {
	names := []string{AmneziaWG}
	for _, p := range All() {
		names = append(names, p.Name)
	}
	return names
}

// Capabilities lists every kind of connection this build carries, as a
// subscription is told them.
func Capabilities() []string {
	var out []string
	for _, p := range All() {
		out = append(out, p.Variants...)
	}
	return out
}

// Versions reports what implements each registered protocol.
func Versions() map[string]string {
	out := map[string]string{}
	for _, p := range All() {
		if p.Version != nil {
			out[p.Name] = p.Version()
		}
	}
	return out
}
