// Package probe brings up a single tunnel and makes one request through it.
//
// It runs entirely in userspace on a gVisor netstack: no privileges, no
// interface on the host, and nothing outside the calling process routed through
// the tunnel. That makes it safe to run repeatedly, and it is the smallest
// thing that answers whether a configuration actually works.
package probe

import (
	"context"
	"errors"
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
	"github.com/TeamGDB/Caelo/core/internal/protocol"
	_ "github.com/TeamGDB/Caelo/core/internal/protocol/all"
	"github.com/TeamGDB/Caelo/core/internal/rtt"
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
	// LatencyMs is the round trip from here, through the server and out of
	// its exit, to the nearest CDN: what a speed test run over the tunnel
	// shows, and what the live ping on the main screen measures (#154, #156).
	// For a server that relays to an exit elsewhere it is the whole way, not
	// the first hop. ElapsedMs stays the whole first request, establishment
	// included, and remains the availability metric used by callers.
	LatencyMs *int64 `json:"latency_ms,omitempty"`

	// Protocol is set for nodes of a registered protocol ("vless"). Absent
	// means AmneziaWG, as every result before there was a choice.
	Protocol string `json:"protocol,omitempty"`
}

// Options configure a single probe run.
type Options struct {
	// URL is fetched through the tunnel. Its response body is what tells you
	// whether traffic really left through the endpoint.
	URL string

	Timeout time.Duration

	// Verbose logs device internals, including handshake progress, to stderr.
	Verbose bool

	// MeasureLatency reports LatencyMs.
	MeasureLatency bool

	// LatencyTarget is where the round trip out of the exit is timed to, as
	// host:port with an address for a host, so no lookup is timed with it.
	// Only a TCP handshake is made; nothing is sent over it. Empty means
	// DefaultLatencyTarget.
	LatencyTarget string
}

// DefaultLatencyTarget is Cloudflare's resolver: anycast, so it answers from
// beside nearly every exit, and reachable wherever the tunnel exits.
const DefaultLatencyTarget = "1.1.1.1:443"

// exitDialTimeout bounds the one connection made to time the exit. It does
// not answer within this, and the probe falls back rather than waits.
const exitDialTimeout = 3 * time.Second

// Run parses configText, brings the tunnel up, and fetches opts.URL through it.
func Run(configText string, opts Options) (*Result, error) {
	if opts.URL == "" {
		opts.URL = "https://ifconfig.me/ip"
	}
	if opts.Timeout <= 0 {
		opts.Timeout = 30 * time.Second
	}

	// A protocol registered with the core runs its own way. Anything none of
	// them claims is AmneziaWG, probed exactly as it always was.
	if node, err := protocol.Parse(configText); !errors.Is(err, protocol.ErrNotClaimed) {
		if err != nil {
			return nil, fmt.Errorf("reading configuration: %w", err)
		}
		return runRegistered(node, opts)
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
	meter := rtt.New()
	dev := device.NewDevice(rtt.Wrap(tunnel, meter), conn.NewDefaultBind(), clock.logger(diag.DeviceLogger()))
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
		target := opts.LatencyTarget
		if target == "" {
			target = DefaultLatencyTarget
		}
		latencyMs, err = measureLatency(ctx, latencySources{
			exit:      func(ctx context.Context) (time.Duration, bool) { return timeExit(ctx, tnet, meter, target) },
			handshake: clock.roundTrip,
			request: func(ctx context.Context) (time.Duration, error) {
				_, _, latency, err := fetch(ctx, client, opts.URL)
				return latency, err
			},
		})
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

// runRegistered probes a node of a registered protocol: the same request,
// through whatever that protocol dials with.
//
// Latency is the second request over the connection the first one opened.
// A proxy protocol has no handshake of its own to time, and opening a
// connection through it proves nothing until bytes come back, so the one
// figure that is a round trip out of the exit and back is a request on a
// connection that already exists.
func runRegistered(node protocol.Config, opts Options) (*Result, error) {
	diag.SetVerbose(opts.Verbose)
	description := node.Describe()

	dialer, err := node.Dial()
	if err != nil {
		return nil, err
	}
	defer dialer.Close()

	ctx, cancel := context.WithTimeout(context.Background(), opts.Timeout)
	defer cancel()

	transport := &http.Transport{DialContext: dialer.DialContext}
	defer transport.CloseIdleConnections()
	client := &http.Client{Transport: transport}

	status, body, elapsed, err := fetch(ctx, client, opts.URL)
	if err != nil {
		return nil, err
	}

	var latencyMs *int64
	if opts.MeasureLatency {
		latencyMs, err = measureLatency(ctx, latencySources{
			exit:      func(context.Context) (time.Duration, bool) { return 0, false },
			handshake: func() (time.Duration, bool) { return 0, false },
			request: func(ctx context.Context) (time.Duration, error) {
				_, _, latency, err := fetch(ctx, client, opts.URL)
				return latency, err
			},
		})
		if err != nil {
			return nil, err
		}
	}

	return &Result{
		Endpoint:  description.Endpoint,
		MTU:       description.MTU,
		Status:    status,
		Body:      body,
		Elapsed:   elapsed,
		ElapsedMs: elapsed.Milliseconds(),
		LatencyMs: latencyMs,
		Protocol:  description.Protocol,
	}, nil
}

// latencySources are the ways to time the round trip, best first.
type latencySources struct {
	// exit is the way out through the server's exit to a CDN beside it: the
	// figure wanted (#156).
	exit func(context.Context) (time.Duration, bool)
	// handshake is the way to the server only, which for a server relaying
	// to an exit elsewhere is the shorter part of the trip (#154).
	handshake func() (time.Duration, bool)
	// request is one more request over the proving connection, as before
	// #154.
	request func(context.Context) (time.Duration, error)
}

// measureLatency reports the best figure there is.
//
// Each fallback is what an earlier release measured, so a probe whose exit
// will not take a connection still answers with a figure, as it did then,
// rather than turning a working server into one without.
func measureLatency(ctx context.Context, sources latencySources) (*int64, error) {
	if rtt, ok := sources.exit(ctx); ok {
		ms := max(rtt.Milliseconds(), 1)
		return &ms, nil
	}
	if rtt, ok := sources.handshake(); ok {
		diag.Logf("probe: the exit did not answer; reporting the handshake")
		ms := max(rtt.Milliseconds(), 1)
		return &ms, nil
	}
	diag.Logf("probe: neither the exit nor the handshake was timed; measuring a request instead")
	latency, err := sources.request(ctx)
	if err != nil {
		return nil, fmt.Errorf("measuring latency: %w", err)
	}
	ms := max(latency.Milliseconds(), 1)
	return &ms, nil
}

// timeExit opens one TCP connection to target through the tunnel and closes
// it, and reports the round trip the meter saw for it: the same figure, taken
// the same way, as the live ping once connected. Only this connection counts;
// the proving request may have gone somewhere nearer or further. A SYN that
// had to be sent twice gives no figure (Karn's rule), and the probe falls back.
func timeExit(ctx context.Context, tnet *netstack.Net, meter *rtt.Meter, target string) (time.Duration, bool) {
	ctx, cancel := context.WithTimeout(ctx, exitDialTimeout)
	defer cancel()
	meter.Forget()
	connection, err := tnet.DialContext(ctx, "tcp", target)
	if err != nil {
		diag.Logf("probe: timing the exit: %v", err)
		return 0, false
	}
	connection.Close()
	return meter.Latency()
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
