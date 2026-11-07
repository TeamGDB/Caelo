package rtt

import (
	"bytes"
	"encoding/binary"
	"net/netip"
	"os"
	"testing"
	"time"

	"github.com/amnezia-vpn/amneziawg-go/v3/tun"
)

var (
	phone  = netip.MustParseAddr("10.8.1.2")
	site   = netip.MustParseAddr("142.250.74.110")
	phone6 = netip.MustParseAddr("fd00::2")
	site6  = netip.MustParseAddr("2a00:1450:4001:82a::200e")
)

// tcp4 builds an IPv4 TCP segment with the given flags.
func tcp4(src, dst netip.Addr, sport, dport uint16, flags byte, seq, ack uint32) []byte {
	p := make([]byte, 40)
	p[0] = 0x45
	binary.BigEndian.PutUint16(p[2:4], 40)
	p[8] = 64
	p[9] = 6
	copy(p[12:16], src.AsSlice())
	copy(p[16:20], dst.AsSlice())
	segment(p[20:], sport, dport, flags, seq, ack)
	return p
}

func tcp6(src, dst netip.Addr, sport, dport uint16, flags byte, seq, ack uint32) []byte {
	p := make([]byte, 60)
	p[0] = 0x60
	binary.BigEndian.PutUint16(p[4:6], 20)
	p[6] = 6
	p[7] = 64
	copy(p[8:24], src.AsSlice())
	copy(p[24:40], dst.AsSlice())
	segment(p[40:], sport, dport, flags, seq, ack)
	return p
}

func segment(s []byte, sport, dport uint16, flags byte, seq, ack uint32) {
	binary.BigEndian.PutUint16(s[0:2], sport)
	binary.BigEndian.PutUint16(s[2:4], dport)
	binary.BigEndian.PutUint32(s[4:8], seq)
	binary.BigEndian.PutUint32(s[8:12], ack)
	s[12] = 5 << 4
	s[13] = flags
}

const synAck = flagSYN | flagACK

type clock struct{ at time.Time }

func (c *clock) now() time.Time          { return c.at }
func (c *clock) advance(d time.Duration) { c.at = c.at.Add(d) }
func meterAt() (*Meter, *clock) {
	c := &clock{at: time.Unix(1_700_000_000, 0)}
	m := New()
	m.now = c.now
	return m, c
}

// handshake shows the meter a SYN, then its SYN-ACK after rtt.
func handshake(m *Meter, c *clock, port uint16, rtt time.Duration) {
	m.Outbound(tcp4(phone, site, port, 443, flagSYN, 1000, 0))
	c.advance(rtt)
	m.Inbound(tcp4(site, phone, 443, port, synAck, 5000, 1001))
}

func latency(t *testing.T, m *Meter) time.Duration {
	t.Helper()
	got, ok := m.Latency()
	if !ok {
		t.Fatal("no latency yet")
	}
	return got
}

func TestNothingMeasuredUntilAConnectionCompletes(t *testing.T) {
	m, c := meterAt()
	if _, ok := m.Latency(); ok {
		t.Fatal("a figure before any traffic")
	}
	m.Outbound(tcp4(phone, site, 50000, 443, flagSYN, 1, 0))
	c.advance(30 * time.Millisecond)
	if _, ok := m.Latency(); ok {
		t.Fatal("a figure from a SYN with no answer")
	}
}

func TestASynAndItsAnswerAreOneRoundTrip(t *testing.T) {
	m, c := meterAt()
	handshake(m, c, 50000, 42*time.Millisecond)
	if got := latency(t, m); got != 42*time.Millisecond {
		t.Fatalf("latency = %v, want 42ms", got)
	}
}

func TestIPv6CountsToo(t *testing.T) {
	m, c := meterAt()
	m.Outbound(tcp6(phone6, site6, 50000, 443, flagSYN, 7, 0))
	c.advance(33 * time.Millisecond)
	m.Inbound(tcp6(site6, phone6, 443, 50000, synAck, 9, 8))
	if got := latency(t, m); got != 33*time.Millisecond {
		t.Fatalf("latency = %v, want 33ms", got)
	}
}

