package rtt

import (
	"context"
	"io"
	"net/http"
	"testing"
	"time"

	"github.com/amnezia-vpn/amneziawg-go/v3/conn"
	"github.com/amnezia-vpn/amneziawg-go/v3/device"
	"github.com/amnezia-vpn/amneziawg-go/v3/tun/netstack"

	"github.com/TeamGDB/Caelo/core/internal/awg"
	"github.com/TeamGDB/Caelo/core/internal/awgtest"
)

// A real tunnel to a server 80 ms away, carrying ordinary requests: the
// meter finds the round trip in them, and the requests are unaffected.
func TestTheMeterFindsTheRoundTripInRealTraffic(t *testing.T) {
	t.Parallel()

	const delay = 80 * time.Millisecond
	server := awgtest.Start(t, awgtest.Options{Obfuscation: awgtest.Obfuscation, Delay: delay})

	cfg, err := awg.Parse(server.ClientConfig)
	if err != nil {
		t.Fatal(err)
	}
	system, tnet, err := netstack.CreateNetTUN(cfg.Addresses, nil, cfg.MTU)
	if err != nil {
		t.Fatal(err)
	}
	meter := New()
	dev := device.NewDevice(Wrap(system, meter), conn.NewDefaultBind(), device.NewLogger(device.LogLevelSilent, ""))
	defer dev.Close()
	if err := dev.IpcSet(cfg.IPC()); err != nil {
		t.Fatal(err)
	}
	if err := dev.Up(); err != nil {
		t.Fatal(err)
	}

	if _, ok := meter.Latency(); ok {
		t.Fatal("a figure before any traffic")
	}

	// A new connection each time, as a browser opening pages would.
	client := &http.Client{Transport: &http.Transport{
		DialContext:       tnet.DialContext,
		DisableKeepAlives: true,
	}}
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()
	for range 3 {
		request, _ := http.NewRequestWithContext(ctx, http.MethodGet, server.URL, nil)
		response, err := client.Do(request)
		if err != nil {
			t.Fatal(err)
		}
		body, _ := io.ReadAll(response.Body)
		response.Body.Close()
		if string(body) != " 10.154.1.1\n" {
			t.Fatalf("body = %q: the tunnel did not carry the request intact", body)
		}
	}

	latency, ok := meter.Latency()
	if !ok {
		t.Fatal("three connections went through and nothing was measured")
	}
	if latency < delay || latency >= 2*delay {
		t.Fatalf("latency = %v, want one round trip of about %v", latency, delay)
	}
	if server.Requests() != 3 {
		t.Fatalf("server saw %d requests, want 3: the meter must send nothing", server.Requests())
	}
}
