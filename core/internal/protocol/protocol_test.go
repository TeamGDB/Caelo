package protocol_test

import (
	"errors"
	"slices"
	"testing"

	"github.com/TeamGDB/Caelo/core/internal/protocol"
	_ "github.com/TeamGDB/Caelo/core/internal/protocol/all"
)

const link = "vless://00000000-0000-4000-8000-000000000001@192.0.2.10:443?type=tcp&flow=xtls-rprx-vision&security=reality&sni=edge.example.com&pbk=AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8&sid=01&fp=safari#n"

// AmneziaWG is nobody's to claim: whatever reaches the old path does so
// because no registered protocol wanted it, which is what keeps that path
// exactly as it was.
func TestAmneziaWGIsLeftToTheOriginalPath(t *testing.T) {
	for _, text := range []string{
		"[Interface]\nPrivateKey = x\n[Peer]\nEndpoint = 192.0.2.1:51820\n",
		`{"type":"amneziawg","peers":[]}`,
		"",
	} {
		if _, err := protocol.Parse(text); !errors.Is(err, protocol.ErrNotClaimed) {
			t.Fatalf("%q was claimed: %v", text, err)
		}
	}
}

func TestVLESSIsClaimedAndDescribed(t *testing.T) {
	node, err := protocol.Parse(link)
	if err != nil {
		t.Fatal(err)
	}
	d := node.Describe()
	if d.Protocol != "vless" || d.Variant != "vless-reality-vision" || d.Endpoint != "192.0.2.10:443" {
		t.Fatalf("%+v", d)
	}
	if !slices.Contains(d.AllowedIPs, "::/0") || len(d.Addresses) != 2 || len(d.DNS) == 0 || d.MTU == 0 {
		t.Fatalf("device: %+v", d)
	}
}

func TestPinningAnAddressKeepsIt(t *testing.T) {
	node, err := protocol.Parse(link)
	if err != nil {
		t.Fatal(err)
	}
	_, address, err := node.Pin(t.Context())
	if err != nil || address != "192.0.2.10" {
		t.Fatalf("%q %v", address, err)
	}
}

func TestListsWhatTheBuildCarries(t *testing.T) {
	if names := protocol.Names(); !slices.Equal(names, []string{"amneziawg", "vless"}) {
		t.Fatalf("names %v", names)
	}
	if variants := protocol.Capabilities(); !slices.Contains(variants, "vless-tls-xhttp") {
		t.Fatalf("variants %v", variants)
	}
	if versions := protocol.Versions(); versions["vless"] == "" {
		t.Fatalf("versions %v", versions)
	}
}

func TestRefusesAnIncompleteOrDuplicateRegistration(t *testing.T) {
	for name, p := range map[string]protocol.Protocol{
		"no name":   {Claims: func(string) bool { return false }},
		"amneziawg": {Name: "amneziawg", Claims: func(string) bool { return false }},
		"duplicate": {Name: "vless", Claims: func(string) bool { return false }},
	} {
		func() {
			defer func() {
				if recover() == nil {
					t.Errorf("%s: registered", name)
				}
			}()
			if p.Parse == nil {
				p.Parse = func(string) (protocol.Config, error) { return nil, nil }
			}
			protocol.Register(p)
		}()
	}
}