func TestTheShortestInTheWindowIsTheFigure(t *testing.T) {
	m, c := meterAt()
	handshake(m, c, 50001, 90*time.Millisecond) // a site far beyond the server
	handshake(m, c, 50002, 41*time.Millisecond) // a CDN beside it
	handshake(m, c, 50003, 60*time.Millisecond)
	if got := latency(t, m); got != 41*time.Millisecond {
		t.Fatalf("latency = %v, want the shortest, 41ms", got)
	}
}

func TestTheFigureFollowsTheNetwork(t *testing.T) {
	m, c := meterAt()
	handshake(m, c, 50001, 40*time.Millisecond)
	c.advance(Window + time.Second)
	// Worse network now: the old, better figure has left the window.
	handshake(m, c, 50002, 120*time.Millisecond)
	if got := latency(t, m); got != 120*time.Millisecond {
		t.Fatalf("latency = %v, want 120ms from the new network", got)
	}
}

func TestAQuietTunnelHoldsItsFigure(t *testing.T) {
	m, c := meterAt()
	handshake(m, c, 50001, 55*time.Millisecond)
	c.advance(10 * Window)
	if got := latency(t, m); got != 55*time.Millisecond {
		t.Fatalf("latency = %v after a quiet spell, want 55ms held", got)
	}
	// And keeps holding it on the next look.
	if got := latency(t, m); got != 55*time.Millisecond {
		t.Fatalf("latency = %v on a second look, want 55ms held", got)
	}
}

func TestARetransmittedSynIsNotCounted(t *testing.T) {
	m, c := meterAt()
	m.Outbound(tcp4(phone, site, 50000, 443, flagSYN, 1000, 0))
	c.advance(time.Second)
	m.Outbound(tcp4(phone, site, 50000, 443, flagSYN, 1000, 0))
	c.advance(20 * time.Millisecond)
	m.Inbound(tcp4(site, phone, 443, 50000, synAck, 5000, 1001))
	if _, ok := m.Latency(); ok {
		t.Fatal("an answer to a retransmitted SYN was counted: which SYN it answers is unknown")
	}
	// The connection is forgotten, so a later one on the same ports counts.
	handshake(m, c, 50000, 30*time.Millisecond)
	if got := latency(t, m); got != 30*time.Millisecond {
		t.Fatalf("latency = %v, want 30ms", got)
	}
}

func TestOnlyTheAnswerToThatSynCounts(t *testing.T) {
	m, c := meterAt()
	m.Outbound(tcp4(phone, site, 50000, 443, flagSYN, 1000, 0))
	c.advance(20 * time.Millisecond)
	for _, wrong := range [][]byte{
		tcp4(site, phone, 443, 50000, synAck, 5000, 999),   // acks something else
		tcp4(site, phone, 443, 50001, synAck, 5000, 1001),  // another connection
		tcp4(site, phone, 80, 50000, synAck, 5000, 1001),   // another port on the site
		tcp4(phone, site, 50000, 443, synAck, 5000, 1001),  // wrong direction
		tcp4(site, phone, 443, 50000, flagACK, 5000, 1001), // not a SYN-ACK
		tcp4(netip.MustParseAddr("1.1.1.1"), phone, 443, 50000, synAck, 5000, 1001),
	} {
		m.Inbound(wrong)
	}
	if _, ok := m.Latency(); ok {
		t.Fatal("a packet that does not answer the SYN was counted")
	}
}

func TestAStragglerIsNotCounted(t *testing.T) {
	m, c := meterAt()
	m.Outbound(tcp4(phone, site, 50000, 443, flagSYN, 1000, 0))
	c.advance(pendingFor + time.Second)
	m.Inbound(tcp4(site, phone, 443, 50000, synAck, 5000, 1001))
	if _, ok := m.Latency(); ok {
		t.Fatal("a SYN-ACK after the SYN gave up was counted")
	}
}

