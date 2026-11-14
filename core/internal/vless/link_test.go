package vless

import (
	"errors"
	"net/url"
	"strings"
	"testing"
)

// The three links from the issue (#172): test values and documentation
// addresses only.
const (
	visionLink = "vless://00000000-0000-4000-8000-000000000001@192.0.2.10:443?encryption=none&type=tcp&headerType=none&flow=xtls-rprx-vision&security=reality&sni=edge.example.com&pbk=AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8&sid=0123456789abcdef&fp=safari#Example%20Vision"
	xhttpLink  = "vless://00000000-0000-4000-8000-000000000001@192.0.2.10:443?encryption=none&type=xhttp&mode=packet-up&path=%2Fxhttp&security=reality&sni=edge.example.com&pbk=AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8&sid=0123456789abcdef&fp=safari#Example%20XHTTP"
	cdnLink    = "vless://00000000-0000-4000-8000-000000000001@cdn.example.com:443?encryption=none&type=xhttp&mode=packet-up&path=%2Fxhttp&security=tls&sni=cdn.example.com&host=cdn.example.com&fp=safari&alpn=h2%2Chttp%2F1.1#Example%20CDN"
)

func TestReadsTheThreeKindsOfLink(t *testing.T) {
	vision, err := Parse(visionLink)
	if err != nil {
		t.Fatal(err)
	}
	if vision.Variant() != "vless-reality-vision" || vision.Flow != FlowVision || vision.Transport != TransportTCP {
		t.Fatalf("vision: %+v", vision)
	}
	if vision.Name != "Example Vision" || vision.Fingerprint != "safari" || vision.ShortID != "0123456789abcdef" {
		t.Fatalf("vision fields: %+v", vision)
	}
	if vision.Endpoint() != "192.0.2.10:443" {
		t.Fatalf("endpoint %q", vision.Endpoint())
	}

	xhttp, err := Parse(xhttpLink)
	if err != nil {
		t.Fatal(err)
	}
	if xhttp.Variant() != "vless-reality-xhttp" || xhttp.Path != "/xhttp" || xhttp.Mode != "packet-up" || xhttp.Flow != "" {
		t.Fatalf("xhttp: %+v", xhttp)
	}

	cdn, err := Parse(cdnLink)
	if err != nil {
		t.Fatal(err)
	}
	if cdn.Variant() != "vless-tls-xhttp" || cdn.HTTPHost != "cdn.example.com" || cdn.SNI != "cdn.example.com" {
		t.Fatalf("cdn: %+v", cdn)
	}
	if strings.Join(cdn.ALPN, ",") != "h2,http/1.1" {
		t.Fatalf("alpn %v", cdn.ALPN)
	}
}

func TestEveryAdvertisedVariantIsOneALinkCanBe(t *testing.T) {
	seen := map[string]bool{}
	for _, link := range []string{visionLink, xhttpLink, cdnLink,
		strings.Replace(visionLink, "security=reality", "security=tls", 1)} {
		parsed, err := Parse(link)
		if err != nil {
			t.Fatal(err)
		}
		seen[parsed.Variant()] = true
	}
	for _, variant := range Variants {
		if !seen[variant] {
			t.Errorf("%s is advertised but no link produced it", variant)
		}
	}
}

func TestKeepsTheFingerprintAsked(t *testing.T) {
	for _, fp := range []string{"safari", "chrome", "firefox", "ios", "edge", "randomized"} {
		link, err := Parse(strings.Replace(visionLink, "fp=safari", "fp="+fp, 1))
		if err != nil {
			t.Fatalf("%s: %v", fp, err)
		}
		if link.Fingerprint != fp {
			t.Fatalf("asked %s, got %s", fp, link.Fingerprint)
		}
	}
}

func TestReadsIPv6AndUnicodeAndEncoding(t *testing.T) {
	link, err := Parse("vless://00000000-0000-4000-8000-000000000001@[2001:db8::1]:8443?security=reality&sni=edge.example.com&pbk=AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8&sid=ab&fp=chrome&type=raw#%D0%93%D0%B5%D1%80%D0%BC%D0%B0%D0%BD%D0%B8%D1%8F%20%F0%9F%87%A9%F0%9F%87%AA")
	if err != nil {
		t.Fatal(err)
	}
	if link.Host != "2001:db8::1" || link.Port != 8443 || link.Endpoint() != "[2001:db8::1]:8443" {
		t.Fatalf("address: %+v", link)
	}
	if link.Name != "Германия 🇩🇪" {
		t.Fatalf("name %q", link.Name)
	}
}

func TestTrimsWhitespaceAndCarriageReturns(t *testing.T) {
	if _, err := Parse("  " + visionLink + "\r\n"); err != nil {
		t.Fatal(err)
	}
}

func TestIgnoresParametersItDoesNotKnow(t *testing.T) {
	link, err := Parse(withParam(visionLink, "ech=&someday=maybe"))
	if err != nil {
		t.Fatal(err)
	}
	if link.Variant() != "vless-reality-vision" {
		t.Fatal(link.Variant())
	}
}

