package awg

import (
	"fmt"
	"reflect"
	"strings"
	"testing"
)

// endpointJSON is the same node the `.conf` below describes, so that the two
// can be compared rather than each merely checked against what its own author
// expected.
func endpointJSON() string {
	return fmt.Sprintf(`{
	  "type": "amneziawg",
	  "tag": "Frankfurt",
	  "address": ["10.8.1.23/32"],
	  "private_key": %q,
	  "mtu": 1376,
	  "dns": ["1.1.1.1", "9.9.9.9"],
	  "peers": [{
	    "address": "203.0.113.10",
	    "port": 45330,
	    "public_key": %q,
	    "pre_shared_key": %q,
	    "allowed_ips": ["0.0.0.0/0"],
	    "persistent_keepalive_interval": 25
	  }],
	  "jc": 6, "jmin": 10, "jmax": 50,
	  "s1": 112, "s2": 70, "s3": 33, "s4": 9,
	  "h1": "1148446321", "i1": "<b 0xc0de>"
	}`, fakeKey(1), fakeKey(2), fakeKey(3))
}

func equivalentConf() string {
	return fmt.Sprintf(`[Interface]
PrivateKey = %s
Address = 10.8.1.23/32
MTU = 1376
DNS = 1.1.1.1, 9.9.9.9
Jc = 6
Jmin = 10
Jmax = 50
S1 = 112
S2 = 70
S3 = 33
S4 = 9
H1 = 1148446321
I1 = <b 0xc0de>

[Peer]
PublicKey = %s
PresharedKey = %s
Endpoint = 203.0.113.10:45330
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
`, fakeKey(1), fakeKey(2), fakeKey(3))
}

// The point of the whole arrangement: one node written two ways has to produce
// one configuration. If these ever diverge, a subscription and a pasted file
// describing the same server would dial differently, and only one of them
// would be tested.
func TestEndpointMatchesConf(t *testing.T) {
	fromJSON, err := ParseEndpoint([]byte(endpointJSON()))
	if err != nil {
		t.Fatalf("reading the endpoint: %v", err)
	}
	fromConf, err := ParseConfig(equivalentConf())
	if err != nil {
		t.Fatalf("reading the conf: %v", err)
	}

	if !reflect.DeepEqual(fromJSON, fromConf) {
		t.Errorf("the two forms disagree\n json: %+v\n conf: %+v", fromJSON, fromConf)
	}
	if fromJSON.IPC() != fromConf.IPC() {
		t.Errorf("the two forms render different UAPI\n json:\n%s\n conf:\n%s",
			fromJSON.IPC(), fromConf.IPC())
	}
}

func TestEndpointAcceptsEitherSpelling(t *testing.T) {
	quoted := fmt.Sprintf(`{
	  "type": "amneziawg",
	  "address": ["10.0.0.2/32"],
	  "private_key": %q,
	  "peers": [{"address": "198.51.100.4", "port": 51820, "public_key": %q}],
	  "jc": "6", "s1": "112"
	}`, fakeKey(4), fakeKey(5))

	cfg, err := ParseEndpoint([]byte(quoted))
	if err != nil {
		t.Fatalf("a server that quotes its numbers should still work: %v", err)
	}
	if cfg.Obfuscation["jc"] != "6" || cfg.Obfuscation["s1"] != "112" {
		t.Errorf("obfuscation did not survive quoting: %v", cfg.Obfuscation)
	}
}

func TestEndpointDefaults(t *testing.T) {
	minimal := fmt.Sprintf(`{
	  "address": ["10.0.0.2/32"],
	  "private_key": %q,
	  "peers": [{"address": "198.51.100.4", "port": 51820, "public_key": %q}]
	}`, fakeKey(4), fakeKey(5))

	cfg, err := ParseEndpoint([]byte(minimal))
	if err != nil {
		t.Fatalf("reading the endpoint: %v", err)
	}
	if cfg.MTU != 1420 {
		t.Errorf("MTU = %d, want the same 1420 a .conf without one gets", cfg.MTU)
	}
	if len(cfg.Peer.AllowedIPs) != 1 || cfg.Peer.AllowedIPs[0] != "0.0.0.0/0" {
		t.Errorf("AllowedIPs = %v, want everything by default", cfg.Peer.AllowedIPs)
	}
	if len(cfg.Obfuscation) != 0 {
		t.Errorf("obfuscation = %v, want none: a node may be plain WireGuard", cfg.Obfuscation)
	}
}

