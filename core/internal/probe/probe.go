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
	// LatencyMs is a warm HTTPS round trip through an already proven tunnel.
	// It is intentionally separate from ElapsedMs, whose first request includes
	// tunnel establishment and remains the availability metric used by callers.
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

	// MeasureLatency follows the proving request with one more request over the
	// same tunnel. The second request excludes WireGuard establishment and is
	// suitable for a periodically refreshed value in the UI.
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

	dev := device.NewDevice(tunnel, conn.NewDefaultBind(), diag.DeviceLogger())
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

	status, body, elapsed, latencyMs, err := requestMeasurements(
		ctx,
		client,
		opts.URL,
		opts.MeasureLatency,
	)
	if err != nil {
		return nil, err
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

func requestMeasurements(
	ctx context.Context,
	client *http.Client,
	url string,
	measureLatency bool,
) (string, string, time.Duration, *int64, error) {
	status, body, elapsed, err := fetch(ctx, client, url)
	if err != nil {
		return "", "", 0, nil, err
	}
	if !measureLatency {
		return status, body, elapsed, nil, nil
	}

	_, _, latency, err := fetch(ctx, client, url)
	if err != nil {
		return "", "", 0, nil, fmt.Errorf("measuring latency: %w", err)
	}
	measured := latency.Milliseconds()
	return status, body, elapsed, &measured, nil
}

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
	body, readErr := io.ReadAll(io.LimitReader(response.Body, 4096))
	closeErr := response.Body.Close()
	if readErr != nil {
		return "", "", 0, fmt.Errorf("reading response: %w", readErr)
	}
	if closeErr != nil {
		return "", "", 0, fmt.Errorf("closing response: %w", closeErr)
	}
	return response.Status, strings.TrimSpace(string(body)), time.Since(started), nil
}
