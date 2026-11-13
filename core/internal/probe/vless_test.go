package probe

import (
	"strings"
	"testing"
	"time"

	"github.com/TeamGDB/Caelo/core/internal/vless/vlesstest"
)

// A VLESS link is probed the way an AmneziaWG configuration is: one request
// through it, its answer, and a round trip measured on the way.
func TestRunProbesAVLESSLink(t *testing.T) {
	for name, variant := range map[string]vlesstest.Variant{
		"vision": vlesstest.RealityVision,
		"xhttp":  vlesstest.RealityXHTTP,
	} {
		t.Run(name, func(t *testing.T) {
			server := vlesstest.Start(t, variant)
			result, err := Run(server.Link, Options{URL: server.URL, Timeout: 15 * time.Second, MeasureLatency: true})
			if err != nil {
				t.Fatal(err)
			}
			if result.Body != vlesstest.Body {
				t.Fatalf("body %q", result.Body)
			}
			if result.Protocol != "vless" || !strings.HasPrefix(result.Endpoint, "127.0.0.1:") {
				t.Fatalf("result %+v", result)
			}
			if result.LatencyMs == nil || *result.LatencyMs < 1 {
				t.Fatalf("latency %v", result.LatencyMs)
			}
		})
	}
}

// A VLESS link that cannot be honoured is refused with its own reason, not
// handed to the AmneziaWG parser to fail for one that makes no sense.
func TestRunRefusesAVLESSLinkWithItsOwnReason(t *testing.T) {
	_, err := Run("vless://00000000-0000-4000-8000-000000000001@192.0.2.1:443?type=ws&security=tls#x", Options{Timeout: time.Second})
	if err == nil || !strings.Contains(err.Error(), "transport") {
		t.Fatalf("got %v", err)
	}
}

func TestRunFailsAgainstAVLESSServerThatIsNotThere(t *testing.T) {
	server := vlesstest.Start(t, vlesstest.RealityVision)
	link := strings.Replace(server.Link, vlesstest.UUID, "00000000-0000-4000-8000-0000000000cc", 1)
	if _, err := Run(link, Options{URL: server.URL, Timeout: 4 * time.Second}); err == nil {
		t.Fatal("a server that does not know the user was reported working")
	}
}
