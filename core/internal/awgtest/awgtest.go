// Package awgtest runs a real AmneziaWG server on loopback for tests.
//
// It is a server in every way that matters to a client: a device with its own
// key on a UDP port, the obfuscation it is given, and a web server inside its
// tunnel. Only tests import it.
package awgtest

import (
	"crypto/rand"
	"encoding/base64"
	"fmt"
	"net"
	"net/http"
	"net/netip"
	"sync/atomic"
	"testing"
	"time"

	"github.com/amnezia-vpn/amneziawg-go/v3/conn"
	"github.com/amnezia-vpn/amneziawg-go/v3/device"
	"github.com/amnezia-vpn/amneziawg-go/v3/tun/netstack"
	"golang.org/x/crypto/curve25519"

	"github.com/TeamGDB/Caelo/core/internal/awg"
)

// Obfuscation is a full AWG 1.5 set, so that a test can show something works
// when headers and sizes no longer say what a packet is.
const Obfuscation = "Jc = 4\nJmin = 10\nJmax = 50\n" +
	"S1 = 31\nS2 = 17\n" +
	"H1 = 1000000-1000100\nH2 = 2000000-2000100\n" +
	"H3 = 3000000-3000100\nH4 = 4000000-4000100\n"

// Address is the server's address inside the tunnel.
var Address = netip.MustParseAddr("10.154.1.1")

// Options shape the server.
type Options struct {
	// Obfuscation lines, in .conf form, shared by server and client.
	Obfuscation string
	// Delay holds back every packet the server sends, like a server far
	// away, so that a round trip is something to measure.
	Delay time.Duration
}

// Server is a running loopback server.
type Server struct {
	// ClientConfig is a .conf that connects to it.
	ClientConfig string
	// URL answers with the server's tunnel address.
	URL string

	requests atomic.Int64
}

// Requests is how many requests the web server has answered.
func (s *Server) Requests() int { return int(s.requests.Load()) }

// Start runs a server until the test ends.
func Start(t testing.TB, opts Options) *Server {
	t.Helper()

	serverKey, serverPublic := KeyPair(t)
	clientKey, clientPublic := KeyPair(t)
	port := FreeUDPPort(t)

	cfg, err := awg.ParseConfig("[Interface]\n" +
		"PrivateKey = " + serverKey + "\n" +
		"Address = " + Address.String() + "/32\n" + opts.Obfuscation +
		"[Peer]\n" +
		"PublicKey = " + clientPublic + "\n" +
		"AllowedIPs = 10.154.1.2/32\n")
	if err != nil {
		t.Fatal(err)
	}
	tunDevice, tnet, err := netstack.CreateNetTUN(cfg.Addresses, nil, cfg.MTU)
	if err != nil {
		t.Fatal(err)
	}
	var bind conn.Bind = conn.NewDefaultBind()
	if opts.Delay > 0 {
		bind = &delayedBind{Bind: bind, delay: opts.Delay}
	}
	dev := device.NewDevice(tunDevice, bind, device.NewLogger(device.LogLevelSilent, ""))
	t.Cleanup(dev.Close)
	if err := dev.IpcSet(fmt.Sprintf("listen_port=%d\n", port) + cfg.IPC()); err != nil {
		t.Fatal(err)
	}
	if err := dev.Up(); err != nil {
		t.Fatal(err)
	}

	listener, err := tnet.ListenTCP(&net.TCPAddr{IP: Address.AsSlice(), Port: 80})
	if err != nil {
		t.Fatal(err)
	}
	server := &Server{
		ClientConfig: "[Interface]\n" +
			"PrivateKey = " + clientKey + "\n" +
			"Address = 10.154.1.2/32\n" + opts.Obfuscation +
			"[Peer]\n" +
			"PublicKey = " + serverPublic + "\n" +
			fmt.Sprintf("Endpoint = 127.0.0.1:%d\n", port) +
			"AllowedIPs = 10.154.1.0/24\n",
		URL: "http://" + Address.String() + "/",
	}
	web := &http.Server{Handler: http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		server.requests.Add(1)
		_, _ = w.Write([]byte(" " + Address.String() + "\n"))
	})}
	go func() { _ = web.Serve(listener) }()
	t.Cleanup(func() { _ = web.Close() })
	return server
}

// KeyPair is a fresh Curve25519 key pair, base64 as a .conf has it.
func KeyPair(t testing.TB) (private, public string) {
	t.Helper()
	var key [32]byte
	if _, err := rand.Read(key[:]); err != nil {
		t.Fatal(err)
	}
	key[0] &= 248
	key[31] = key[31]&127 | 64
	pub, err := curve25519.X25519(key[:], curve25519.Basepoint)
	if err != nil {
		t.Fatal(err)
	}
	return base64.StdEncoding.EncodeToString(key[:]), base64.StdEncoding.EncodeToString(pub)
}

// FreeUDPPort is a loopback port nothing was listening on a moment ago.
func FreeUDPPort(t testing.TB) int {
	t.Helper()
	socket, err := net.ListenUDP("udp", &net.UDPAddr{IP: net.IPv4(127, 0, 0, 1)})
	if err != nil {
		t.Fatal(err)
	}
	defer socket.Close()
	return socket.LocalAddr().(*net.UDPAddr).Port
}

// delayedBind sends every packet late.
type delayedBind struct {
	conn.Bind
	delay time.Duration
}

func (b *delayedBind) Send(bufs [][]byte, ep conn.Endpoint) error {
	copied := make([][]byte, len(bufs))
	for i, buf := range bufs {
		copied[i] = append([]byte(nil), buf...)
	}
	time.AfterFunc(b.delay, func() { _ = b.Bind.Send(copied, ep) })
	return nil
}
