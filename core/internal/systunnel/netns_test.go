//go:build linux && netns

package systunnel

// A real run of the desktop tunnel: a kernel tun device, real routes and a
// real AmneziaWG server, all inside a network namespace of its own so that the
// machine running it is not touched. Not part of the ordinary test run, which
// cannot create interfaces. Run it as
//
//	go test -c -tags netns -o /tmp/systunnel.test ./internal/systunnel
//	unshare -rnm /tmp/systunnel.test -test.v -test.run Netns
//
// unshare gives the test root inside a namespace that starts with nothing but
// a loopback device.

import (
	"io"
	"net/http"
	"os/exec"
	"strings"
	"testing"
	"time"

	"github.com/TeamGDB/Caelo/core/internal/awgtest"
	"github.com/TeamGDB/Caelo/core/internal/diag"
)

// The "internet" is one dummy interface: the server's address is on it, and
// the default route points through it.
const serverHost = "192.0.2.1"

func network(t *testing.T) {
	t.Helper()
	for _, args := range [][]string{
		{"link", "set", "lo", "up"},
		{"link", "add", "uplink", "type", "dummy"},
		{"address", "add", serverHost + "/24", "dev", "uplink"},
		{"link", "set", "uplink", "up"},
		{"route", "add", "default", "via", "192.0.2.254", "dev", "uplink", "onlink"},
	} {
		if out, err := exec.Command("ip", args...).CombinedOutput(); err != nil {
			t.Skipf("not in a namespace of our own (ip %v: %v %s); run under unshare -rnm", args, err, out)
		}
	}
}

func TestNetnsDesktopTunnelReportsTheLiveRoundTrip(t *testing.T) {
	network(t)

	const delay = 60 * time.Millisecond
	server := awgtest.Start(t, awgtest.Options{Obfuscation: awgtest.Obfuscation, Delay: delay})

	// The loopback server's configuration, pointed at the "remote" address and
	// carrying everything, as a subscription's would.
	config := strings.Replace(server.ClientConfig, "Endpoint = 127.0.0.1:", "Endpoint = "+serverHost+":", 1)
	config = strings.Replace(config, "AllowedIPs = 10.154.0.0/16", "AllowedIPs = 0.0.0.0/0\nPersistentKeepalive = 25", 1)

	controller := New(false)
	status, err := controller.Start(config)
	if err != nil {
		for _, line := range diag.Lines() {
			t.Log(line)
		}
		t.Fatalf("start: %v", err)
	}
	defer func() {
		if err := controller.Stop(); err != nil {
			t.Errorf("stop: %v", err)
		}
		routes, _ := exec.Command("ip", "route").CombinedOutput()
		if strings.Contains(string(routes), "0.0.0.0/1") {
			t.Errorf("routes left behind:\n%s", routes)
		}
	}()
	t.Logf("up: %+v", *status)

	routes, _ := exec.Command("ip", "route").CombinedOutput()
	t.Logf("routes:\n%s", routes)

	if got := controller.Status().LatencyMs; got != 0 {
		t.Fatalf("latency = %d before any traffic", got)
	}

	// Ordinary requests through the kernel's routing, a new connection each.
	client := &http.Client{
		Timeout:   5 * time.Second,
		Transport: &http.Transport{DisableKeepAlives: true},
	}
	for i := range 5 {
		response, err := client.Get(server.URL)
		if err != nil {
			t.Fatalf("request %d through the tunnel: %v", i, err)
		}
		body, _ := io.ReadAll(response.Body)
		response.Body.Close()
		if strings.TrimSpace(string(body)) != "10.154.1.1" {
			t.Fatalf("body = %q", body)
		}
		got := controller.Status()
		t.Logf("after request %d: latency_ms=%d handshake_unix=%d", i+1, got.LatencyMs, got.HandshakeUnix)
	}

	got := controller.Status()
	latency := time.Duration(got.LatencyMs) * time.Millisecond
	if latency < delay || latency >= 2*delay {
		t.Fatalf("latency = %v, want one round trip of about %v", latency, delay)
	}
	if got.HandshakeUnix == 0 || !got.Up {
		t.Fatalf("status = %+v: the rest of it is missing", got)
	}
	if server.Requests() != 5 {
		t.Fatalf("server saw %d requests, want 5: nothing extra is sent", server.Requests())
	}
}
