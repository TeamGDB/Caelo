// Package vlesstest runs a real Xray VLESS server on loopback for tests.
//
// It is a server in every way that matters to a client: REALITY or TLS in
// front, Vision or XHTTP inside, a user id it checks, and a web server behind
// it to fetch from. Only tests import it.
package vlesstest

import (
	"bytes"
	"crypto/ecdh"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/base64"
	"encoding/json"
	"encoding/pem"
	"fmt"
	"math/big"
	"net"
	"net/http"
	"net/http/httptest"
	"net/url"
	"strconv"
	"strings"
	"testing"
	"time"

	"github.com/xtls/xray-core/core"
	"github.com/xtls/xray-core/infra/conf/serial"

	_ "github.com/xtls/xray-core/app/dispatcher"
	_ "github.com/xtls/xray-core/app/proxyman/inbound"
	_ "github.com/xtls/xray-core/app/proxyman/outbound"
	_ "github.com/xtls/xray-core/proxy/freedom"
	_ "github.com/xtls/xray-core/proxy/vless/inbound"
	_ "github.com/xtls/xray-core/transport/internet/reality"
	_ "github.com/xtls/xray-core/transport/internet/splithttp"
	_ "github.com/xtls/xray-core/transport/internet/tcp"
	_ "github.com/xtls/xray-core/transport/internet/tls"
)

// UUID is the one user every test server knows.
const UUID = "00000000-0000-4000-8000-0000000000aa"

// ServerName is what REALITY and TLS clients ask for.
const ServerName = "edge.example.com"

// ShortID is the REALITY short id every test server accepts.
const ShortID = "0123456789abcdef"

// Body is what the web server behind every test server answers with, so a
// test can tell a reply that crossed the tunnel from one that did not.
const Body = "carried by vless"

// Variant chooses what the server runs.
type Variant struct {
	// Security is "reality" or "tls".
	Security string
	// Transport is "tcp" (with Vision) or "xhttp".
	Transport string
}

var (
	RealityVision = Variant{"reality", "tcp"}
	RealityXHTTP  = Variant{"reality", "xhttp"}
	TLSXHTTP      = Variant{"tls", "xhttp"}
	TLSVision     = Variant{"tls", "tcp"}
)

// Server is one running test server.
type Server struct {
	// Link is a share link a client can use, pointed at 127.0.0.1.
	Link string
	// URL is the web server behind the VLESS server: reachable from it, and
	// what a client fetches through it.
	URL string
	// Target is URL's host:port.
	Target string
	// RootCA is the PEM of the authority behind a TLS server's certificate.
	// Empty for REALITY, which needs none.
	RootCA string
}

// Start runs a server for the variant until the test ends.
func Start(t testing.TB, variant Variant) *Server {
	t.Helper()

	web := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		fmt.Fprint(w, Body)
	}))
	t.Cleanup(web.Close)

	port := freePort(t)
	server := &Server{URL: web.URL, Target: strings.TrimPrefix(web.URL, "http://")}

	client := map[string]any{"id": UUID}
	if variant.Transport == "tcp" {
		client["flow"] = "xtls-rprx-vision"
	}
	stream := map[string]any{
		"network":  map[string]string{"tcp": "raw", "xhttp": "xhttp"}[variant.Transport],
		"security": variant.Security,
	}
	if variant.Transport == "xhttp" {
		stream["xhttpSettings"] = map[string]any{"path": "/xhttp", "mode": "packet-up"}
	}

	query := url.Values{}
	query.Set("encryption", "none")
	query.Set("type", variant.Transport)
	query.Set("security", variant.Security)
	query.Set("sni", ServerName)
	query.Set("fp", "chrome")
	if variant.Transport == "tcp" {
		query.Set("flow", "xtls-rprx-vision")
	} else {
		query.Set("path", "/xhttp")
		query.Set("mode", "packet-up")
	}

	switch variant.Security {
	case "reality":
		// REALITY borrows a real TLS 1.3 server's handshake for anyone who
		// is not a client. This one stands in for the site it imitates.
		decoy := httptest.NewUnstartedServer(http.NotFoundHandler())
		decoy.StartTLS()
		t.Cleanup(decoy.Close)

		private, public := realityKeys(t)
		stream["realitySettings"] = map[string]any{
			"target":      strings.TrimPrefix(decoy.URL, "https://"),
			"serverNames": []string{ServerName},
			"privateKey":  private,
			"shortIds":    []string{ShortID},
		}
		query.Set("pbk", public)
		query.Set("sid", ShortID)
	case "tls":
		certificate, key, ca := certificateFor(t, ServerName)
		stream["tlsSettings"] = map[string]any{
			"certificates": []map[string]any{{
				"certificate": strings.Split(strings.TrimSpace(certificate), "\n"),
				"key":         strings.Split(strings.TrimSpace(key), "\n"),
			}},
		}
		server.RootCA = ca
		if variant.Transport == "xhttp" {
			query.Set("host", ServerName)
			query.Set("alpn", "h2,http/1.1")
		}
	}

	config := map[string]any{
		"log": map[string]any{"loglevel": "none"},
		"inbounds": []any{map[string]any{
			"listen":         "127.0.0.1",
			"port":           port,
			"protocol":       "vless",
			"settings":       map[string]any{"clients": []any{client}, "decryption": "none"},
			"streamSettings": stream,
		}},
		// Freedom refuses private addresses unless told otherwise, and
		// the web server behind this one is on loopback.
		"outbounds": []any{map[string]any{
			"protocol": "freedom",
			"settings": map[string]any{"finalRules": []any{map[string]any{"action": "allow", "ip": []string{"127.0.0.1/32"}}}},
		}},
	}
	run(t, config)

	server.Link = fmt.Sprintf("vless://%s@127.0.0.1:%d?%s#%s", UUID, port, query.Encode(),
		url.PathEscape(variant.Security+" "+variant.Transport))
	waitListening(t, port)
	return server
}

