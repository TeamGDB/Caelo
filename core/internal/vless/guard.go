package vless

import (
	"github.com/TeamGDB/Caelo/core/internal/protocol"
	"time"
)

type packetGuard interface {
	FD() int
	Close()
	Failed() bool
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
