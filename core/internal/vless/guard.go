package vless

import (
	"time"

	"github.com/TeamGDB/Caelo/core/internal/protocol"
)

type packetGuard interface {
	FD() int
	Close()
	Failed() bool
	Done() <-chan struct{}
	Diagnostics() protocol.TunnelDiagnostics
}

type guardedTunnel struct {
	*instance
	guard packetGuard
}

func (g *guardedTunnel) Close() { g.guard.Close(); g.instance.Close() }
func (g *guardedTunnel) LastAlive() time.Time {
	if g.guard.Failed() {
		return time.Time{}
	}
	return g.instance.LastAlive()
}
func (g *guardedTunnel) WaitAlive(timeout time.Duration) bool {
	return !g.guard.Failed() && g.instance.WaitAlive(timeout) && !g.guard.Failed()
}

var _ protocol.Tunnel = (*guardedTunnel)(nil)

func (g *guardedTunnel) Diagnostics() protocol.TunnelDiagnostics {
	d := g.instance.Diagnostics()
	guard := g.guard.Diagnostics()
	d.Failure = guard.Failure
	for k, v := range guard.Counters {
		d.Counters[k] = v
	}
	return d
}

// A broken bridge must not leave Xray reading a dead datagram peer. The host
// still owns the real device and its routes; only transport resources close.
func closeOnGuardFailure(guard packetGuard, closeTransport func()) {
	<-guard.Done()
	if guard.Failed() {
		closeTransport()
	}
}