func TestEndpointRefusals(t *testing.T) {
	cases := map[string]string{
		"another type": fmt.Sprintf(
			`{"type":"vless","address":["10.0.0.2/32"],"private_key":%q,"peers":[{"address":"a","port":1,"public_key":%q}]}`,
			fakeKey(4), fakeKey(5)),
		"no peers": fmt.Sprintf(
			`{"address":["10.0.0.2/32"],"private_key":%q,"peers":[]}`, fakeKey(4)),
		"two peers": fmt.Sprintf(
			`{"address":["10.0.0.2/32"],"private_key":%q,"peers":[{"address":"a","port":1,"public_key":%q},{"address":"b","port":2,"public_key":%q}]}`,
			fakeKey(4), fakeKey(5), fakeKey(6)),
		"no address": fmt.Sprintf(
			`{"private_key":%q,"peers":[{"address":"a","port":1,"public_key":%q}]}`, fakeKey(4), fakeKey(5)),
		"no port": fmt.Sprintf(
			`{"address":["10.0.0.2/32"],"private_key":%q,"peers":[{"address":"a","public_key":%q}]}`,
			fakeKey(4), fakeKey(5)),
		"a key that is not one": `{"address":["10.0.0.2/32"],"private_key":"hello","peers":[]}`,
		"not an object":         `["not", "an", "endpoint"]`,
	}

	for name, document := range cases {
		t.Run(name, func(t *testing.T) {
			if _, err := ParseEndpoint([]byte(document)); err == nil {
				t.Errorf("accepted %s", name)
			}
		})
	}
}

func TestLooksLikeJSON(t *testing.T) {
	if !LooksLikeJSON("  \n{\"type\":\"amneziawg\"}") {
		t.Error("a document with leading space is still a document")
	}
	if LooksLikeJSON("[Interface]\nPrivateKey = x\n") {
		t.Error("a .conf was taken for JSON")
	}
	if LooksLikeJSON("") {
		t.Error("nothing at all was taken for JSON")
	}
}

// Регрессия, которую видно было только на живом сервере: подписка отдавала
// endpoint без параметров 3.1, и сервер с RandomTrailers не отвечал на
// рукопожатия. Из .conf тот же сервер подключался, из ссылки — нет.
func TestEndpointCarriesAmnezia31(t *testing.T) {
	cfg, err := ParseEndpoint([]byte(`{
		"type": "amneziawg",
		"tag": "Sima",
		"address": ["10.8.1.4/32"],
		"private_key": "` + fakeKey(1) + `",
		"peers": [{
			"address": "198.51.100.4", "port": 48881,
			"public_key": "` + fakeKey(2) + `"
		}],
		"jc": 4, "s1": 79, "h1": "1",
		"header_protection_key": "` + fakeKey(3) + `",
		"content_padding_addition": "10-100",
		"rekey_after_time": "100-120",
		"reject_after_time": "150-180",
		"keepalive_timeout": "5-15",
		"max_handshake_attempts": "15-20",
		"random_trailers": "on",
		"disable_cookies": "on"
	}`))
	if err != nil {
		t.Fatal(err)
	}

	ipc := cfg.IPC()
	for _, want := range []string{
		"content_padding_addition=10-100",
		"reject_after_time=150-180",
		"keepalive_timeout=5-15",
		"max_handshake_attempts=15-20",
		"random_trailers=true",
		"disable_cookies=true",
	} {
		if !strings.Contains(ipc, want) {
			t.Errorf("в IPC нет %q:\n%s", want, ipc)
		}
	}

	// Ключ защиты заголовков едет base64 и там, и там, а устройство читает hex.
	// Перевод должен случиться на обоих путях одинаково, иначе сервер работает
	// из файла и молчит по ссылке.
	if !strings.Contains(ipc, "header_protection_key="+hexOf(fakeKey(3))) {
		t.Errorf("ключ защиты заголовков не переведён в hex:\n%s", ipc)
	}
}
