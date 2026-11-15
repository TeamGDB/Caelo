//go:build !windows

package vless

import (
	"errors"
	"fmt"
	"io"
	"os"
	"sync"
	"sync/atomic"
	"time"

	"github.com/TeamGDB/Caelo/core/internal/diag"
	"github.com/TeamGDB/Caelo/core/internal/protocol"
	"golang.org/x/sys/unix"
)

// fdGuard keeps unsupported IPv6 inside the tunnel and passes IPv4 to Xray.
// Datagram boundaries include Apple's four-byte utun family header.
type fdGuard struct {
	original, engine, pump                       *os.File
	prefix                                       int
	once                                         sync.Once
	wg                                           sync.WaitGroup
	closing                                      atomic.Bool
	failure                                      atomic.Pointer[guardFailure]
	done                                         chan struct{}
	hostRead, engineWrite, engineRead, hostWrite atomic.Uint64
	ipv6Filtered, pressure, dropped              atomic.Uint64
	lastHostRead, lastEngineRead, pressureLogged atomic.Int64
}
type guardFailure struct{ message string }

const packetWriteAttempts = 4

func newIPv6Guard(fd, prefix int) (packetGuard, error) {
	duplicate, err := unix.Dup(fd)
	if err != nil {
		return nil, err
	}
	pair, err := unix.Socketpair(unix.AF_UNIX, unix.SOCK_DGRAM, 0)
	if err != nil {
		unix.Close(duplicate)
		return nil, err
	}
	fds := []int{duplicate, pair[0], pair[1]}
	for _, n := range fds {
		unix.CloseOnExec(n)
		if err = unix.SetNonblock(n, true); err != nil {
			for _, v := range fds {
				unix.Close(v)
			}
			return nil, err
		}
	}
	g := &fdGuard{original: os.NewFile(uintptr(duplicate), "vpn-guard"), engine: os.NewFile(uintptr(pair[0]), "xray-guard"), pump: os.NewFile(uintptr(pair[1]), "packet-guard"), prefix: prefix, done: make(chan struct{})}
	g.wg.Add(2)
	go g.fromHost()
	go g.fromEngine()
	diag.Logf("vless: packet guard started: family_header=%d write_attempts=%d", prefix, packetWriteAttempts)
	return g, nil
}
func (g *fdGuard) FD() int               { return int(g.engine.Fd()) }
func (g *fdGuard) Done() <-chan struct{} { return g.done }
func (g *fdGuard) Failed() bool          { return g.failure.Load() != nil }
func (g *fdGuard) Diagnostics() protocol.TunnelDiagnostics {
	d := protocol.TunnelDiagnostics{Counters: map[string]uint64{
		"guard_host_read_packets": g.hostRead.Load(), "guard_engine_write_packets": g.engineWrite.Load(),
		"guard_engine_read_packets": g.engineRead.Load(), "guard_host_write_packets": g.hostWrite.Load(),
		"guard_ipv6_filtered_packets": g.ipv6Filtered.Load(), "guard_write_pressure_events": g.pressure.Load(),
		"guard_dropped_packets": g.dropped.Load(), "guard_last_host_read_ms": uint64(g.lastHostRead.Load()),
		"guard_last_engine_read_ms": uint64(g.lastEngineRead.Load()),
	}}
	if failure := g.failure.Load(); failure != nil {
		d.Failure = failure.message
	}
	return d
}
func (g *fdGuard) stop(err error) {
	// One cause: the other reader will wake with ErrClosed after this closes it.
	g.once.Do(func() {
		if err != nil && !g.closing.Load() {
			g.failure.Store(&guardFailure{message: err.Error()})
			diag.Logf("vless: packet guard stopped: %v", err)
		}
		close(g.done)
		g.original.Close()
		g.engine.Close()
		g.pump.Close()
		diag.Logf("vless: packet guard final counters: %v", g.Diagnostics().Counters)
	})
}
func (g *fdGuard) Close() { g.closing.Store(true); g.stop(nil); g.wg.Wait() }
func writePacket(file *os.File, p []byte) error {
	n, err := file.Write(p)
	if err != nil {
		return err
	}
	if n != len(p) {
		return io.ErrShortWrite
	}
	return nil
}

// Darwin may report ENOBUFS instead of waiting for a Unix datagram reader.
// A bounded retry absorbs brief bursts. If still full, lose one packet (TCP
// can retransmit), not the whole tunnel; closing always interrupts the wait.
func (g *fdGuard) forward(file *os.File, p []byte, direction string) (bool, error) {
	for attempt := 0; ; attempt++ {
		select {
		case <-g.done:
			return false, os.ErrClosed
		default:
		}
		err := writePacket(file, p)
		if err == nil {
			return true, nil
		}
		if !errors.Is(err, unix.ENOBUFS) && !errors.Is(err, unix.EAGAIN) && !errors.Is(err, unix.EINTR) {
			return false, err
		}
		count := g.pressure.Add(1)
		now := time.Now().UnixNano()
		last := g.pressureLogged.Load()
		if (last == 0 || now-last >= int64(10*time.Second)) && g.pressureLogged.CompareAndSwap(last, now) {
			diag.Logf("vless: packet guard temporary write pressure: direction=%s events=%d: %v", direction, count, err)
		}
		if attempt == packetWriteAttempts-1 {
			g.dropped.Add(1)
			return false, nil
		}
		timer := time.NewTimer(time.Millisecond << attempt)
		select {
		case <-g.done:
			timer.Stop()
			return false, os.ErrClosed
		case <-timer.C:
		}
	}
}
func (g *fdGuard) fromHost() {
	defer g.wg.Done()
	buffer := make([]byte, 65535+40+4)
	for {
		n, err := g.original.Read(buffer)
		if err != nil {
			g.stop(err)
			return
		}
		if n <= g.prefix {
			continue
		}
		g.hostRead.Add(1)
		g.lastHostRead.Store(time.Now().UnixMilli())
		packet := buffer[:n]
		var wrote bool
		if packet[g.prefix]>>4 == 6 {
			g.ipv6Filtered.Add(1)
			reply := rejectIPv6(packet[g.prefix:])
			if reply == nil {
				continue
			}
			framed := append(append([]byte(nil), packet[:g.prefix]...), reply...)
			wrote, err = g.forward(g.original, framed, "to_host_ipv6_reject")
			if wrote {
				g.hostWrite.Add(1)
			}
		} else {
			wrote, err = g.forward(g.pump, packet, "to_engine")
			if wrote {
				g.engineWrite.Add(1)
			}
		}
		if err != nil {
			g.stop(fmt.Errorf("forward packet: %w", err))
			return
		}
	}
}
func (g *fdGuard) fromEngine() {
	defer g.wg.Done()
	buffer := make([]byte, 65535+40+4)
	for {
		n, err := g.pump.Read(buffer)
		if err != nil {
			g.stop(err)
			return
		}
		g.engineRead.Add(1)
		g.lastEngineRead.Store(time.Now().UnixMilli())
		wrote, err := g.forward(g.original, buffer[:n], "to_host")
		if err != nil {
			g.stop(fmt.Errorf("return packet: %w", err))
			return
		}
		if wrote {
			g.hostWrite.Add(1)
		}
	}
}
