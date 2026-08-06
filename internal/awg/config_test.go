package awg

import (
	"encoding/base64"
	"strings"
	"testing"
)

// fakeKey returns a syntactically valid Curve25519 key. Tests never carry real
// key material: a config file in a repository is a config file in a backup, in
// a CI log, and eventually in a search index.
func fakeKey(fill byte) string {
	raw := make([]byte, 32)
	for i := range raw {
		raw[i] = fill
	}
	return base64.StdEncoding.EncodeToString(raw)
}

func minimalConfig() string {
	return "[Interface]\n" +
		"PrivateKey = " + fakeKey(1) + "\n" +
		"Address = 10.8.1.23/32\n" +
		"[Peer]\n" +
		"PublicKey = " + fakeKey(2) + "\n"
}

func TestParseMinimal(t *testing.T) {
	cfg, err := ParseConfig(minimalConfig())
	if err != nil {
		t.Fatalf("ParseConfig: %v", err)
	}

	if got := cfg.Addresses[0].String(); got != "10.8.1.23" {
		t.Errorf("address = %q, want the address without its prefix length", got)
	}
	if cfg.MTU != 1420 {
		t.Errorf("MTU = %d, want the WireGuard default of 1420", cfg.MTU)
	}
}

func TestParseObfuscation(t *testing.T) {
	text := "[Interface]\n" +
		"PrivateKey = " + fakeKey(1) + "\n" +
		"Address = 10.8.1.23/32\n" +
		"Jc = 6\nJmin = 10\nJmax = 50\n" +
		"S1 = 112\nS2 = 70\nS3 = 33\nS4 = 9\n" +
		"H1 = 1925275600-2111937258\n" +
		"I1 = <b 0x08448180>\n" +
		"[Peer]\n" +
		"PublicKey = " + fakeKey(2) + "\n"

	cfg, err := ParseConfig(text)
	if err != nil {
		t.Fatalf("ParseConfig: %v", err)
	}

	for key, want := range map[string]string{
		"jc": "6", "jmin": "10", "jmax": "50",
		"s1": "112", "s4": "9",
		"h1": "1925275600-2111937258",
		"i1": "<b 0x08448180>",
	} {
		if got := cfg.Obfuscation[key]; got != want {
			t.Errorf("obfuscation[%q] = %q, want %q", key, got, want)
		}
	}
}

// H1 ranges and I1 packet chains have their own grammar, which the device layer
// already implements. Passing them through untouched is deliberate.
func TestObfuscationValuesAreNotReinterpreted(t *testing.T) {
	text := strings.Replace(
		minimalConfig(),
		"Address = 10.8.1.23/32\n",
		"Address = 10.8.1.23/32\nH2 = 2141845799-2143666835\n",
		1,
	)

	cfg, err := ParseConfig(text)
	if err != nil {
		t.Fatalf("ParseConfig: %v", err)
	}
	if got := cfg.Obfuscation["h2"]; got != "2141845799-2143666835" {
		t.Errorf("h2 = %q, want the range verbatim", got)
	}
}

func TestIPCOrdering(t *testing.T) {
	text := "[Interface]\n" +
		"PrivateKey = " + fakeKey(1) + "\n" +
		"Address = 10.8.1.23/32\n" +
		"Jc = 6\n" +
		"[Peer]\n" +
		"PublicKey = " + fakeKey(2) + "\n" +
		"PresharedKey = " + fakeKey(3) + "\n" +
		"Endpoint = 203.0.113.10:51820\n" +
		"AllowedIPs = 0.0.0.0/0, ::/0\n" +
		"PersistentKeepalive = 25\n"

	cfg, err := ParseConfig(text)
	if err != nil {
		t.Fatalf("ParseConfig: %v", err)
	}

	ipc := cfg.IPC()

	// public_key opens the peer section, so anything peer-scoped that lands
	// above it would silently be applied to the interface instead.
	privateAt := strings.Index(ipc, "private_key=")
	jcAt := strings.Index(ipc, "jc=")
	publicAt := strings.Index(ipc, "public_key=")
	endpointAt := strings.Index(ipc, "endpoint=")

	if !(privateAt < jcAt && jcAt < publicAt && publicAt < endpointAt) {
		t.Errorf("IPC sections are out of order:\n%s", ipc)
	}

	for _, want := range []string{
		"allowed_ip=0.0.0.0/0\n",
		"allowed_ip=::/0\n",
		"persistent_keepalive_interval=25\n",
		"preshared_key=",
	} {
		if !strings.Contains(ipc, want) {
			t.Errorf("IPC is missing %q:\n%s", want, ipc)
		}
	}
}

func TestKeysBecomeHex(t *testing.T) {
	cfg, err := ParseConfig(minimalConfig())
	if err != nil {
		t.Fatalf("ParseConfig: %v", err)
	}

	want := strings.Repeat("01", 32)
	if cfg.PrivateKey != want {
		t.Errorf("PrivateKey = %q, want the base64 key as hex", cfg.PrivateKey)
	}
}

func TestUnknownInterfaceKeysAreIgnored(t *testing.T) {
	text := strings.Replace(
		minimalConfig(),
		"Address = 10.8.1.23/32\n",
		"Address = 10.8.1.23/32\nSomeFutureKnob = whatever\n",
		1,
	)

	if _, err := ParseConfig(text); err != nil {
		t.Errorf("an unrecognised key should not stop a connection: %v", err)
	}
}

func TestRejections(t *testing.T) {
	cases := map[string]string{
		"no private key": "[Interface]\nAddress = 10.0.0.1/32\n[Peer]\nPublicKey = " + fakeKey(2) + "\n",
		"no public key":  "[Interface]\nPrivateKey = " + fakeKey(1) + "\nAddress = 10.0.0.1/32\n",
		"no address":     "[Interface]\nPrivateKey = " + fakeKey(1) + "\n[Peer]\nPublicKey = " + fakeKey(2) + "\n",
		"short key":      "[Interface]\nPrivateKey = AAAA\nAddress = 10.0.0.1/32\n[Peer]\nPublicKey = " + fakeKey(2) + "\n",
		"key outside a section": "PrivateKey = " + fakeKey(1) + "\n",
		"line without =":        "[Interface]\nPrivateKey\n",
	}

	for name, text := range cases {
		t.Run(name, func(t *testing.T) {
			if _, err := ParseConfig(text); err == nil {
				t.Error("expected an error, got none")
			}
		})
	}
}
