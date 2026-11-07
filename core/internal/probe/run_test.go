package probe

import (
	"context"
	"errors"
	"strings"
	"testing"
	"time"

	"github.com/TeamGDB/Caelo/core/internal/awgtest"
)

func TestRunReportsTheRoundTrip(t *testing.T) {
	t.Parallel()

	for name, extra := range map[string]string{
		"plain WireGuard": "",
		"obfuscated":      awgtest.Obfuscation,
	} {
		t.Run(name, func(t *testing.T) {
			t.Parallel()
			server := awgtest.Start(t, awgtest.Options{Obfuscation: extra})

			result, err := Run(server.ClientConfig, Options{
				URL:            server.URL,
				Timeout:        15 * time.Second,
				MeasureLatency: true,
				LatencyTarget:  awgtest.FarAddress.String() + ":80",
			})
			if err != nil {
				t.Fatal(err)
			}

			// What callers already rely on is unchanged.
			if result.Body != "10.154.1.1" {
				t.Fatalf("body = %q, want the server's address, trimmed", result.Body)
			}
			if result.Status != "200 OK" {
				t.Fatalf("status = %q", result.Status)
			}
			if result.ElapsedMs != result.Elapsed.Milliseconds() || result.Elapsed <= 0 {
				t.Fatalf("elapsed = %v / %dms", result.Elapsed, result.ElapsedMs)
			}
			if result.Obfuscated != (extra != "") {
				t.Fatalf("obfuscated = %v", result.Obfuscated)
			}

			// The figure is the handshake, not another request.
			if got := server.Requests(); got != 1 {
				t.Fatalf("server saw %d requests, want only the proving one", got)
			}
			if result.LatencyMs == nil {
				t.Fatal("latency_ms is missing")
			}
			if *result.LatencyMs < 0 || *result.LatencyMs > result.ElapsedMs {
				t.Fatalf("latency %dms is outside 0..elapsed %dms", *result.LatencyMs, result.ElapsedMs)
			}
		})
	}
}

// One round trip, not the several a request takes: this is the difference a
// person saw against a speed test (#154).
func TestRunMeasuresOneRoundTripNotARequest(t *testing.T) {
	t.Parallel()

	const delay = 80 * time.Millisecond
	server := awgtest.Start(t, awgtest.Options{Obfuscation: awgtest.Obfuscation, Delay: delay})

	result, err := Run(server.ClientConfig, Options{
		URL:            server.URL,
		Timeout:        15 * time.Second,
		MeasureLatency: true,
		LatencyTarget:  awgtest.FarAddress.String() + ":80",
	})
	if err != nil {
		t.Fatal(err)
	}
	latency := time.Duration(*result.LatencyMs) * time.Millisecond
	if latency < delay || latency >= 2*delay {
		t.Fatalf("latency = %v, want one round trip of about %v", latency, delay)
	}
	// Handshake, TCP, and the request itself: at least three.
	if result.Elapsed < 3*delay {
		t.Fatalf("elapsed = %v, want at least three round trips", result.Elapsed)
	}
}

func TestRunWithoutMeasuringLeavesLatencyOut(t *testing.T) {
	t.Parallel()
	server := awgtest.Start(t, awgtest.Options{})

	result, err := Run(server.ClientConfig, Options{URL: server.URL, Timeout: 15 * time.Second})
	if err != nil {
		t.Fatal(err)
	}
	if result.LatencyMs != nil {
		t.Fatalf("latency = %d, want none from a plain probe", *result.LatencyMs)
	}
	if got := server.Requests(); got != 1 {
		t.Fatalf("server saw %d requests, want 1", got)
	}
}

func TestRunFailsAgainstAServerThatDoesNotAnswer(t *testing.T) {
	t.Parallel()
	server := awgtest.Start(t, awgtest.Options{})

	// Same server, wrong obfuscation: it drops every packet, as a real one
	// would. No figure is invented for it.
	_, err := Run(strings.Replace(server.ClientConfig, "[Peer]", "Jc = 3\nJmin = 10\nJmax = 20\nH1 = 77\n[Peer]", 1), Options{
		URL:            server.URL,
		Timeout:        2 * time.Second,
		MeasureLatency: true,
	})
	if err == nil {
		t.Fatal("a server that never answered was reported as working")
	}
}

