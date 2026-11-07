// Package rtt measures the round trip to the server from traffic that is
// crossing the tunnel anyway (#156).
//
// Every TCP connection a person opens starts with a SYN going out and a
// SYN-ACK coming back, and both pass through the tun device. The time between
// them is a round trip through the server to wherever the connection goes.
// All of it goes through the server, so none can be shorter than the trip to
// the server, and the shortest of the recent ones — usually to a CDN that sits
// beside the exit — is that trip plus a few milliseconds.
//
// Nothing is sent to measure it. An active ping every second would be a
// metronome in an otherwise irregular stream, which is exactly the kind of
// regularity a blocking system can pick out; this changes nothing on the wire.
package rtt

import (
	"encoding/binary"
	"net/netip"
	"sync"
	"time"

	"github.com/amnezia-vpn/amneziawg-go/v3/tun"
)

const (
	// Window is how far back the figure looks. Long enough to have a few
	// connections in it while someone browses, short enough to follow a
	// change of network within seconds.
	Window = 10 * time.Second

	// pendingFor is how long a SYN waits for its answer. A SYN-ACK later
	// than this is from a connection that was struggling, and its time says
	// more about that than about the server.
	pendingFor = 5 * time.Second

	// maxPending bounds what is remembered between a SYN and its answer, so
	// a burst of connections that never complete cannot grow it without end.
	maxPending = 512

	// maxSamples bounds the window the same way.
	maxSamples = 256
)

type flow struct {
	local, remote         netip.Addr
	localPort, remotePort uint16
}

type syn struct {
	at  time.Time
	seq uint32
	// again is set when the SYN was sent more than once. Which of them the
	// answer is to cannot be told, so the connection is not counted
	// (Karn's rule).
	again bool
}

type sample struct {
	at  time.Time
	rtt time.Duration
}

// Meter collects round trips from packets shown to it.
type Meter struct {
	mu      sync.Mutex
	pending map[flow]syn
	samples []sample
	last    time.Duration
	seen    bool
	now     func() time.Time
}

// New returns a Meter with nothing measured.
func New() *Meter {
	return &Meter{pending: map[flow]syn{}, now: time.Now}
}

// Latency is the shortest round trip seen in the last Window. When nothing
// was seen in that time it is the last figure there was, held rather than
// dropped: a quiet tunnel is not a slower one. ok is false until the first
// round trip.
func (m *Meter) Latency() (time.Duration, bool) {
	m.mu.Lock()
	defer m.mu.Unlock()
	if !m.seen {
		return 0, false
	}
	m.expireLocked(m.now())
	if len(m.samples) == 0 {
		return m.last, true
	}
	least := m.samples[0].rtt
	for _, s := range m.samples[1:] {
		least = min(least, s.rtt)
	}
	m.last = least
	return least, true
}

// Forget drops everything measured so far, so that what comes next is
// measured on its own.
func (m *Meter) Forget() {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.samples = m.samples[:0]
	m.seen = false
	m.last = 0
}

// Milliseconds is Latency in whole milliseconds for a status to carry, or
// zero, which a status leaves out, when there is none yet. A round trip under
// a millisecond is one rather than none. A nil Meter has none.
func (m *Meter) Milliseconds() int64 {
	if m == nil {
		return 0
	}
	latency, ok := m.Latency()
	if !ok {
		return 0
	}
	return max(latency.Milliseconds(), 1)
}

// Outbound is shown a packet the system is sending into the tunnel.
func (m *Meter) Outbound(packet []byte) {
	f, flags, seq, _, ok := parseTCP(packet)
	if !ok || flags&(flagSYN|flagACK) != flagSYN {
		return
	}
	now := m.now()
	m.mu.Lock()
	defer m.mu.Unlock()
	if earlier, ok := m.pending[f]; ok {
		earlier.again = true
		m.pending[f] = earlier
		return
	}
	if len(m.pending) >= maxPending {
		m.expireLocked(now)
		if len(m.pending) >= maxPending {
			return
		}
	}
	m.pending[f] = syn{at: now, seq: seq}
}

