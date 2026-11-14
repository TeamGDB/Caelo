package vless

import (
	"context"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/tls"
	"crypto/x509"
	"crypto/x509/pkix"
	"math/big"
	"net"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/TeamGDB/Caelo/core/internal/vless/vlesstest"
)

func ipv6TLS(t *testing.T) (ipv6Target, *x509.CertPool) {
	t.Helper()
	ln, e := net.Listen("tcp6", "[::1]:0")
	if e != nil {
		t.Skipf("IPv6 loopback unavailable: %v", e)
	}
	key, e := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if e != nil {
		t.Fatal(e)
	}
	template := &x509.Certificate{SerialNumber: big.NewInt(1), Subject: pkix.Name{CommonName: "probe.example"}, DNSNames: []string{"probe.example"}, NotBefore: time.Now().Add(-time.Hour), NotAfter: time.Now().Add(time.Hour), KeyUsage: x509.KeyUsageDigitalSignature, ExtKeyUsage: []x509.ExtKeyUsage{x509.ExtKeyUsageServerAuth}, BasicConstraintsValid: true}
	der, e := x509.CreateCertificate(rand.Reader, template, template, &key.PublicKey, key)
	if e != nil {
		t.Fatal(e)
	}
	certificate, e := x509.ParseCertificate(der)
	if e != nil {
		t.Fatal(e)
	}
	roots := x509.NewCertPool()
	roots.AddCert(certificate)
	server := httptest.NewUnstartedServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { w.WriteHeader(204) }))
	server.Listener.Close()
	server.Listener = ln
	server.TLS = &tls.Config{Certificates: []tls.Certificate{{Certificate: [][]byte{der}, PrivateKey: key}}}
	server.StartTLS()
	t.Cleanup(server.Close)
	return ipv6Target{ln.Addr().String(), "probe.example"}, roots
}

func TestIPv6ProofCrossesTheVLESSExit(t *testing.T) {
	target, roots := ipv6TLS(t)
	for _, variant := range []vlesstest.Variant{vlesstest.RealityVision, vlesstest.RealityXHTTP, vlesstest.TLSVision, vlesstest.TLSXHTTP} {
		for _, blocked := range []bool{false, true} {
			name := variant.Security + "/" + variant.Transport
			if blocked {
				name += "/ipv4-only"
			} else {
				name += "/dual-stack"
			}
			t.Run(name, func(t *testing.T) {
				server := vlesstest.StartWith(t, variant, vlesstest.Options{BlockIPv6: blocked})
				link, e := Parse(server.Link)
				if e != nil {
					t.Fatal(e)
				}
				// В приложении семейство проверяется после успешной пробы узла.
				// REALITY-стенд сначала должен закончить проверку своей заглушки.
				in, e := start(link, options{rootCAs: []string{server.RootCA}})
				if e != nil {
					t.Fatal(e)
				}
				defer in.Close()
				tr := &http.Transport{DialContext: in.Dial}
				defer tr.CloseIdleConnections()
				client := &http.Client{Transport: tr, Timeout: 10 * time.Second}
				response, e := client.Get(server.URL)
				if e != nil {
					t.Fatal(e)
				}
				response.Body.Close()
				if response.StatusCode != 200 {
					t.Fatal(response.Status)
				}
				node := &config{link: link}
				ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
				defer cancel()
				prepared, e := node.prepareIPv6(ctx, []ipv6Target{target}, roots, options{rootCAs: []string{server.RootCA}})
				if e != nil {
					t.Fatal(e)
				}
				c := prepared.(*config)
				if !c.ipv6Checked || c.ipv6Available == blocked {
					t.Fatalf("checked=%v available=%v blocked=%v", c.ipv6Checked, c.ipv6Available, blocked)
				}
				android := c.describeFor("android")
				apple := c.describeFor("ios")
				wantFamilies := 2
				if blocked {
					wantFamilies = 1
				}
				if len(android.Addresses) != wantFamilies || len(android.AllowedIPs) != wantFamilies {
					t.Fatal("Android advertised an unsupported address family")
				}
				if len(apple.Addresses) != 2 || len(apple.AllowedIPs) != 2 {
					t.Fatal("Apple must retain its IPv6 capture route")
				}
				if android.IPv6Available == nil || *android.IPv6Available == blocked {
					t.Fatal("missing family result")
				}

			})
		}
	}
}

func TestIPv6ProofVerifiesTheCertificateAndFamily(t *testing.T) {
	target, roots := ipv6TLS(t)
	d := &net.Dialer{}
	for _, tc := range []struct {
		name   string
		target ipv6Target
		roots  *x509.CertPool
		want   bool
	}{
		{"trusted", target, roots, true}, {"untrusted", target, x509.NewCertPool(), false},
		{"wrong name", ipv6Target{target.address, "other.example"}, roots, false},
		{"IPv4 is not a proof", ipv6Target{"127.0.0.1:443", "probe.example"}, roots, false},
	} {
		t.Run(tc.name, func(t *testing.T) {
			ctx, cancel := context.WithTimeout(context.Background(), time.Second)
			defer cancel()
			if got := checkIPv6Target(ctx, d.DialContext, tc.target, tc.roots); got != tc.want {
				t.Fatalf("got %v", got)
			}
		})
	}
}

func TestIPv6ProofStopsOtherAttemptsAfterSuccess(t *testing.T) {
	target, roots := ipv6TLS(t)
	d := &net.Dialer{}
	stopped := make(chan struct{})
	dial := func(ctx context.Context, network, address string) (net.Conn, error) {
		if strings.Contains(address, "2001:db8") {
			<-ctx.Done()
			close(stopped)
			return nil, ctx.Err()
		}
		return d.DialContext(ctx, network, address)
	}
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()
	if !ipv6Reachable(ctx, dial, []ipv6Target{target, {"[2001:db8::1]:443", "unused.example"}}, roots) {
		t.Fatal("working exit rejected")
	}
	select {
	case <-stopped:
	default:
		t.Fatal("the outstanding probe was not cancelled")
	}
}

func TestIPv6ProofTimeoutFailsClosed(t *testing.T) {
	ctx, cancel := context.WithTimeout(context.Background(), 25*time.Millisecond)
	defer cancel()
	dial := func(ctx context.Context, _, _ string) (net.Conn, error) { <-ctx.Done(); return nil, ctx.Err() }
	if ipv6Reachable(ctx, dial, []ipv6Target{{"[2001:db8::1]:443", "probe.example"}}, nil) {
		t.Fatal("timeout advertised IPv6")
	}
}
