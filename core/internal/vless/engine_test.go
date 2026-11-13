package vless

import (
	"context"
	"io"
	"net/http"
	"strings"
	"testing"
	"time"

	"github.com/TeamGDB/Caelo/core/internal/vless/vlesstest"
)

// fetchThrough asks for url through a running client.
func fetchThrough(t *testing.T, in *instance, url string) string {
	t.Helper()
	client := &http.Client{Transport: &http.Transport{DialContext: in.Dial}, Timeout: 15 * time.Second}
	response, err := client.Get(url)
	if err != nil {
		t.Fatalf("fetching through the server: %v", err)
	}
	defer response.Body.Close()
	body, _ := io.ReadAll(response.Body)
	return string(body)
}

// Each kind of connection carries a request end to end through a real Xray
// server: the link is read, rendered, run, and something comes back.
func TestCarriesTrafficThroughEveryVariant(t *testing.T) {
	for name, variant := range map[string]vlesstest.Variant{
		"reality vision": vlesstest.RealityVision,
		"reality xhttp":  vlesstest.RealityXHTTP,
		"tls xhttp":      vlesstest.TLSXHTTP,
		"tls vision":     vlesstest.TLSVision,
	} {
		t.Run(name, func(t *testing.T) {
			server := vlesstest.Start(t, variant)
			link, err := Parse(server.Link)
			if err != nil {
				t.Fatal(err)
			}
			opts := options{}
			if server.RootCA != "" {
				opts.rootCAs = []string{server.RootCA}
			}
			in, err := start(link, opts)
			if err != nil {
				t.Fatal(err)
			}
			defer in.Close()

			if !in.LastAlive().IsZero() {
				t.Fatal("alive before anything was sent")
			}
			if body := fetchThrough(t, in, server.URL); body != vlesstest.Body {
				t.Fatalf("got %q", body)
			}
			// The counter is polled; give it a beat.
			deadline := time.Now().Add(3 * time.Second)
			for in.LastAlive().IsZero() && time.Now().Before(deadline) {
				time.Sleep(50 * time.Millisecond)
			}
			if in.LastAlive().IsZero() {
				t.Fatal("bytes came back but the server was never seen alive")
			}
		})
	}
}

// A server that does not know the user carries nothing, and the client says
// so rather than reporting a connection.
func TestAWrongUserCarriesNothing(t *testing.T) {
	server := vlesstest.Start(t, vlesstest.RealityVision)
	link, err := Parse(strings.Replace(server.Link, vlesstest.UUID, "00000000-0000-4000-8000-0000000000bb", 1))
	if err != nil {
		t.Fatal(err)
	}
	in, err := start(link, options{})
	if err != nil {
		t.Fatal(err)
	}
	defer in.Close()

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	request, _ := http.NewRequestWithContext(ctx, http.MethodGet, server.URL, nil)
	client := &http.Client{Transport: &http.Transport{DialContext: in.Dial}}
	if response, err := client.Do(request); err == nil {
		body, _ := io.ReadAll(response.Body)
		response.Body.Close()
		if string(body) == vlesstest.Body {
			t.Fatal("a server carried traffic for a user it does not know")
		}
	}
}

// A certificate nobody vouches for is refused: the link cannot turn checks
// off, and the system does not trust the test authority.
func TestRefusesACertificateNobodyVouchesFor(t *testing.T) {
	server := vlesstest.Start(t, vlesstest.TLSXHTTP)
	link, err := Parse(server.Link)
	if err != nil {
		t.Fatal(err)
	}
	in, err := start(link, options{})
	if err != nil {
		t.Fatal(err)
	}
	defer in.Close()

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	request, _ := http.NewRequestWithContext(ctx, http.MethodGet, server.URL, nil)
	client := &http.Client{Transport: &http.Transport{DialContext: in.Dial}}
	if response, err := client.Do(request); err == nil {
		body, _ := io.ReadAll(response.Body)
		response.Body.Close()
		if string(body) == vlesstest.Body {
			t.Fatal("traffic crossed a server whose certificate was not checked")
		}
	}
}

// The address a route was pinned to is what is dialled; the name stays the
// server name and the HTTP host.
func TestDialsThePinnedAddressUnderTheLinksName(t *testing.T) {
	server := vlesstest.Start(t, vlesstest.TLSXHTTP)
	// The link names a host that does not resolve; only the pin can reach it.
	link, err := Parse(strings.Replace(server.Link, "@127.0.0.1:", "@"+vlesstest.ServerName+":", 1))
	if err != nil {
		t.Fatal(err)
	}
	in, err := start(link, options{address: "127.0.0.1", rootCAs: []string{server.RootCA}})
	if err != nil {
		t.Fatal(err)
	}
	defer in.Close()
	if body := fetchThrough(t, in, server.URL); body != vlesstest.Body {
		t.Fatalf("got %q", body)
	}
}

// A quiet tunnel is asked about rather than declared dead: once the last
// answer is old, reading it sends one request through the server, and not
// another until a minute has passed.
func TestAQuietTunnelIsAskedNotAssumed(t *testing.T) {
	server := vlesstest.Start(t, vlesstest.RealityVision)
	link, err := Parse(server.Link)
	if err != nil {
		t.Fatal(err)
	}
	in, err := start(link, options{})
	if err != nil {
		t.Fatal(err)
	}
	defer in.Close()

	old := time.Now().Add(-2 * quietFor)
	in.alive.Store(old.UnixNano())
	if got := in.LastAlive(); !got.Equal(time.Unix(0, old.UnixNano())) {
		t.Fatalf("reading changed the answer: %v", got)
	}
	first := in.proved.Load()
	if first == 0 {
		t.Fatal("a quiet tunnel was not asked about")
	}
	in.LastAlive()
	if in.proved.Load() != first {
		t.Fatal("asked again within the minute")
	}
}
