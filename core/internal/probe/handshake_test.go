package probe

import (
	"encoding/base64"
	"encoding/hex"
	"fmt"
	"net/netip"
	"testing"
	"time"

	"github.com/amnezia-vpn/amneziawg-go/v3/conn"
	"github.com/amnezia-vpn/amneziawg-go/v3/device"
	"github.com/amnezia-vpn/amneziawg-go/v3/tun/netstack"

	"github.com/TeamGDB/Caelo/core/internal/awgtest"
)

func TestHandshakeClockPairsTheLastInitiationWithTheResponse(t *testing.T) {
	t.Parallel()

	at := time.Unix(0, 0)
	clock := newHandshakeClock()
	clock.now = func() time.Time { return at }
	log := clock.logger(&device.Logger{})

	if _, ok := clock.roundTrip(); ok {
		t.Fatal("a round trip was reported before any handshake")
	}

	log.Verbosef(sendingInitiation, "peer")
	at = at.Add(5 * time.Second) // lost; retried
	log.Verbosef(sendingInitiation, "peer")
	at = at.Add(42 * time.Millisecond)
	log.Verbosef(receivedResponse, "peer")

	rtt, ok := clock.roundTrip()
	if !ok || rtt != 42*time.Millisecond {
		t.Fatalf("round trip = %v (%v), want 42ms from the retry", rtt, ok)
	}

	// A response with no initiation outstanding changes nothing.
	at = at.Add(time.Second)
	log.Verbosef(receivedResponse, "peer")
	if rtt, _ := clock.roundTrip(); rtt != 42*time.Millisecond {
		t.Fatalf("round trip = %v after an unpaired response, want 42ms kept", rtt)
	}
}

func TestHandshakeClockToleratesALoggerWithoutLevels(t *testing.T) {
	t.Parallel()

	// The device calls both functions without checking; nil would crash it.
	log := newHandshakeClock().logger(&device.Logger{})
	log.Verbosef(sendingInitiation, "peer")
	log.Errorf("broken")
}

func TestHandshakeClockPassesLinesOn(t *testing.T) {
	t.Parallel()

	var verbose, errors []string
	base := &device.Logger{
		Verbosef: func(format string, args ...any) { verbose = append(verbose, fmt.Sprintf(format, args...)) },
		Errorf:   func(format string, args ...any) { errors = append(errors, fmt.Sprintf(format, args...)) },
	}
	log := newHandshakeClock().logger(base)
	log.Verbosef(sendingInitiation, "peer(x)")
	log.Errorf("broken %d", 1)

	if len(verbose) != 1 || verbose[0] != "peer(x) - Sending handshake initiation" {
		t.Fatalf("verbose = %q", verbose)
	}
	if len(errors) != 1 || errors[0] != "broken 1" {
		t.Fatalf("errors = %q", errors)
	}
}

// Two real devices on loopback: the clock has to see the device's own log
// lines, so a library upgrade that rewords them fails here rather than as a
// server list with no figures.
func TestHandshakeClockTimesARealHandshake(t *testing.T) {
	t.Parallel()

	serverKey, serverPublic := hexKeyPair(t)
	clientKey, clientPublic := hexKeyPair(t)
	port := awgtest.FreeUDPPort(t)

	serverAddr := netip.MustParseAddr("10.154.0.1")
	clientAddr := netip.MustParseAddr("10.154.0.2")

	serverTun, _, err := netstack.CreateNetTUN([]netip.Addr{serverAddr}, nil, 1420)
	if err != nil {
		t.Fatal(err)
	}
	server := device.NewDevice(serverTun, conn.NewDefaultBind(), device.NewLogger(device.LogLevelSilent, ""))
	defer server.Close()
	if err := server.IpcSet(fmt.Sprintf(
		"private_key=%s\nlisten_port=%d\npublic_key=%s\nallowed_ip=%s/32\n",
		serverKey, port, clientPublic, clientAddr,
	)); err != nil {
		t.Fatal(err)
	}
	if err := server.Up(); err != nil {
		t.Fatal(err)
	}

	clientTun, clientNet, err := netstack.CreateNetTUN([]netip.Addr{clientAddr}, nil, 1420)
	if err != nil {
		t.Fatal(err)
	}
	clock := newHandshakeClock()
	client := device.NewDevice(clientTun, conn.NewDefaultBind(), clock.logger(&device.Logger{}))
	defer client.Close()
	if err := client.IpcSet(fmt.Sprintf(
		"private_key=%s\npublic_key=%s\nendpoint=127.0.0.1:%d\nallowed_ip=%s/32\n",
		clientKey, serverPublic, port, serverAddr,
	)); err != nil {
		t.Fatal(err)
	}
	if err := client.Up(); err != nil {
		t.Fatal(err)
	}

	// Any packet for the peer starts a handshake.
	socket, err := clientNet.DialUDPAddrPort(netip.AddrPort{}, netip.AddrPortFrom(serverAddr, 9))
	if err != nil {
		t.Fatal(err)
	}
	defer socket.Close()
	if _, err := socket.Write([]byte("hello")); err != nil {
		t.Fatal(err)
	}

	deadline := time.Now().Add(10 * time.Second)
	for time.Now().Before(deadline) {
		if rtt, ok := clock.roundTrip(); ok {
			if rtt <= 0 || rtt > 5*time.Second {
				t.Fatalf("round trip on loopback = %v", rtt)
			}
			return
		}
		time.Sleep(10 * time.Millisecond)
	}
	t.Fatal("the handshake completed unseen: has the device reworded its log lines?")
}

// hexKeyPair is a key pair as UAPI takes it.
func hexKeyPair(t *testing.T) (private, public string) {
	t.Helper()
	b64Private, b64Public := awgtest.KeyPair(t)
	return toHex(t, b64Private), toHex(t, b64Public)
}

func toHex(t *testing.T, key string) string {
	t.Helper()
	raw, err := base64.StdEncoding.DecodeString(key)
	if err != nil {
		t.Fatal(err)
	}
	return hex.EncodeToString(raw)
}
