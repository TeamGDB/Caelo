//go:build !windows

package vless

import (
	"errors"
	"os"
	"testing"

	"golang.org/x/sys/unix"

	"github.com/TeamGDB/Caelo/core/internal/vless/vlesstest"
)

// On Android the core is handed the VPN descriptor and must close it: that
// is what takes the interface down. Xray reads a duplicate, so the original
// is closed with the tunnel — once, however often Close is called.
func TestATunnelGivenADescriptorClosesIt(t *testing.T) {
	server := vlesstest.Start(t, vlesstest.RealityVision)
	link, err := Parse(server.Link)
	if err != nil {
		t.Fatal(err)
	}
	in, err := start(link, options{})
	if err != nil {
		t.Fatal(err)
	}
	read, write, err := os.Pipe()
	if err != nil {
		t.Fatal(err)
	}
	defer write.Close()
	fd, err := unix.Dup(int(read.Fd()))
	if err != nil {
		t.Fatal(err)
	}
	read.Close()

	owned := &ownedFd{Tunnel: in, fd: fd}
	owned.Close()
	owned.Close()
	if _, err := unix.FcntlInt(uintptr(fd), unix.F_GETFD, 0); !errors.Is(err, unix.EBADF) {
		t.Fatalf("descriptor still open after Close: %v", err)
	}
}