func run(t testing.TB, config map[string]any) {
	t.Helper()
	encoded, err := json.Marshal(config)
	if err != nil {
		t.Fatal(err)
	}
	loaded, err := serial.LoadJSONConfig(bytes.NewReader(encoded))
	if err != nil {
		t.Fatalf("server configuration: %v", err)
	}
	instance, err := core.New(loaded)
	if err != nil {
		t.Fatalf("server: %v", err)
	}
	if err := instance.Start(); err != nil {
		t.Fatalf("starting server: %v", err)
	}
	t.Cleanup(func() { instance.Close() })
}

func freePort(t testing.TB) int {
	t.Helper()
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer listener.Close()
	return listener.Addr().(*net.TCPAddr).Port
}

func waitListening(t testing.TB, port int) {
	t.Helper()
	deadline := time.Now().Add(5 * time.Second)
	for time.Now().Before(deadline) {
		connection, err := net.DialTimeout("tcp", "127.0.0.1:"+strconv.Itoa(port), 200*time.Millisecond)
		if err == nil {
			connection.Close()
			return
		}
		time.Sleep(20 * time.Millisecond)
	}
	t.Fatalf("server on %d never listened", port)
}

// realityKeys is an X25519 pair in the encoding REALITY configurations use.
func realityKeys(t testing.TB) (private, public string) {
	t.Helper()
	key, err := ecdh.X25519().GenerateKey(rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	return base64.RawURLEncoding.EncodeToString(key.Bytes()),
		base64.RawURLEncoding.EncodeToString(key.PublicKey().Bytes())
}

// certificateFor makes an authority and a certificate it signed for name.
func certificateFor(t testing.TB, name string) (certificate, key, ca string) {
	t.Helper()
	caKey, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	caTemplate := &x509.Certificate{
		SerialNumber:          big.NewInt(1),
		Subject:               pkix.Name{CommonName: "vlesstest authority"},
		NotBefore:             time.Now().Add(-time.Hour),
		NotAfter:              time.Now().Add(time.Hour),
		IsCA:                  true,
		BasicConstraintsValid: true,
		KeyUsage:              x509.KeyUsageCertSign,
	}
	caDER, err := x509.CreateCertificate(rand.Reader, caTemplate, caTemplate, &caKey.PublicKey, caKey)
	if err != nil {
		t.Fatal(err)
	}
	caCert, _ := x509.ParseCertificate(caDER)

	leafKey, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	leafTemplate := &x509.Certificate{
		SerialNumber: big.NewInt(2),
		Subject:      pkix.Name{CommonName: name},
		DNSNames:     []string{name},
		NotBefore:    time.Now().Add(-time.Hour),
		NotAfter:     time.Now().Add(time.Hour),
		KeyUsage:     x509.KeyUsageDigitalSignature,
		ExtKeyUsage:  []x509.ExtKeyUsage{x509.ExtKeyUsageServerAuth},
	}
	leafDER, err := x509.CreateCertificate(rand.Reader, leafTemplate, caCert, &leafKey.PublicKey, caKey)
	if err != nil {
		t.Fatal(err)
	}
	leafKeyDER, err := x509.MarshalECPrivateKey(leafKey)
	if err != nil {
		t.Fatal(err)
	}
	encode := func(kind string, der []byte) string {
		return string(pem.EncodeToMemory(&pem.Block{Type: kind, Bytes: der}))
	}
	return encode("CERTIFICATE", leafDER), encode("EC PRIVATE KEY", leafKeyDER), encode("CERTIFICATE", caDER)
}