// A server that relays to an exit elsewhere: quick to shake hands with, slow
// to get anywhere through. The figure is the whole way, as a speed test over
// the tunnel would show it, not the first hop (#156).
func TestRunMeasuresTheWayOutThroughARelay(t *testing.T) {
	t.Parallel()

	const entry, exit = 20 * time.Millisecond, 70 * time.Millisecond
	server := awgtest.Start(t, awgtest.Options{
		Obfuscation: awgtest.Obfuscation,
		Delay:       entry,
		ExitDelay:   exit,
	})

	result, err := Run(server.ClientConfig, Options{
		// The proving request goes to the server itself, entry away: it
		// must not stand in for the way out.
		URL:            server.URL,
		Timeout:        15 * time.Second,
		MeasureLatency: true,
		LatencyTarget:  awgtest.FarAddress.String() + ":80",
	})
	if err != nil {
		t.Fatal(err)
	}
	latency := time.Duration(*result.LatencyMs) * time.Millisecond
	if whole := entry + exit; latency < whole || latency >= 2*whole {
		t.Fatalf("latency = %v, want the whole way out, about %v, not the %v to the server", latency, whole, entry)
	}
	if server.Requests() != 1 {
		t.Fatalf("server saw %d requests: timing the exit must send nothing over the connection", server.Requests())
	}
}

func TestRunFallsBackToTheHandshakeWhenTheExitDoesNotAnswer(t *testing.T) {
	t.Parallel()

	const delay = 40 * time.Millisecond
	server := awgtest.Start(t, awgtest.Options{Delay: delay})

	started := time.Now()
	result, err := Run(server.ClientConfig, Options{
		URL:            server.URL,
		Timeout:        15 * time.Second,
		MeasureLatency: true,
		// Nothing listens there: the connection is refused or never answered.
		LatencyTarget: "10.154.9.9:443",
	})
	if err != nil {
		t.Fatal(err)
	}
	if result.LatencyMs == nil {
		t.Fatal("no figure: a working server must keep one")
	}
	latency := time.Duration(*result.LatencyMs) * time.Millisecond
	// The handshake's crypto is slow under the race detector, so only the
	// floor is exact: a figure that is at least one round trip.
	if latency < delay || latency > delay+500*time.Millisecond {
		t.Fatalf("latency = %v, want the handshake, about %v", latency, delay)
	}
	if took := time.Since(started); took > exitDialTimeout+5*time.Second {
		t.Fatalf("the probe took %v waiting for an exit that does not answer", took)
	}
}

func sources(exit time.Duration, exitOK bool, handshake time.Duration, handshakeOK bool, request func() (time.Duration, error)) latencySources {
	return latencySources{
		exit:      func(context.Context) (time.Duration, bool) { return exit, exitOK },
		handshake: func() (time.Duration, bool) { return handshake, handshakeOK },
		request:   func(context.Context) (time.Duration, error) { return request() },
	}
}

func TestMeasureLatencyPrefersTheWayOut(t *testing.T) {
	t.Parallel()
	asked := false
	latency, err := measureLatency(context.Background(), sources(
		93*time.Millisecond, true, 32*time.Millisecond, true,
		func() (time.Duration, error) { asked = true; return 0, nil },
	))
	if err != nil || latency == nil || *latency != 93 {
		t.Fatalf("latency = %v, %v; want 93 from the exit", latency, err)
	}
	if asked {
		t.Fatal("a request was made although the exit answered")
	}
}

func TestMeasureLatencyFallsBackToTheHandshake(t *testing.T) {
	t.Parallel()
	latency, err := measureLatency(context.Background(), sources(
		0, false, 32*time.Millisecond, true,
		func() (time.Duration, error) { t.Fatal("a request was made"); return 0, nil },
	))
	if err != nil || latency == nil || *latency != 32 {
		t.Fatalf("latency = %v, %v; want 32 from the handshake", latency, err)
	}
}

func TestMeasureLatencyFallsBackToARequest(t *testing.T) {
	t.Parallel()
	latency, err := measureLatency(context.Background(), sources(
		0, false, 0, false,
		func() (time.Duration, error) { return 140 * time.Millisecond, nil },
	))
	if err != nil || latency == nil || *latency != 140 {
		t.Fatalf("latency = %v, %v; want 140 from the request", latency, err)
	}
}

func TestMeasureLatencyFallbackReportsAFailedRequest(t *testing.T) {
	t.Parallel()
	if _, err := measureLatency(context.Background(), sources(
		0, false, 0, false,
		func() (time.Duration, error) { return 0, errors.New("refused") },
	)); err == nil {
		t.Fatal("a failed fallback request produced a figure")
	}
}

func TestMeasureLatencyNeverReportsZero(t *testing.T) {
	t.Parallel()
	latency, _ := measureLatency(context.Background(), sources(
		300*time.Microsecond, true, 0, false, nil,
	))
	if latency == nil || *latency != 1 {
		t.Fatalf("latency = %v, want 1: zero reads as no figure in the app", latency)
	}
}
