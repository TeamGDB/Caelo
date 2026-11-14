package vless

import (
	"bytes"
	"encoding/binary"
	"net"
	"testing"

	"golang.org/x/net/icmp"
	"golang.org/x/net/ipv6"
)

func ipv6Packet(next byte, payload []byte) []byte {
	p := make([]byte, 40+len(payload))
	p[0], p[6], p[7] = 0x60, next, 64
	binary.BigEndian.PutUint16(p[4:6], uint16(len(payload)))
	copy(p[8:24], net.ParseIP("fdfe:dcba:9876::1").To16())
	copy(p[24:40], net.ParseIP("2001:db8::2").To16())
	copy(p[40:], payload)
	return p
}

func TestIPv6RejectIsValidAndBounded(t *testing.T) {
	for _, size := range []int{20, 2000} {
		p := ipv6Packet(6, make([]byte, size))
		reply := rejectIPv6(p)
		if len(reply) > 1280 || len(reply) < 48 || reply[6] != 58 {
			t.Fatalf("invalid reply length/header: %d", len(reply))
		}
		if !bytes.Equal(reply[8:24], p[24:40]) || !bytes.Equal(reply[24:40], p[8:24]) {
			t.Fatal("addresses not reversed")
		}
		if int(binary.BigEndian.Uint16(reply[4:6])) != len(reply)-40 {
			t.Fatal("wrong payload length")
		}
		m, err := icmp.ParseMessage(58, reply[40:])
		if err != nil {
			t.Fatal(err)
		}
		if m.Type != ipv6.ICMPTypeDestinationUnreachable || m.Code != 0 {
			t.Fatal("not a no-route error")
		}
		quote := m.Body.(*icmp.DstUnreach).Data
		if !bytes.Equal(quote, p[:len(quote)]) {
			t.Fatal("bad packet quote")
		}
		// Marshal recomputes the pseudo-header checksum; compare with the wire value.
		wire, err := m.Marshal(icmp.IPv6PseudoHeader(reply[8:24], reply[24:40]))
		if err != nil {
			t.Fatal(err)
		}
		if !bytes.Equal(wire, reply[40:]) {
			t.Fatal("bad checksum")
		}
	}
}

func TestIPv6RejectDoesNotCreateErrorLoops(t *testing.T) {
	errorPacket := ipv6Packet(58, []byte{1, 0, 0, 0, 0, 0, 0, 0})
	extensionError := ipv6Packet(0, append([]byte{58, 0, 0, 0, 0, 0, 0, 0}, errorPacket[40:]...))
	fragment := ipv6Packet(44, []byte{6, 0, 0, 8, 0, 0, 0, 0})
	multicast := ipv6Packet(6, make([]byte, 20))
	copy(multicast[24:40], net.ParseIP("ff02::1").To16())
	unspecified := ipv6Packet(6, make([]byte, 20))
	clear(unspecified[8:24])
	for _, p := range [][]byte{nil, errorPacket, extensionError, fragment, multicast, unspecified, ipv6Packet(6, make([]byte, 20))[:50], ipv6Packet(0, []byte{6, 10})} {
		if rejectIPv6(p) != nil {
			t.Fatalf("answered invalid/error packet %x", p)
		}
	}
	echo := ipv6Packet(58, []byte{128, 0, 0, 0, 0, 0, 0, 0})
	if rejectIPv6(echo) == nil {
		t.Fatal("echo request should get an error")
	}
	extensionTCP := ipv6Packet(60, append([]byte{6, 0, 0, 0, 0, 0, 0, 0}, make([]byte, 20)...))
	if rejectIPv6(extensionTCP) == nil {
		t.Fatal("valid extension chain rejected")
	}
}
