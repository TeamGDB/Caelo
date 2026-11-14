//go:build darwin && !ios

package vless

import (
	"context"
	"encoding/binary"
	"io"
	"net/http"
	"net/netip"
	"sync"
	"testing"
	"time"

	"github.com/TeamGDB/Caelo/core/internal/vless/vlesstest"
	"github.com/amnezia-vpn/amneziawg-go/v3/tun/netstack"
)

// Полный путь системного клиента через переданный FD без интерфейсов и
// маршрутов macOS: сетевой стек клиента и utun живут только внутри теста.
func TestHostedVLESSRejectsUnavailableIPv6BeforeTCPConnect(t *testing.T) {
	for _, variant := range []vlesstest.Variant{vlesstest.RealityVision, vlesstest.RealityXHTTP} {
		for _, available := range []bool{false, true} {
			name := variant.Transport + "/ipv4-only"
			if available {
				name = variant.Transport + "/dual-stack"
			}
			t.Run(name, func(t *testing.T) {
				server := vlesstest.StartWith(t, variant, vlesstest.Options{Redirect: true, BlockIPv6: !available})
				link, err := Parse(server.Link)
				if err != nil {
					t.Fatal(err)
				}
				warm, err := start(link, options{})
				if err != nil {
					t.Fatal(err)
				}
				tr := &http.Transport{DialContext: warm.Dial}
				r, err := (&http.Client{Transport: tr, Timeout: 10 * time.Second}).Get(server.URL)
				if err != nil {
					warm.Close()
					t.Fatal(err)
				}
				r.Body.Close()
				tr.CloseIdleConnections()
				warm.Close()

				device, clientNet, err := netstack.CreateNetTUN([]netip.Addr{netip.MustParseAddr("172.19.0.1"), netip.MustParseAddr("fdfe:dcba:9876::1")}, nil, 1500)
				if err != nil {
					t.Fatal(err)
				}
				host, tun := socketFiles(t)
				var pumps sync.WaitGroup
				pumps.Add(2)
				go func() {
					defer pumps.Done()
					buf := make([]byte, 65580)
					sizes := make([]int, 1)
					for {
						n, e := device.Read([][]byte{buf}, sizes, 4)
						if e != nil {
							return
						}
						if n == 0 {
							continue
						}
						family := uint32(2)
						if buf[4]>>4 == 6 {
							family = 30
						}
						binary.BigEndian.PutUint32(buf, family)
						if writePacket(host, buf[:sizes[0]+4]) != nil {
							return
						}
					}
				}()
				go func() {
					defer pumps.Done()
					buf := make([]byte, 65580)
					for {
						n, e := host.Read(buf)
						if e != nil {
							return
						}
						if n < 4 {
							continue
						}
						if _, e = device.Write([][]byte{buf[4:n]}, 0); e != nil {
							return
						}
					}
				}()
				defer func() { device.Close(); host.Close(); pumps.Wait() }()
				node := &config{link: link, ipv6Checked: true, ipv6Available: available}
				tunnel, err := node.Attach(int(tun.Fd()), 1500)
				if err != nil {
					t.Fatal(err)
				}
				defer tunnel.Close()
				transport := &http.Transport{DialContext: clientNet.DialContext}
				defer transport.CloseIdleConnections()
				client := &http.Client{Transport: transport, Timeout: 10 * time.Second}
				response, err := client.Get("http://198.51.100.9/")
				if err != nil {
					t.Fatal(err)
				}
				body, err := io.ReadAll(response.Body)
				response.Body.Close()
				if err != nil || string(body) != vlesstest.Body {
					t.Fatalf("IPv4 payload: %q %v", body, err)
				}
				ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
				defer cancel()
				began := time.Now()
				conn, err := clientNet.DialContext(ctx, "tcp6", "[2001:db8::2]:80")
				if !available {
					if conn != nil {
						conn.Close()
						t.Fatal("unreachable IPv6 accepted TCP before failing")
					}
					if err == nil || time.Since(began) > time.Second {
						t.Fatalf("IPv6 did not fail fast: %v", err)
					}
				} else {
					if err != nil {
						t.Fatal(err)
					}
					conn.Close()
					response, err := client.Get("http://[2001:db8::2]/")
					if err != nil {
						t.Fatal(err)
					}
					body, err := io.ReadAll(response.Body)
					response.Body.Close()
					if err != nil || string(body) != vlesstest.Body {
						t.Fatalf("IPv6 payload: %q %v", body, err)
					}
				}
			})
		}
	}
}
