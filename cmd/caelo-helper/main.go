//go:build darwin

// Command caelo-helper is the privileged half of Caelo on macOS.
//
// It runs as root under launchd and does the two things the sandboxed app
// cannot: create a utun interface and change the machine's routing. The app
// drives it over a Unix socket.
//
// It is deliberately small. Everything it accepts is reachable by whoever can
// open that socket, and it runs as root, so the useful measure of this program
// is not what it can do but what it refuses to.
//
// This is the development path. What ships is a NetworkExtension, where the
// system owns the tunnel and no part of Caelo runs as root at all.
package main

import (
	"bufio"
	"encoding/json"
	"flag"
	"fmt"
	"log"
	"net"
	"os"
	"os/signal"
	"syscall"

	"golang.org/x/sys/unix"

	"github.com/TeamGDB/caelo-core/internal/ipc"
	"github.com/TeamGDB/caelo-core/internal/systunnel"
	"github.com/TeamGDB/caelo-core/internal/version"
)

func main() {
	socketPath := flag.String("socket", ipc.SocketPath, "where to listen")
	allowedUID := flag.Int("uid", -1, "the only user allowed to connect")
	verbose := flag.Bool("v", false, "log device internals")
	flag.Parse()

	log.SetPrefix("caelo-helper: ")
	log.SetFlags(log.LstdFlags)

	if os.Geteuid() != 0 {
		log.Fatal("must run as root")
	}
	if *allowedUID < 0 {
		// Refusing to start is the right failure. Defaulting to "anyone" would
		// hand root to every process on the machine, and it would work, so
		// nobody would notice.
		log.Fatal("-uid is required: the helper will not serve an unspecified user")
	}

	controller := systunnel.New(*verbose)

	listener, err := listen(*socketPath, *allowedUID)
	if err != nil {
		log.Fatal(err)
	}
	defer os.Remove(*socketPath)

	// launchd stops us with SIGTERM. Leaving the machine routed through an
	// interface that is about to disappear would look exactly like the network
	// dying for no reason.
	stop := make(chan os.Signal, 1)
	signal.Notify(stop, os.Interrupt, syscall.SIGTERM)
	go func() {
		<-stop
		log.Print("stopping, restoring routing")
		if err := controller.Stop(); err != nil {
			log.Printf("%v", err)
		}
		listener.Close()
		os.Remove(*socketPath)
		os.Exit(0)
	}()

	log.Printf("listening on %s for uid %d", *socketPath, *allowedUID)

	for {
		conn, err := listener.Accept()
		if err != nil {
			return
		}
		go serve(conn.(*net.UnixConn), controller, *allowedUID)
	}
}

// listen creates the socket owned by the one user allowed to use it.
func listen(path string, allowedUID int) (net.Listener, error) {
	// A socket left over from a previous run would make Listen fail. Removing
	// it is safe because only root can write here in the first place.
	_ = os.Remove(path)

	listener, err := net.Listen("unix", path)
	if err != nil {
		return nil, fmt.Errorf("listening on %s: %w", path, err)
	}

	// Belt and braces with the peer check below: file permissions stop the
	// connection being made, the credential check stops it being served.
	if err := os.Chown(path, allowedUID, -1); err != nil {
		listener.Close()
		return nil, fmt.Errorf("setting socket owner: %w", err)
	}
	if err := os.Chmod(path, 0o600); err != nil {
		listener.Close()
		return nil, fmt.Errorf("setting socket permissions: %w", err)
	}

	return listener, nil
}

// peerUID asks the kernel who is on the other end. The answer comes from the
// kernel rather than from the peer, which is the entire point: a caller cannot
// claim to be someone else.
func peerUID(conn *net.UnixConn) (int, error) {
	raw, err := conn.SyscallConn()
	if err != nil {
		return -1, err
	}

	var uid int
	var credErr error
	err = raw.Control(func(fd uintptr) {
		cred, err := unix.GetsockoptXucred(int(fd), unix.SOL_LOCAL, unix.LOCAL_PEERCRED)
		if err != nil {
			credErr = err
			return
		}
		uid = int(cred.Uid)
	})
	if err != nil {
		return -1, err
	}
	return uid, credErr
}

func serve(conn *net.UnixConn, controller *systunnel.Controller, allowedUID int) {
	defer conn.Close()

	uid, err := peerUID(conn)
	if err != nil {
		log.Printf("refusing a connection whose owner could not be established: %v", err)
		return
	}
	if uid != allowedUID && uid != 0 {
		log.Printf("refusing uid %d", uid)
		return
	}

	// One request per connection. A long-lived connection carrying many
	// commands would need its own state machine, and there is nothing here
	// worth that.
	scanner := bufio.NewScanner(conn)
	scanner.Buffer(make([]byte, 0, 64*1024), 256*1024)
	if !scanner.Scan() {
		return
	}

	var request ipc.Request
	if err := json.Unmarshal(scanner.Bytes(), &request); err != nil {
		reply(conn, ipc.Response{Error: "malformed request"})
		return
	}

	reply(conn, handle(request, controller))
}

func handle(request ipc.Request, controller *systunnel.Controller) ipc.Response {
	switch request.Command {
	case ipc.CommandVersion:
		return ipc.Response{OK: true, Core: version.Version, AmneziaWG: version.AmneziaWG()}

	case ipc.CommandStatus:
		return fromStatus(controller.Status())

	case ipc.CommandConnect:
		status, err := controller.Start(request.Config)
		if err != nil {
			log.Printf("connect failed: %v", err)
			return ipc.Response{Error: err.Error()}
		}
		log.Printf("up on %s via %s", status.Interface, status.Endpoint)
		return fromStatus(*status)

	case ipc.CommandDisconnect:
		if err := controller.Stop(); err != nil {
			log.Printf("disconnect: %v", err)
			return ipc.Response{Error: err.Error()}
		}
		log.Print("down, routing restored")
		return ipc.Response{OK: true}

	default:
		// Unknown commands are refused without explanation of what would have
		// worked. There is no audience for that hint except someone probing.
		return ipc.Response{Error: "unknown command"}
	}
}

func fromStatus(status systunnel.Status) ipc.Response {
	return ipc.Response{
		OK:         true,
		Up:         status.Up,
		Interface:  status.Interface,
		Endpoint:   status.Endpoint,
		Protocol:   status.Protocol,
		Obfuscated: status.Obfuscated,
		SinceUnix:  status.SinceUnix,
	}
}

func reply(conn *net.UnixConn, response ipc.Response) {
	encoded, err := json.Marshal(response)
	if err != nil {
		encoded = []byte(`{"ok":false,"error":"failed to encode response"}`)
	}
	conn.Write(append(encoded, '\n'))
}
