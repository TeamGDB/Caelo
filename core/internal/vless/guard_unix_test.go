//go:build !windows

package vless

import (
	"bytes"
	"encoding/binary"
	"os"
	"testing"
	"time"

	"golang.org/x/sys/unix"
)

func socketFiles(t *testing.T) (*os.File, *os.File) {
	t.Helper()
	pair, err := unix.Socketpair(unix.AF_UNIX, unix.SOCK_DGRAM, 0)
	if err != nil {
		t.Fatal(err)
	}
	for _, fd := range pair {
		if err := unix.SetNonblock(fd, true); err != nil {
			t.Fatal(err)
		}
	}
	a, b := os.NewFile(uintptr(pair[0]), "test-host"), os.NewFile(uintptr(pair[1]), "test-tun")
	t.Cleanup(func() { a.Close(); b.Close() })
	return a, b
}

func readPacketTest(t *testing.T, f *os.File) []byte {
	t.Helper()
	if err := f.SetReadDeadline(time.Now().Add(time.Second)); err != nil {
		t.Fatal(err)
	}
	b := make([]byte, 65580)
	n, err := f.Read(b)
	if err != nil {
		t.Fatal(err)
	}
	return b[:n]
}

func TestIPv6GuardPreservesPacketsAndCloses(t *testing.T) {
	for _, prefix := range []int{0, 4} {
		t.Run(string(rune('0'+prefix)), func(t *testing.T) {
			host, tun := socketFiles(t)
			g, err := newIPv6Guard(int(tun.Fd()), prefix)
			if err != nil {
				t.Fatal(err)
			}
			defer g.Close()
			engineFD, err := unix.Dup(g.FD())
			if err != nil {
				t.Fatal(err)
			}
			unix.SetNonblock(engineFD, true)
			engine := os.NewFile(uintptr(engineFD), "test-engine")
			defer engine.Close()
			frame := func(p []byte) []byte {
				out := make([]byte, prefix+len(p))
				if prefix == 4 {
					family := uint32(2)
					if p[0]>>4 == 6 {
						family = 30
					}
					binary.BigEndian.PutUint32(out, family)
				}
				copy(out[prefix:], p)
				return out
			}
			v4 := frame([]byte{0x45, 1, 2, 3, 4})
			if err := writePacket(host, v4); err != nil {
				t.Fatal(err)
			}
			if got := readPacketTest(t, engine); !bytes.Equal(got, v4) {
				t.Fatal("outbound IPv4 changed")
			}
			if err := writePacket(engine, v4); err != nil {
				t.Fatal(err)
			}
			if got := readPacketTest(t, host); !bytes.Equal(got, v4) {
				t.Fatal("inbound IPv4 changed")
			}
			v6 := frame(ipv6Packet(6, make([]byte, 20)))
			if err := writePacket(host, v6); err != nil {
				t.Fatal(err)
			}
			got := readPacketTest(t, host)
			if !bytes.Equal(got[:prefix], v6[:prefix]) || !bytes.Equal(got[prefix:], rejectIPv6(v6[prefix:])) {
				t.Fatal("bad IPv6 rejection")
			}
			// A following IPv4 packet must be the next packet Xray sees, never the IPv6 SYN.
			writePacket(host, v4)
			if got := readPacketTest(t, engine); !bytes.Equal(got, v4) {
				t.Fatal("IPv6 reached Xray")
			}
			done := make(chan struct{})
			go func() { g.Close(); g.Close(); close(done) }()
			select {
			case <-done:
			case <-time.After(time.Second):
				t.Fatal("close left blocked readers")
			}
			if g.Failed() {
				t.Fatal("normal close marked as failure")
			}
		})
	}
}
