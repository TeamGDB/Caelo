package tunnel

import (
	"testing"
	"time"

	"github.com/TeamGDB/Caelo/core/internal/vless/vlesstest"
)

// The in-process tunnel carries a VLESS node the way it carries AmneziaWG:
// up, a request through it, and down.
func TestConnectsThroughAVLESSNode(t *testing.T) {
	server := vlesstest.Start(t, vlesstest.RealityXHTTP)
	session := New()
	info, err := session.Connect(server.Link)
	if err != nil {
		t.Fatal(err)
	}
	if info.Protocol != "VLESS" {
		t.Fatalf("info %+v", info)
	}
	if up, endpoint := session.Up(); !up || endpoint == "" {
		t.Fatal("not up")
	}
	result, err := session.Check(server.URL, 15*time.Second)
	if err != nil {
		t.Fatal(err)
	}
	if result.Address != vlesstest.Body {
		t.Fatalf("got %q", result.Address)
	}
	session.Disconnect()
	if up, _ := session.Up(); up {
		t.Fatal("still up")
	}
	if _, err := session.Check(server.URL, time.Second); err != ErrNotConnected {
		t.Fatalf("after disconnect: %v", err)
	}
}
