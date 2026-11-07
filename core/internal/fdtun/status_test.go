//go:build android || linux || darwin

package fdtun

import (
	"encoding/json"
	"strings"
	"testing"

	"github.com/TeamGDB/Caelo/core/internal/rtt"
	"github.com/TeamGDB/Caelo/core/internal/rtt/rtttest"
)

func TestStatusCarriesTheLiveRoundTrip(t *testing.T) {
	meter := rtt.New()
	s := &Session{status: Status{Up: true, Endpoint: "203.0.113.1:51820"}, meter: meter}

	if got := s.Status().LatencyMs; got != 0 {
		t.Fatalf("latency = %d before any traffic, want none", got)
	}
	encoded, _ := json.Marshal(s.Status())
	if strings.Contains(string(encoded), "latency_ms") {
		t.Fatalf("%s: no figure yet should mean no field, as an older core sends", encoded)
	}

	rtttest.Connect(meter)
	status := s.Status()
	if status.LatencyMs <= 0 {
		t.Fatalf("latency = %d after a connection, want a figure", status.LatencyMs)
	}
	encoded, _ = json.Marshal(status)
	if !strings.Contains(string(encoded), `"latency_ms":`) {
		t.Fatalf("%s: the figure is missing from what the app reads", encoded)
	}
	// What was there before is untouched.
	if !status.Up || status.Endpoint != "203.0.113.1:51820" {
		t.Fatalf("status = %+v", status)
	}
}

func TestADownTunnelHasNoRoundTrip(t *testing.T) {
	meter := rtt.New()
	rtttest.Connect(meter)
	s := &Session{status: Status{}, meter: meter}
	if got := s.Status().LatencyMs; got != 0 {
		t.Fatalf("latency = %d with nothing up", got)
	}
	s = &Session{status: Status{Up: true}}
	if got := s.Status().LatencyMs; got != 0 {
		t.Fatalf("latency = %d with no meter", got)
	}
}

func TestStopForgetsTheMeter(t *testing.T) {
	s := &Session{}
	s.Stop() // nothing up: must not panic
	if s.meter != nil {
		t.Fatal("a meter outlived its tunnel")
	}
}
