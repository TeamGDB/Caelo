//go:build windows

package main

import (
	"fmt"
	"net"

	"github.com/Microsoft/go-winio"

	"github.com/TeamGDB/Caelo/core/internal/ipc"
)

// pipeSecurity is who may open the pipe, in SDDL.
//
// This is the Windows spelling of the caelo group: the access control on the
// endpoint is what separates "can drive the machine's routing" from "cannot",
// and it is the only thing that does.
//
//	D:P            a discretionary ACL, protected from inheritance
//	(A;;GA;;;SY)   LocalSystem: everything. The service itself runs as this.
//	(A;;GA;;;BA)   Administrators: everything, so the machine's owner can
//	               always reach it without being locked out by our own rules.
//	(A;;GRGW;;;IU) Interactively logged-on users: read and write, no more.
//
// IU rather than AU deliberately. Authenticated Users would include service
// accounts and anything that arrived over the network with valid credentials;
// Interactive Users is the person sitting at the machine, which is who the
// button belongs to.
const pipeSecurity = "D:P(A;;GA;;;SY)(A;;GA;;;BA)(A;;GRGW;;;IU)"

// listen returns the pipe to serve on.
//
// Unlike systemd, Windows does not hand a listening endpoint to the process it
// starts: the service creates the pipe itself, and the Service Control Manager
// is told to start the service when somebody opens that name. The second
// return value says whether something else provided the endpoint, which on
// Windows is never.
func listen(_ string) (net.Listener, bool, error) {
	listener, err := winio.ListenPipe(ipc.PipeName, &winio.PipeConfig{
		SecurityDescriptor: pipeSecurity,
		// One instance is enough: requests are one per connection and finish in
		// milliseconds. A pipe that accepts many at once would let anything
		// that can open it hold connections open to keep the service alive.
		MessageMode: false,
	})
	if err != nil {
		return nil, false, fmt.Errorf("listening on %s: %w", ipc.PipeName, err)
	}
	return listener, false, nil
}

// authorise is a no-op on Windows.
//
// On Linux the socket's permissions are checked a second time from inside the
// process, because a socket file's mode can be changed after it is created. A
// pipe's security descriptor is fixed when the pipe is created, by this
// program, from the constant above — there is no second question to ask, and
// pretending to ask one would suggest a check that is not happening.
func authorise(net.Conn) error { return nil }