// Inbound is shown a packet coming out of the tunnel to the system.
func (m *Meter) Inbound(packet []byte) {
	f, flags, _, ack, ok := parseTCP(packet)
	if !ok || flags&(flagSYN|flagACK) != flagSYN|flagACK {
		return
	}
	// Coming back, the remote end is the source.
	f = flow{local: f.remote, remote: f.local, localPort: f.remotePort, remotePort: f.localPort}
	now := m.now()
	m.mu.Lock()
	defer m.mu.Unlock()
	sent, ok := m.pending[f]
	if !ok {
		return
	}
	delete(m.pending, f)
	if sent.again || ack != sent.seq+1 {
		return
	}
	rtt := now.Sub(sent.at)
	if rtt <= 0 || rtt > pendingFor {
		return
	}
	if len(m.samples) == maxSamples {
		m.samples = append(m.samples[:0], m.samples[1:]...)
	}
	m.samples = append(m.samples, sample{at: now, rtt: rtt})
	m.seen = true
}

func (m *Meter) expireLocked(now time.Time) {
	keep := m.samples[:0]
	for _, s := range m.samples {
		if now.Sub(s.at) <= Window {
			keep = append(keep, s)
		}
	}
	// Remember the figure the expiring samples gave, so a quiet tunnel holds
	// it rather than forgetting it.
	if len(keep) == 0 && len(m.samples) > 0 {
		least := m.samples[0].rtt
		for _, s := range m.samples[1:] {
			least = min(least, s.rtt)
		}
		m.last = least
	}
	m.samples = keep
	for f, s := range m.pending {
		if now.Sub(s.at) > pendingFor {
			delete(m.pending, f)
		}
	}
}

const (
	flagSYN = 0x02
	flagACK = 0x10
)

// parseTCP reads what the meter needs from an IPv4 or IPv6 packet carrying
// TCP, and nothing else. Anything it does not understand is not TCP to it.
func parseTCP(p []byte) (f flow, flags byte, seq, ack uint32, ok bool) {
	if len(p) < 1 {
		return
	}
	var segment []byte
	switch p[0] >> 4 {
	case 4:
		if len(p) < 20 {
			return
		}
		ihl := int(p[0]&0x0f) * 4
		total := int(binary.BigEndian.Uint16(p[2:4]))
		// Not TCP, or a fragment other than the first: no header to read.
		if ihl < 20 || ihl > len(p) || p[9] != 6 || binary.BigEndian.Uint16(p[6:8])&0x1fff != 0 {
			return
		}
		if total > len(p) || total < ihl {
			total = len(p)
		}
		f.local = netip.AddrFrom4([4]byte(p[12:16]))
		f.remote = netip.AddrFrom4([4]byte(p[16:20]))
		segment = p[ihl:total]
	case 6:
		// Extension headers are rare on a SYN and are not followed; such a
		// packet is simply not counted.
		if len(p) < 40 || p[6] != 6 {
			return
		}
		f.local = netip.AddrFrom16([16]byte(p[8:24]))
		f.remote = netip.AddrFrom16([16]byte(p[24:40]))
		segment = p[40:]
	default:
		return
	}
	if len(segment) < 20 {
		return
	}
	f.localPort = binary.BigEndian.Uint16(segment[0:2])
	f.remotePort = binary.BigEndian.Uint16(segment[2:4])
	seq = binary.BigEndian.Uint32(segment[4:8])
	ack = binary.BigEndian.Uint32(segment[8:12])
	flags = segment[13]
	ok = true
	return
}

// Device shows a Meter every packet that crosses a tun device, and changes
// nothing about them.
type Device struct {
	tun.Device
	meter *Meter
}

// Wrap returns device with meter watching it.
func Wrap(device tun.Device, meter *Meter) tun.Device {
	return &Device{Device: device, meter: meter}
}

// Read is the system sending: packets on their way into the tunnel.
func (d *Device) Read(bufs [][]byte, sizes []int, offset int) (int, error) {
	n, err := d.Device.Read(bufs, sizes, offset)
	for i := 0; i < n && i < len(bufs) && i < len(sizes); i++ {
		if end := offset + sizes[i]; sizes[i] > 0 && end <= len(bufs[i]) {
			d.meter.Outbound(bufs[i][offset:end])
		}
	}
	return n, err
}

// Write is the tunnel delivering: packets on their way to the system. They
// are looked at before they are handed on, because a device may reuse or
// coalesce the buffers it is given.
func (d *Device) Write(bufs [][]byte, offset int) (int, error) {
	for _, buf := range bufs {
		if offset < len(buf) {
			d.meter.Inbound(buf[offset:])
		}
	}
	return d.Device.Write(bufs, offset)
}
