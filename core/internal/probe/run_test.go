package probe

import (
	"context"
	"crypto/rand"
	"encoding/base64"
	"fmt"
	"net"
	"net/http"
	"net/http/httptest"
	"net/netip"
	"strings"
	"testing"
	"time"

	"github.com/amnezia-vpn/amneziawg-go/v3/conn"
	"github.com/amnezia-vpn/amneziawg-go/v3/device"
	"github.com/amnezia-vpn/amneziawg-go/v3/tun/netstack"
	"golang.org/x/crypto/curve25519"

	"github.com/TeamGDB/Caelo/core/internal/awg"
)

// obfuscation is a full AWG 1.5 set, so that the clock is shown to work when
// headers and sizes no longer say what a packet is.
const obfuscation = "Jc = 4\nJmin = 10\nJmax = 50\n" +
	"S1 = 31\nS2 = 17\n" +
	"H1 = 1000000-1000100\nH2 = 2000000-2000100\n" +
	"H3 = 3000000-3000100\nH4 = 4000000-4000100\n"

// loopbackServer is an AmneziaWG server on 127.0.0.1 with a web server inside
// its tunnel, which answers with the server's tunnel address.
type loopbackServer struct {
	clientConfig string
	url          string
	requests     func() int
}

func startLoopbackServer(t *testing.T, extra string, delay time.Duration) loopbackServer {
	t.Helper()

	serverKey, serverPublic := base64KeyPair(t)
	clientKey, clientPublic := base64KeyPair(t)
	port := freeUDPPort(t)
	serverAddr := netip.MustParseAddr("10.154.1.1")

	serverCfg, err := awg.ParseConfig("[Interface]\n" +
		"PrivateKey = " + serverKey + "\n" +
		"Address = " + serverAddr.String() + "/32\n" + extra +
		"[Peer]\n" +
		"PublicKey = " + clientPublic + "\n" +
		"AllowedIPs = 10.154.1.2/32\n")
	if err != nil {
		t.Fatal(err)
	}
	tun, tnet, err := netstack.CreateNetTUN(serverCfg.Addresses, nil, serverCfg.MTU)
	if err != nil {
		t.Fatal(err)
	}
	// Every packet the server sends is held back by delay, so the round trip
	// is something to measure rather than loopback's microseconds.
	var bind conn.Bind = conn.NewDefaultBind()
	if delay > 0 {
		bind = &delayedBind{Bind: bind, delay: delay}
	}
	dev := device.NewDevice(tun, bind, device.NewLogger(device.LogLevelSilent, ""))
	t.Cleanup(dev.Close)

	if err := dev.IpcSet(fmt.Sprintf("listen_port=%d\n", port) + serverCfg.IPC()); err != nil {
		t.Fatal(err)
	}
	if err := dev.Up(); err != nil {
		t.Fatal(err)
	}

	listener, err := tnet.ListenTCP(&net.TCPAddr{IP: serverAddr.AsSlice(), Port: 80})
	if err != nil {
		t.Fatal(err)
	}
	count := make(chan int, 1)
	count <- 0
	web := &http.Server{Handler: http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		n := <-count
		count <- n + 1
		_, _ = w.Write([]byte(" " + serverAddr.String() + "\n"))
	})}
	go func() { _ = web.Serve(listener) }()
	t.Cleanup(func() { _ = web.Close() })

	return loopbackServer{
		clientConfig: "[Interface]\n" +
			"PrivateKey = " + clientKey + "\n" +
			"Address = 10.154.1.2/32\n" + extra +
			"[Peer]\n" +
			"PublicKey = " + serverPublic + "\n" +
			fmt.Sprintf("Endpoint = 127.0.0.1:%d\n", port) +
			"AllowedIPs = 10.154.1.0/24\n",
		url: "http://" + serverAddr.String() + "/",
		requests: func() int {
			n := <-count
			count <- n
			return n
		},
	}
}

func TestRunReportsTheHandshakeRoundTrip(t *testing.T) {
	t.Parallel()

	for name, extra := range map[string]string{
		"plain WireGuard": "",
		"obfuscated":      obfuscation,
	} {
		t.Run(name, func(t *testing.T) {
			t.Parallel()
			server := startLoopbackServer(t, extra, 0)

			result, err := Run(server.clientConfig, Options{
				URL:            server.url,
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
			if got := server.requests(); got != 1 {
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
	server := startLoopbackServer(t, obfuscation, delay)

	result, err := Run(server.clientConfig, Options{
		URL:            server.url,
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
	server := startLoopbackServer(t, "", 0)

	result, err := Run(server.clientConfig, Options{URL: server.url, Timeout: 15 * time.Second})
	if err != nil {
		t.Fatal(err)
	}
	if result.LatencyMs != nil {
		t.Fatalf("latency = %d, want none from a plain probe", *result.LatencyMs)
	}
	if got := server.requests(); got != 1 {
		t.Fatalf("server saw %d requests, want 1", got)
	}
}

func TestRunFailsAgainstAServerThatDoesNotAnswer(t *testing.T) {
	t.Parallel()
	server := startLoopbackServer(t, "", 0)

	// Same server, wrong obfuscation: it drops every packet, as a real one
	// would. No figure is invented for it.
	_, err := Run(strings.Replace(server.clientConfig, "[Peer]", "Jc = 3\nJmin = 10\nJmax = 20\nH1 = 77\n[Peer]", 1), Options{
		URL:            server.url,
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

func base64KeyPair(t *testing.T) (private, public string) {
	t.Helper()
	var key [32]byte
	if _, err := rand.Read(key[:]); err != nil {
		t.Fatal(err)
	}
	key[0] &= 248
	key[31] = key[31]&127 | 64
	pub, err := curve25519.X25519(key[:], curve25519.Basepoint)
	if err != nil {
		t.Fatal(err)
	}
	return base64.StdEncoding.EncodeToString(key[:]), base64.StdEncoding.EncodeToString(pub)
}

// delayedBind sends every packet late, like a server far away.
type delayedBind struct {
	conn.Bind
	delay time.Duration
}

func (b *delayedBind) Send(bufs [][]byte, ep conn.Endpoint) error {
	copied := make([][]byte, len(bufs))
	for i, buf := range bufs {
		copied[i] = append([]byte(nil), buf...)
	}
	time.AfterFunc(b.delay, func() { _ = b.Bind.Send(copied, ep) })
	return nil
}