func TestCarriesTheXHTTPExtraThatShapesTheWire(t *testing.T) {
	link, err := Parse(withParam(cdnLink, "extra="+url.QueryEscape(`{"xPaddingBytes":"100-1000","xmux":{"maxConcurrency":"16-32"}}`)))
	if err != nil {
		t.Fatal(err)
	}
	if len(link.Extra) == 0 {
		t.Fatal("extra dropped")
	}
	in, err := start(link, options{})
	if err != nil {
		t.Fatalf("Xray refused it: %v", err)
	}
	in.Close()
}

func TestReadsPostQuantumVerification(t *testing.T) {
	link, err := Parse(strings.Replace(visionLink, "&fp=", "&pqv=bWxkc2E&fp=", 1))
	if err != nil {
		t.Fatal(err)
	}
	if link.MLDSA65Verify != "bWxkc2E" {
		t.Fatalf("pqv %q", link.MLDSA65Verify)
	}
}

// What cannot be honoured is refused with a reason, rather than connected
// some other way.
func TestRefusesWhatItCannotHonour(t *testing.T) {
	cases := map[string]string{
		"websocket":           strings.Replace(xhttpLink, "type=xhttp", "type=ws", 1),
		"no security":         strings.Replace(visionLink, "security=reality", "security=none", 1),
		"vision over xhttp":   strings.Replace(xhttpLink, "type=xhttp", "type=xhttp&flow=xtls-rprx-vision", 1),
		"unknown fingerprint": strings.Replace(visionLink, "fp=safari", "fp=netscape", 1),
		"http header":         strings.Replace(visionLink, "headerType=none", "headerType=http", 1),
		"unknown flow":        strings.Replace(visionLink, "flow=xtls-rprx-vision", "flow=xtls-rprx-direct", 1),
		"insecure tls":        withParam(cdnLink, "allowInsecure=1"),
		"unknown mode":        strings.Replace(cdnLink, "mode=packet-up", "mode=teleport", 1),
		// A whole second stream configuration, with files and socket options,
		// for a service that runs as root.
		"download settings": withParam(cdnLink, "extra="+url.QueryEscape(`{"downloadSettings":{"tlsSettings":{"masterKeyLog":"/etc/x"}}}`)),
		"socket options":    withParam(cdnLink, "extra="+url.QueryEscape(`{"sockopt":{"mark":1}}`)),
	}
	for name, link := range cases {
		_, err := Parse(link)
		if !errors.Is(err, ErrUnsupported) {
			t.Errorf("%s: want unsupported, got %v", name, err)
		}
	}
}

func TestRefusesWhatIsBroken(t *testing.T) {
	cases := map[string]string{
		"not vless":       "trojan://x@192.0.2.1:443",
		"no uuid":         strings.Replace(visionLink, "00000000-0000-4000-8000-000000000001@", "", 1),
		"bad uuid":        strings.Replace(visionLink, "00000000-0000-4000-8000-000000000001", "user", 1),
		"no port":         strings.Replace(visionLink, ":443", "", 1),
		"port too big":    strings.Replace(visionLink, ":443", ":70000", 1),
		"no public key":   strings.Replace(visionLink, "pbk=AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8", "pbk=", 1),
		"no sni":          strings.Replace(visionLink, "sni=edge.example.com", "sni=", 1),
		"bad short id":    strings.Replace(visionLink, "sid=0123456789abcdef", "sid=xyz", 1),
		"bad xhttp extra": withParam(xhttpLink, "extra=%7Bnope"),
		"relative path":   strings.Replace(xhttpLink, "path=%2Fxhttp", "path=xhttp", 1),
		"bad brackets":    strings.Replace(visionLink, "192.0.2.10", "[edge.example.com]", 1),
	}
	for name, link := range cases {
		if _, err := Parse(link); err == nil {
			t.Errorf("%s: accepted", name)
		}
	}
}

// Errors are shown to people and written to logs; the user id is the key to
// somebody's access and must not travel with them.
func TestErrorsDoNotRepeatTheUserID(t *testing.T) {
	for _, link := range []string{
		strings.Replace(visionLink, "type=tcp", "type=ws", 1),
		strings.Replace(visionLink, ":443", ":0", 1),
		"vless://00000000-0000-4000-8000-000000000001@%zz:443",
	} {
		_, err := Parse(link)
		if err == nil {
			t.Fatalf("accepted %s", link)
		}
		if strings.Contains(err.Error(), "00000000-0000-4000-8000-000000000001") {
			t.Fatalf("error repeats the id: %v", err)
		}
	}
}

// withParam adds to the query, before the fragment.
func withParam(link, param string) string {
	cut := strings.Index(link, "#")
	return link[:cut] + "&" + param + link[cut:]
}

func TestClaimsOnlyVLESS(t *testing.T) {
	if !Claims(visionLink) || !Claims("  VLESS://x") {
		t.Fatal("did not claim a vless link")
	}
	for _, text := range []string{"", "[Interface]\nPrivateKey = x", `{"type":"amneziawg"}`, "vmess://abc"} {
		if Claims(text) {
			t.Fatalf("claimed %q", text)
		}
	}
}

func TestVisionWithUDP443KeepsItsVariant(t *testing.T) {
	link, err := Parse(strings.Replace(visionLink, "flow=xtls-rprx-vision", "flow=xtls-rprx-vision-udp443", 1))
	if err != nil {
		t.Fatal(err)
	}
	if link.Variant() != "vless-reality-vision" {
		t.Fatalf("variant: %s", link.Variant())
	}
}
