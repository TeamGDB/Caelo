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
}

// Options configure a single probe run.
type Options struct {
	// URL is fetched through the tunnel. Its response body is what tells you
	// whether traffic really left through the endpoint.
	URL string

	Timeout time.Duration

	// Verbose logs device internals, including handshake progress, to stderr.
	Verbose bool
}

// Run parses configText, brings the tunnel up, and fetches opts.URL through it.
func Run(configText string, opts Options) (*Result, error) {
	if opts.URL == "" {
		opts.URL = "https://ifconfig.me/ip"
	}
	if opts.Timeout <= 0 {
		opts.Timeout = 30 * time.Second
	}

	cfg, err := awg.ParseConfig(configText)
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

	level := device.LogLevelError
	if opts.Verbose {
		level = device.LogLevelVerbose
	}
	dev := device.NewDevice(tunnel, conn.NewDefaultBind(), device.NewLogger(level, "caelo "))
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

	request, err := http.NewRequestWithContext(ctx, http.MethodGet, opts.URL, nil)
	if err != nil {
		return nil, err
	}

	started := time.Now()
	response, err := client.Do(request)
	if err != nil {
		return nil, fmt.Errorf("fetching %s through the tunnel: %w", opts.URL, err)
	}
	defer response.Body.Close()

	body, err := io.ReadAll(io.LimitReader(response.Body, 4096))
	if err != nil {
		return nil, fmt.Errorf("reading response: %w", err)
	}
	elapsed := time.Since(started)

	return &Result{
		Endpoint:   cfg.Peer.Endpoint,
		MTU:        cfg.MTU,
		Obfuscated: len(cfg.Obfuscation) > 0,
		Status:     response.Status,
		Body:       strings.TrimSpace(string(body)),
		Elapsed:    elapsed,
		ElapsedMs:  elapsed.Milliseconds(),
	}, nil
}
