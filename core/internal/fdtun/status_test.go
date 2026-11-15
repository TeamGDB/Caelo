//go:build android || linux || darwin

package fdtun

import (
	"encoding/json"
	"strings"
	"testing"
	"time"

	"github.com/TeamGDB/Caelo/core/internal/protocol"
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

type diagnosedTunnel struct {
	failure string
	polls   int
}

func (d *diagnosedTunnel) LastAlive() time.Time         { d.polls++; return time.Unix(123, 0) }
func (d *diagnosedTunnel) WaitAlive(time.Duration) bool { return d.failure == "" }
func (d *diagnosedTunnel) Close()                       {}
func (d *diagnosedTunnel) Diagnostics() protocol.TunnelDiagnostics {
	return protocol.TunnelDiagnostics{Failure: d.failure, Counters: map[string]uint64{"guard_write_pressure_events": 9}}
}
func TestLocalPacketFailureIsNotReportedAsUp(t *testing.T) {
	tunnel := &diagnosedTunnel{}
	session := &Session{status: Status{Up: true, Protocol: "VLESS"}, tunnel: tunnel}
	live := session.Status()
	if !live.Up || live.Diagnostics.Counters["guard_write_pressure_events"] != 9 {
		t.Fatal("pressure alone must not stop a healthy tunnel")
	}
	tunnel.failure = "forward packet: file already closed"
	failed := session.Status()
	if failed.Up || failed.HandshakeUnix != 0 || failed.Diagnostics.Failure != tunnel.failure {
		t.Fatalf("hidden packet failure: %+v", failed)
	}
	data, err := json.Marshal(failed)
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(data), `"failure":"forward packet: file already closed"`) {
		t.Fatalf("failure missing from FFI payload: %s", data)
	}
}

func TestDiagnosticsDoesNotStartRemoteReachabilityChecks(t *testing.T) {
	tunnel := &diagnosedTunnel{}
	session := &Session{status: Status{Up: true}, tunnel: tunnel}
	if got := session.Diagnostics(); !got.Up || got.Diagnostics == nil {
		t.Fatalf("local snapshot missing: %+v", got)
	}
	if tunnel.polls != 0 {
		t.Fatal("local diagnostics called active reachability check")
	}
	_ = session.Status()
	if tunnel.polls != 1 {
		t.Fatal("control status did not poll reachability")
	}
	tunnel.polls = 0
	tunnel.failure = "closed descriptor"
	if session.Diagnostics().Up {
		t.Fatal("local failure missing")
	}
	if tunnel.polls != 0 {
		t.Fatal("failed local diagnostics dialled remotely")
	}
}
