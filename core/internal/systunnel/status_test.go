package systunnel

import (
	"testing"

	"github.com/TeamGDB/Caelo/core/internal/rtt"
	"github.com/TeamGDB/Caelo/core/internal/rtt/rtttest"
)

func TestStatusCarriesTheLiveRoundTrip(t *testing.T) {
	meter := rtt.New()
	c := &Controller{status: Status{Up: true, Interface: "caelo0"}, meter: meter}
	if got := c.Status().LatencyMs; got != 0 {
		t.Fatalf("latency = %d before any traffic, want none", got)
	}
	rtttest.Connect(meter)
	status := c.Status()
	if status.LatencyMs <= 0 {
		t.Fatalf("latency = %d after a connection, want a figure", status.LatencyMs)
	}
	if !status.Up || status.Interface != "caelo0" || status.HandshakeUnix != 0 {
		t.Fatalf("status = %+v: the rest changed", status)
	}
}

func TestADownTunnelHasNoRoundTrip(t *testing.T) {
	meter := rtt.New()
	rtttest.Connect(meter)
	c := &Controller{meter: meter}
	if got := c.Status().LatencyMs; got != 0 {
		t.Fatalf("latency = %d with nothing up", got)
	}
}
