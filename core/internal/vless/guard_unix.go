//go:build !windows

package vless

import (
	"fmt"
	"io"
	"os"
	"sync"
	"sync/atomic"

	"github.com/TeamGDB/Caelo/core/internal/diag"
	"golang.org/x/sys/unix"
)

// fdGuard держит маршрут IPv6 в туннеле на Apple, но не отдаёт заведомо
// нерабочие соединения TCP-forwarder'у Xray. Unix datagram сохраняет границы
// пакетов; 4-байтный заголовок utun проходит без изменения.
type fdGuard struct {
	original, engine, pump *os.File
	prefix                 int
	once                   sync.Once
	wg                     sync.WaitGroup
	closing                atomic.Bool
	failed                 atomic.Bool
}

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
	g := &fdGuard{original: os.NewFile(uintptr(duplicate), "vpn-guard"), engine: os.NewFile(uintptr(pair[0]), "xray-guard"), pump: os.NewFile(uintptr(pair[1]), "packet-guard"), prefix: prefix}
	g.wg.Add(2)
	go g.fromHost()
	go g.fromEngine()
	return g, nil
}
func (g *fdGuard) FD() int      { return int(g.engine.Fd()) }
func (g *fdGuard) Failed() bool { return g.failed.Load() }
func (g *fdGuard) stop(err error) {
	if err != nil && !g.closing.Load() {
		g.failed.Store(true)
		diag.Logf("vless: packet guard stopped: %v", err)
	}
	g.once.Do(func() { g.original.Close(); g.engine.Close(); g.pump.Close() })
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
		packet := buffer[:n]
		if packet[g.prefix]>>4 == 6 {
			reply := rejectIPv6(packet[g.prefix:])
			if reply == nil {
				continue
			}
			framed := append(append([]byte(nil), packet[:g.prefix]...), reply...)
			err = writePacket(g.original, framed)
		} else {
			err = writePacket(g.pump, packet)
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
		if err = writePacket(g.original, buffer[:n]); err != nil {
			g.stop(err)
			return
		}
	}
}
