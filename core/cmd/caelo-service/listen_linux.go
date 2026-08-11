//go:build linux

package main

import (
	"fmt"
	"net"
	"os"
	"path/filepath"
	"strconv"

	"golang.org/x/sys/unix"
)

// listenFDStart is the first descriptor systemd passes. Fixed by the protocol:
// 0, 1 and 2 are the standard streams, so the first one handed over is 3.
const listenFDStart = 3

// listen returns the socket to serve on, and whether systemd provided it.
//
// Socket activation is what makes this program able to not exist most of the
// time. systemd holds the listening socket, the app connects to it, and only
// then is anything started as root. Nothing has to run between sessions, and
// nothing has to ask anybody for a password.
//
// The fallback path is for running it by hand during development, where there
// is no systemd to hand anything over.
func listen(path string) (net.Listener, bool, error) {
	if listener, ok, err := activated(); ok || err != nil {
		return listener, true, err
	}

	// A socket left over from a previous run would make Listen fail. Removing
	// it is safe because only root can write to this directory in the first
	// place.
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return nil, false, fmt.Errorf("creating the socket directory: %w", err)
	}
	_ = os.Remove(path)

	listener, err := net.Listen("unix", path)
	if err != nil {
		return nil, false, fmt.Errorf("listening on %s: %w", path, err)
	}
	// Root only. Anything wider is the packaged socket unit's decision to make,
	// not this fallback's: a development run should not quietly become the
	// most permissive way to reach a root process on the machine.
	if err := os.Chmod(path, 0o600); err != nil {
		listener.Close()
		return nil, false, fmt.Errorf("setting socket permissions: %w", err)
	}
	return listener, false, nil
}

// activated picks up the socket systemd is holding, if there is one.
//
// LISTEN_PID is checked against our own: the variables are inherited, so a
// child process would otherwise believe it had been handed descriptors that
// belong to its parent.
func activated() (net.Listener, bool, error) {
	if pid, err := strconv.Atoi(os.Getenv("LISTEN_PID")); err != nil || pid != os.Getpid() {
		return nil, false, nil
	}
	count, err := strconv.Atoi(os.Getenv("LISTEN_FDS"))
	if err != nil || count < 1 {
		return nil, false, nil
	}
	if count > 1 {
		return nil, true, fmt.Errorf("systemd passed %d sockets; this program serves one", count)
	}

	// Not inherited any further. A tunnel process started from here has no use
	// for the listening socket and every reason not to hold it open.
	unix.CloseOnExec(listenFDStart)

	file := os.NewFile(listenFDStart, "systemd socket")
	listener, err := net.FileListener(file)
	// FileListener duplicates the descriptor, so ours is now spare.
	file.Close()
	if err != nil {
		return nil, true, fmt.Errorf("adopting the socket systemd passed: %w", err)
	}
	return listener, true, nil
}

// authorise asks the kernel who is on the other end.
//
// The answer comes from the kernel rather than from the peer, which is the
// entire point: a caller cannot claim to be someone else. What it is checked
// against is the socket's own permissions — systemd creates it owned by the
// caelo group — so this is the second of two locks rather than the only one.
// It exists to make a misconfigured socket visible in the log instead of
// silently serving the machine.
func authorise(conn net.Conn) error {
	unixConn, ok := conn.(*net.UnixConn)
	if !ok {
		return fmt.Errorf("not a unix socket")
	}

	raw, err := unixConn.SyscallConn()
	if err != nil {
		return err
	}

	var cred *unix.Ucred
	var credErr error
	if err := raw.Control(func(fd uintptr) {
		cred, credErr = unix.GetsockoptUcred(int(fd), unix.SOL_SOCKET, unix.SO_PEERCRED)
	}); err != nil {
		return err
	}
	if credErr != nil {
		return fmt.Errorf("establishing who is connected: %w", credErr)
	}

	// Logged rather than silent. Everything that reaches here got through the
	// socket's permissions, so the interesting case is not a refusal but a uid
	// nobody expected.
	logPeer(int(cred.Uid), int(cred.Pid))
	return nil
}
