//go:build darwin

package vless

import (
	"bytes"
	"errors"
	"os"
	"testing"
	"time"

	"golang.org/x/sys/unix"
)

// Darwin returns ENOBUFS rather than EAGAIN when a Unix datagram receiver
// falls behind. A real bounded socket catches the failure seen on iOS (#176).
func TestGuardSurvivesDarwinReceiverPressure(t *testing.T) {
	for _, reverse := range []bool{false, true} {
		name := "to_engine"
		if reverse {
			name = "to_host"
		}
		t.Run(name, func(t *testing.T) { testGuardReceiverPressure(t, reverse) })
	}
}
func testGuardReceiverPressure(t *testing.T, reverse bool) {
	host, tun := socketFiles(t)
	guard, err := newIPv6Guard(int(tun.Fd()), 4)
	if err != nil {
		t.Fatal(err)
	}
	defer guard.Close()
	g := guard.(*fdGuard)
	engineFD, err := unix.Dup(g.FD())
	if err != nil {
		t.Fatal(err)
	}
	if err = unix.SetNonblock(engineFD, true); err != nil {
		t.Fatal(err)
	}

	engine := os.NewFile(uintptr(engineFD), "slow-engine")
	defer engine.Close()
	sender, receiver := host, engine
	if reverse {
		sender, receiver = engine, host
	}
	receiveRaw, _ := receiver.SyscallConn()
	_ = receiveRaw.Control(func(fd uintptr) { err = unix.SetsockoptInt(int(fd), unix.SOL_SOCKET, unix.SO_RCVBUF, 4096) })
	if err != nil {
		t.Fatal(err)
	}
	raw, _ := sender.SyscallConn()
	packet := append([]byte{0, 0, 0, 2, 0x45}, bytes.Repeat([]byte{7}, 1399)...)
	until := time.Now().Add(100 * time.Millisecond)
	for time.Now().Before(until) {
		var writeErr error
		_ = raw.Control(func(fd uintptr) { _, writeErr = unix.Write(int(fd), packet) })
		if writeErr != nil && !errors.Is(writeErr, unix.ENOBUFS) && !errors.Is(writeErr, unix.EAGAIN) {
			t.Fatal(writeErr)
		}
		time.Sleep(time.Millisecond)
	}
	if g.Failed() {
		t.Fatal("temporary receiver pressure permanently stopped the packet bridge")
	}
	if g.pressure.Load() == 0 || g.dropped.Load() == 0 {
		t.Fatal("test did not fill the real receiver queue")
	}
	// Drain the queued burst, then prove both directions still carry packets.
	_ = receiver.SetReadDeadline(time.Now().Add(50 * time.Millisecond))
	b := make([]byte, 65580)
	for {
		if _, err = receiver.Read(b); err != nil {
			break
		}
	}
	_ = receiver.SetReadDeadline(time.Time{})
	marker := []byte{0, 0, 0, 2, 0x45, 9, 8, 7, 6}
	if err = writePacket(sender, marker); err != nil {
		t.Fatal(err)
	}
	if got := readPacketTest(t, receiver); !bytes.Equal(got, marker) {
		t.Fatal("forwarding did not recover")
	}
	if err = writePacket(receiver, marker); err != nil {
		t.Fatal(err)
	}
	if got := readPacketTest(t, sender); !bytes.Equal(got, marker) {
		t.Fatal("return traffic did not recover")
	}
}

func TestGuardCloseInterruptsPressure(t *testing.T) {
	host, tun := socketFiles(t)
	raw, err := newIPv6Guard(int(tun.Fd()), 4)
	if err != nil {
		t.Fatal(err)
	}
	g := raw.(*fdGuard)
	defer g.Close()
	packet := append([]byte{0, 0, 0, 2, 0x45}, bytes.Repeat([]byte{1}, 1399)...)
	input, _ := host.SyscallConn()
	until := time.Now().Add(time.Second)
	for g.pressure.Load() == 0 && time.Now().Before(until) {
		_ = input.Control(func(fd uintptr) { _, _ = unix.Write(int(fd), packet) })
		time.Sleep(time.Millisecond)
	}
	if g.pressure.Load() == 0 {
		t.Fatal("test did not reach socket pressure")
	}
	stopped := make(chan struct{})
	go func() { g.Close(); close(stopped) }()
	select {
	case <-stopped:
	case <-time.After(time.Second):
		t.Fatal("close left pressure writers blocked")
	}
	if g.Failed() {
		t.Fatal("user stop was reported as a transport failure")
	}
}