func TestOtherTrafficIsIgnored(t *testing.T) {
	m, c := meterAt()
	udp := tcp4(phone, site, 50000, 53, flagSYN, 1000, 0)
	udp[9] = 17
	m.Outbound(udp)
	fragment := tcp4(phone, site, 50000, 443, flagSYN, 1000, 0)
	binary.BigEndian.PutUint16(fragment[6:8], 100) // a later fragment
	m.Outbound(fragment)
	ack := tcp4(phone, site, 50000, 443, flagACK, 1000, 0)
	m.Outbound(ack)
	if len(m.pending) != 0 {
		t.Fatalf("%d flows remembered from traffic that is not a SYN", len(m.pending))
	}
	c.advance(time.Millisecond)
}

func TestIPv4OptionsAreSkipped(t *testing.T) {
	m, c := meterAt()
	p := tcp4(phone, site, 50000, 443, flagSYN, 1000, 0)
	withOptions := append(append(append([]byte(nil), p[:20]...), 1, 1, 1, 0), p[20:]...)
	withOptions[0] = 0x46
	binary.BigEndian.PutUint16(withOptions[2:4], uint16(len(withOptions)))
	m.Outbound(withOptions)
	c.advance(25 * time.Millisecond)
	m.Inbound(tcp4(site, phone, 443, 50000, synAck, 5000, 1001))
	if got := latency(t, m); got != 25*time.Millisecond {
		t.Fatalf("latency = %v, want 25ms", got)
	}
}

func TestWhatIsRememberedIsBounded(t *testing.T) {
	m, c := meterAt()
	// A port scan's worth of connections that never answer.
	for i := range maxPending * 3 {
		m.Outbound(tcp4(phone, site, uint16(10000+i), 443, flagSYN, 1, 0))
	}
	if len(m.pending) > maxPending {
		t.Fatalf("%d pending, want at most %d", len(m.pending), maxPending)
	}
	for i := range maxSamples * 2 {
		handshake(m, c, uint16(i), time.Millisecond)
	}
	if len(m.samples) > maxSamples {
		t.Fatalf("%d samples, want at most %d", len(m.samples), maxSamples)
	}
	// Once the stale ones expire, new connections are remembered again.
	c.advance(pendingFor + time.Second)
	handshake(m, c, 60000, 70*time.Millisecond)
	if got := latency(t, m); got != 70*time.Millisecond {
		t.Fatalf("latency = %v, want 70ms", got)
	}
}

func TestMalformedPacketsAreSafe(t *testing.T) {
	m, _ := meterAt()
	good := tcp4(phone, site, 50000, 443, flagSYN, 1000, 0)
	for n := range len(good) {
		m.Outbound(good[:n])
		m.Inbound(good[:n])
	}
	lying := append([]byte(nil), good...)
	binary.BigEndian.PutUint16(lying[2:4], 65535) // longer than it is
	m.Outbound(lying)
	short := append([]byte(nil), good...)
	short[0] = 0x4f // header longer than the packet
	m.Outbound(short)
	m.Outbound(nil)
	m.Inbound([]byte{0x60})
}

func FuzzMeterNeverPanics(f *testing.F) {
	f.Add(tcp4(phone, site, 1, 2, flagSYN, 3, 0), tcp4(site, phone, 2, 1, synAck, 9, 4))
	f.Add(tcp6(phone6, site6, 1, 2, flagSYN, 3, 0), tcp6(site6, phone6, 2, 1, synAck, 9, 4))
	f.Add([]byte{0x45}, []byte{0x60, 0, 0})
	f.Fuzz(func(t *testing.T, out, in []byte) {
		m, c := meterAt()
		m.Outbound(out)
		c.advance(time.Millisecond)
		m.Inbound(in)
		m.Latency()
	})
}

// tunAdapter is a tun.Device whose reads and writes go to a fakeTun.
type tunAdapter struct{ *fakeTun }

