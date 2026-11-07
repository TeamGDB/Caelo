// Package probe brings up a single tunnel and makes one request through it.
//
// It runs entirely in userspace on a gVisor netstack: no privileges, no
// interface on the host, and nothing outside the calling process routed through
// the tunnel. That makes it safe to run repeatedly, and it is the smallest
// thing that answers whether a configuration actually works.
package probe

import (
	"context"
	"fmt"
	"io"
	"net/http"
	"net/netip"
	"strings"
	"time"

	"github.com/amnezia-vpn/amneziawg-go/v3/conn"
	"github.com/amnezia-vpn/amneziawg-go/v3/device"
	"github.com/amnezia-vpn/amneziawg-go/v3/tun/netstack"

	"github.com/TeamGDB/Caelo/core/internal/awg"
	"github.com/TeamGDB/Caelo/core/internal/diag"
)

// Result is what a probe found out.
type Result struct {
	Endpoint   string        `json:"endpoint"`
	MTU        int           `json:"mtu"`
	Obfuscated bool          `json:"obfuscated"`
	Status     string        `json:"status"`
	Body       string        `json:"body"`
	Elapsed    time.Duration `json:"-"`
	ElapsedMs  int64         `json:"elapsed_ms"`
	// LatencyMs is the handshake's round trip: the time to the server and
	// back, which is what a person comparing with a speed test means by ping
	// (#154). ElapsedMs stays the whole first request, establishment included,
	// and remains the availability metric used by callers.
	LatencyMs *int64 `json:"latency_ms,omitempty"`
}

// Options configure a single probe run.
type Options struct {
	// URL is fetched through the tunnel. Its response body is what tells you
	// whether traffic really left through the endpoint.
	URL string

	Timeout time.Duration

	// Verbose logs device internals, including handshake progress, to stderr.
	Verbose bool

	// MeasureLatency reports the handshake's round trip as LatencyMs.
	MeasureLatency bool
}

// Run parses configText, brings the tunnel up, and fetches opts.URL through it.
func Run(configText string, opts Options) (*Result, error) {
	if opts.URL == "" {
		opts.URL = "https://ifconfig.me/ip"
	}
	if opts.Timeout <= 0 {
		opts.Timeout = 30 * time.Second
	}

	cfg, err := awg.Parse(configText)
	if err != nil {
		return nil, fmt.Errorf("reading configuration: %w", err)
	}

	dns := cfg.DNS
	if len(dns) == 0 {
		// Resolution happens inside the tunnel, so a resolver reachable only
		// from there is the point rather than a limitation.
		dns = []netip.Addr{netip.MustParseAddr("1.1.1.1")}
	}

	tunnel, tnet, err := netstack.CreateNetTUN(cfg.Addresses, dns, cfg.MTU)
	if err != nil {
		return nil, fmt.Errorf("creating netstack device: %w", err)
	}

	// Verbose is a request for this run, and the ring is shared, so it is set
	// rather than passed: a tunnel already up should start talking too.
	diag.SetVerbose(opts.Verbose)

	clock := newHandshakeClock()
	dev := device.NewDevice(tunnel, conn.NewDefaultBind(), clock.logger(diag.DeviceLogger()))
	defer dev.Close()

	if err := dev.IpcSet(cfg.IPC()); err != nil {
		return nil, fmt.Errorf("configuring device: %w", err)
	}
	if err := dev.Up(); err != nil {
		return nil, fmt.Errorf("bringing device up: %w", err)
	}

	ctx, cancel := context.WithTimeout(context.Background(), opts.Timeout)
	defer cancel()

	client := &http.Client{Transport: &http.Transport{DialContext: tnet.DialContext}}

	status, body, elapsed, err := fetch(ctx, client, opts.URL)
	if err != nil {
		return nil, err
	}

	var latencyMs *int64
	if opts.MeasureLatency {
		latencyMs, err = measureLatency(ctx, client, opts.URL, clock)
		if err != nil {
			return nil, err
		}
	}

	return &Result{
		Endpoint:   cfg.Peer.Endpoint,
		MTU:        cfg.MTU,
		Obfuscated: len(cfg.Obfuscation) > 0,
		Status:     status,
		Body:       body,
		Elapsed:    elapsed,
		ElapsedMs:  elapsed.Milliseconds(),
		LatencyMs:  latencyMs,
	}, nil
}

// measureLatency reports the round trip of the handshake that carried the
// proving request.
//
// A request came back through the tunnel, so a handshake completed and the
// clock saw it. Should it somehow not have — a library upgrade that rewords
// its log lines, say — the figure falls back to what it was before #154, one
// more request over the same connection, rather than turning a working server
// into one with no figure.
func measureLatency(
	ctx context.Context,
	client *http.Client,
	url string,
	clock *handshakeClock,
) (*int64, error) {
	if rtt, ok := clock.roundTrip(); ok {
		ms := rtt.Milliseconds()
		return &ms, nil
	}
	diag.Logf("probe: the handshake was not timed; measuring a request instead")
	_, _, latency, err := fetch(ctx, client, url)
	if err != nil {
		return nil, fmt.Errorf("measuring latency: %w", err)
	}
	ms := latency.Milliseconds()
	return &ms, nil
}

// MaxBody is the largest response a probe reads. The same ceiling the app puts
// on the update manifest it fetches directly, so that a request moved through
// the tunnel does not quietly accept less.
const MaxBody = 256 * 1024

func fetch(ctx context.Context, client *http.Client, url string) (string, string, time.Duration, error) {
	request, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return "", "", 0, err
	}

	started := time.Now()
	response, err := client.Do(request)
	if err != nil {
		return "", "", 0, fmt.Errorf("fetching %s through the tunnel: %w", url, err)
	}
	// One byte past the limit, so that a body which does not fit is refused
	// rather than cut short. A truncated update manifest parses as nothing and
	// reads as "no update", silently and for good (#51).
	body, readErr := io.ReadAll(io.LimitReader(response.Body, MaxBody+1))
	closeErr := response.Body.Close()
	if readErr != nil {
		return "", "", 0, fmt.Errorf("reading response: %w", readErr)
	}
	if len(body) > MaxBody {
		return "", "", 0, fmt.Errorf("response from %s is larger than %d bytes", url, MaxBody)
	}
	if closeErr != nil {
		return "", "", 0, fmt.Errorf("closing response: %w", closeErr)
	}
	return response.Status, strings.TrimSpace(string(body)), time.Since(started), nil
}
