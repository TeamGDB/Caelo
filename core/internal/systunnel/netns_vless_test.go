//go:build linux && netns

package systunnel

// The desktop tunnel with a VLESS node, the same way as the AmneziaWG one in
// netns_test.go: a kernel tun device Xray creates, real routes, and a real
// Xray server behind the namespace's only "uplink". Run it as
//
//	go test -c -tags netns -o /tmp/systunnel.test ./internal/systunnel
//	unshare -rnm /tmp/systunnel.test -test.v -test.run Netns

import (
	"io"
	"net/http"
	"os/exec"
	"strings"
	"testing"
	"time"

	"github.com/TeamGDB/Caelo/core/internal/diag"
	"github.com/TeamGDB/Caelo/core/internal/vless/vlesstest"
)

func TestNetnsDesktopTunnelCarriesVLESS(t *testing.T) {
	network(t)
	diag.SetVerbose(true)

	for name, variant := range map[string]vlesstest.Variant{
		"vision": vlesstest.RealityVision,
		"xhttp":  vlesstest.RealityXHTTP,
	} {
		t.Run(name, func(t *testing.T) {
			// Everything the server carries goes to the web server behind it:
			// there is no internet in here, so the address a request is made
			// to only has to be one the routes send into the tunnel.
			server := vlesstest.StartWith(t, variant, vlesstest.Options{Listen: "0.0.0.0", Redirect: true})
			link := strings.Replace(server.Link, "@127.0.0.1:", "@"+serverHost+":", 1)

			controller := New(true)
			status, err := controller.Start(link)
			if err != nil {
				for _, line := range diag.Lines() {
					t.Log(line)
				}
				t.Fatalf("start: %v", err)
			}
			t.Logf("up: %+v", *status)
			routes, _ := exec.Command("ip", "route").CombinedOutput()
			t.Logf("routes:\n%s", routes)

			client := &http.Client{Timeout: 10 * time.Second, Transport: &http.Transport{DisableKeepAlives: true}}
			for i := range 3 {
				// An address no interface here has: it can only be reached
				// through the default halves, into the tunnel.
				response, err := client.Get("http://203.0.113.80/")
				if err != nil {
					t.Fatalf("request %d through the tunnel: %v", i, err)
				}
				body, _ := io.ReadAll(response.Body)
				response.Body.Close()
				if string(body) != vlesstest.Body {
					t.Fatalf("body = %q", body)
				}
			}

			got := controller.Status()
			if !got.Up || got.Protocol != "VLESS" || got.HandshakeUnix == 0 {
				t.Fatalf("status = %+v", got)
			}

			if err := controller.Stop(); err != nil {
				t.Fatalf("stop: %v", err)
			}
			after, _ := exec.Command("ip", "route").CombinedOutput()
			if strings.Contains(string(after), "0.0.0.0/1") || strings.Contains(string(after), "caelo0") {
				t.Fatalf("routes left behind:\n%s", after)
			}
			if links, _ := exec.Command("ip", "link").CombinedOutput(); strings.Contains(string(links), "caelo0") {
				t.Fatalf("device left behind:\n%s", links)
			}
		})
	}
}