func (tunAdapter) File() *os.File           { return nil }
func (tunAdapter) MTU() (int, error)        { return 1420, nil }
func (tunAdapter) Name() (string, error)    { return "fake", nil }
func (tunAdapter) Events() <-chan tun.Event { return nil }
func (tunAdapter) Close() error             { return nil }
func (tunAdapter) BatchSize() int           { return 3 }

// fakeTun is the system's side of a tun device.
type fakeTun struct {
	toTunnel [][]byte // what Read hands out
	written  [][]byte
}

func (f *fakeTun) Read(bufs [][]byte, sizes []int, offset int) (int, error) {
	n := 0
	for n < len(bufs) && len(f.toTunnel) > 0 {
		sizes[n] = copy(bufs[n][offset:], f.toTunnel[0])
		f.toTunnel = f.toTunnel[1:]
		n++
	}
	return n, nil
}

func (f *fakeTun) Write(bufs [][]byte, offset int) (int, error) {
	for _, b := range bufs {
		f.written = append(f.written, append([]byte(nil), b[offset:]...))
	}
	return len(bufs), nil
}

func TestTheDeviceChangesNothingItCarries(t *testing.T) {
	m, c := meterAt()
	system := &fakeTun{toTunnel: [][]byte{
		tcp4(phone, site, 50000, 443, flagSYN, 1000, 0),
		{0x45, 1, 2},
	}}
	wrapped := Wrap(tunAdapter{system}, m)
	const offset = 16
	bufs := [][]byte{make([]byte, 2048), make([]byte, 2048), make([]byte, 2048)}
	sizes := make([]int, 3)
	n, err := wrapped.Read(bufs, sizes, offset)
	if err != nil || n != 2 {
		t.Fatalf("read %d, %v; want 2", n, err)
	}
	if !bytes.Equal(bufs[0][offset:offset+sizes[0]], tcp4(phone, site, 50000, 443, flagSYN, 1000, 0)) {
		t.Fatal("the SYN was changed on its way into the tunnel")
	}

	c.advance(48 * time.Millisecond)
	answer := tcp4(site, phone, 443, 50000, synAck, 5000, 1001)
	out := append(make([]byte, offset), answer...)
	if written, err := wrapped.Write([][]byte{out}, offset); err != nil || written != 1 {
		t.Fatalf("wrote %d, %v; want 1", written, err)
	}
	if len(system.written) != 1 || !bytes.Equal(system.written[0], answer) {
		t.Fatal("the SYN-ACK was changed on its way to the system")
	}
	if got := latency(t, m); got != 48*time.Millisecond {
		t.Fatalf("latency = %v, want 48ms", got)
	}
}

func TestMillisecondsIsWhatAStatusCarries(t *testing.T) {
	var none *Meter
	if got := none.Milliseconds(); got != 0 {
		t.Fatalf("nil meter = %d, want 0", got)
	}
	m, c := meterAt()
	if got := m.Milliseconds(); got != 0 {
		t.Fatalf("nothing measured = %d, want 0, which a status leaves out", got)
	}
	handshake(m, c, 50000, 300*time.Microsecond)
	if got := m.Milliseconds(); got != 1 {
		t.Fatalf("sub-millisecond = %d, want 1 rather than none", got)
	}
	handshake(m, c, 50001, 200*time.Microsecond)
	c.advance(Window + time.Second)
	handshake(m, c, 50002, 63*time.Millisecond)
	if got := m.Milliseconds(); got != 63 {
		t.Fatalf("= %d, want 63", got)
	}
}

func TestForgetStartsAfresh(t *testing.T) {
	m, c := meterAt()
	handshake(m, c, 50000, 20*time.Millisecond)
	m.Forget()
	if _, ok := m.Latency(); ok {
		t.Fatal("a figure survived Forget")
	}
	handshake(m, c, 50001, 90*time.Millisecond)
	if got := latency(t, m); got != 90*time.Millisecond {
		t.Fatalf("latency = %v, want 90ms on its own, not the forgotten 20ms", got)
	}
}
