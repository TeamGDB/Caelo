// Only where there is no better arrangement. macOS has the NetworkExtension,
// where the system owns the tunnel and nothing of ours runs as root at all;
// this exists because Linux and Windows offer nothing equivalent.
//go:build linux || windows

// Command caelo-service is the privileged half of Caelo on the desktop.
//
// It does the two things an ordinary application cannot: create a tunnel
// interface and change the machine's routing. The app drives it over a local
// socket and never itself runs as root.
//
// It exists only while a tunnel does. systemd hands it a listening socket and
// starts it on the first connection; when nothing is up and nobody is talking
// to it, it exits. A root daemon resident from boot for a VPN that is off most
// of the time is a cost paid continuously for a benefit taken occasionally.
//
// It is deliberately small. Everything it accepts is reachable by whoever can
// open that socket, so the useful measure of this program is not what it can do
// but what it refuses to.
package main

import (
	"bufio"
	"encoding/json"
	"flag"
	"log"
	"net"
	"os"
	"os/signal"
	"sync"
	"syscall"
	"time"

	"github.com/TeamGDB/Caelo/core/internal/ipc"
	"github.com/TeamGDB/Caelo/core/internal/systunnel"
	"github.com/TeamGDB/Caelo/core/internal/version"
)

// stopEverything restores the machine and exits. Set once, in main, so that
// the platform's own stop signal -- a SIGTERM on Linux, the Service Control
// Manager on Windows -- reaches the same path as everything else.
var stopEverything = func(string) {}

func main() {
	socketPath := flag.String("socket", ipc.SocketPath, "where to listen when not socket-activated")
	idle := flag.Duration("idle", 90*time.Second, "exit after this long with nothing up and nobody connected")
	verbose := flag.Bool("v", false, "log device internals")

	// Before the flags: the subcommands take no flags, and Parse would reject
	// them as arguments it did not expect.
	if handled, err := platformCommand(); handled {
		if err != nil {
			log.SetPrefix("caelo-service: ")
			log.Fatal(err)
		}
		return
	}
	flag.Parse()

	log.SetPrefix("caelo-service: ")
	log.SetFlags(log.LstdFlags)

	if err := mustBePrivileged(); err != nil {
		log.Fatal(err)
	}

	controller := systunnel.New(*verbose)

	listener, activated, err := listen(*socketPath)
	if err != nil {
		log.Fatal(err)
	}

	// Only ours to remove if we made it. A socket-activated one belongs to
	// systemd, which reuses it across restarts, and deleting it would leave
	// activation pointing at a path with nothing behind it.
	if !activated {
		defer os.Remove(*socketPath)
	}

	stopEverything = func(why string) {
		shutdown(controller, listener, socketPath, activated, why)
	}

	stopped := make(chan os.Signal, 1)
	signal.Notify(stopped, os.Interrupt, syscall.SIGTERM)

	idler := newIdler(*idle)

	go func() {
		<-stopped
		stopEverything("asked to stop")
	}()
	go func() {
		<-idler.expired
		if controller.Status().Up {
			// Racing with a connect that finished between the timer firing and
			// this check. Losing that race would tear down a tunnel somebody
			// just asked for.
			idler.busy()
			return
		}
		stopEverything("idle")
	}()

	log.Printf("listening on %s", describe(*socketPath, activated))

	accept := func() {
		for {
			conn, err := listener.Accept()
			if err != nil {
				return
			}
			idler.busy()
			go func() {
				defer idler.idle()
				serve(conn, controller)
			}()
		}
	}

	// Under a service manager the accept loop runs in the background while the
	// manager owns the main goroutine. Started from a command line there is
	// nothing else to do with it.
	if managed, err := runManaged(accept); err != nil {
		log.Fatal(err)
	} else if !managed {
		accept()
	}
}

// shutdown restores the machine before the process goes away.
//
// Leaving a machine routed through an interface that is about to disappear
// looks exactly like the network dying for no reason, and the person it happens
// to has no way to connect it to having closed an application.
func shutdown(controller *systunnel.Controller, listener net.Listener, socketPath *string, activated bool, why string) {
	if controller.Status().Up {
		log.Printf("%s: restoring routing first", why)
	}
	if err := controller.Stop(); err != nil {
		log.Printf("%v", err)
	}
	listener.Close()
	if !activated {
		os.Remove(*socketPath)
	}
	os.Exit(0)
}

// idler exits the process once nothing is up and nobody is connected.
//
// The count is of connections rather than of requests: a connection open with
// no request on it yet is somebody about to ask for something.
type idler struct {
	expired chan struct{}

	mu      sync.Mutex
	after   time.Duration
	holders int
	timer   *time.Timer
	fired   bool
}

func newIdler(after time.Duration) *idler {
	i := &idler{expired: make(chan struct{}, 1), after: after}
	i.timer = time.AfterFunc(after, i.fire)
	return i
}

func (i *idler) fire() {
	i.mu.Lock()
	defer i.mu.Unlock()
	if i.holders > 0 || i.fired {
		return
	}
	i.fired = true
	i.expired <- struct{}{}
}

func (i *idler) busy() {
	i.mu.Lock()
	defer i.mu.Unlock()
	i.holders++
	i.fired = false
	i.timer.Stop()
}

func (i *idler) idle() {
	i.mu.Lock()
	defer i.mu.Unlock()
	i.holders--
	if i.holders <= 0 {
		i.holders = 0
		i.timer.Reset(i.after)
	}
}

// describe says where we are listening in a way that distinguishes the two
// ways of getting there, because "listening on /run/caelo/caelo.sock" is the
// same line whether systemd handed it over or we made it ourselves, and those
// have different permissions.
func describe(path string, activated bool) string {
	if activated {
		return path + " (handed over by systemd)"
	}
	return path + " (created here, root only)"
}

// logPeer records who is driving the tunnel. Not a refusal: everything that
// reaches this point already satisfied the socket's permissions. It is here so
// that a socket someone widened by accident shows up as a surprising uid in the
// journal rather than as nothing at all.
func logPeer(uid, pid int) {
	log.Printf("serving uid %d (pid %d)", uid, pid)
}

func serve(conn net.Conn, controller *systunnel.Controller) {
	defer conn.Close()

	if err := authorise(conn); err != nil {
		log.Printf("refusing a connection: %v", err)
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

func reply(conn net.Conn, response ipc.Response) {
	encoded, err := json.Marshal(response)
	if err != nil {
		encoded = []byte(`{"ok":false,"error":"failed to encode response"}`)
	}
	conn.Write(append(encoded, '\n'))
}
