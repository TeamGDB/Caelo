package probe

import (
	"context"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/TeamGDB/Caelo/core/internal/awgtest"
)

func TestRunReportsTheHandshakeRoundTrip(t *testing.T) {
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

func TestMeasureLatencyUsesTheHandshakeWhenTimed(t *testing.T) {
	t.Parallel()

	requests := 0
	web := httptest.NewServer(http.HandlerFunc(func(http.ResponseWriter, *http.Request) { requests++ }))
	defer web.Close()

	at := time.Unix(0, 0)
	clock := newHandshakeClock()
	clock.now = func() time.Time { return at }
	clock.observe(sendingInitiation)
	at = at.Add(37 * time.Millisecond)
	clock.observe(receivedResponse)

	latency, err := measureLatency(context.Background(), web.Client(), web.URL, clock)
	if err != nil {
		t.Fatal(err)
	}
	if latency == nil || *latency != 37 {
		t.Fatalf("latency = %v, want 37", latency)
	}
	if requests != 0 {
		t.Fatalf("requests = %d, want none", requests)
	}
}

func TestMeasureLatencyFallsBackToARequest(t *testing.T) {
	t.Parallel()

	requests := 0
	web := httptest.NewServer(http.HandlerFunc(func(http.ResponseWriter, *http.Request) { requests++ }))
	defer web.Close()

	latency, err := measureLatency(context.Background(), web.Client(), web.URL, newHandshakeClock())
	if err != nil {
		t.Fatal(err)
	}
	if latency == nil || *latency < 0 {
		t.Fatalf("latency = %v, want the request's time", latency)
	}
	if requests != 1 {
		t.Fatalf("requests = %d, want one fallback request", requests)
	}
}

func TestMeasureLatencyFallbackReportsAFailedRequest(t *testing.T) {
	t.Parallel()

	web := httptest.NewServer(http.HandlerFunc(func(http.ResponseWriter, *http.Request) {}))
	url := web.URL
	web.Close()

	if _, err := measureLatency(context.Background(), http.DefaultClient, url, newHandshakeClock()); err == nil {
		t.Fatal("a failed fallback request produced a figure")
	}
}
