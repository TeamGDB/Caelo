// Package ipc defines how the app talks to the privileged service.
//
// The protocol is newline-delimited JSON over a local socket, one request per
// connection. It is small on purpose: the service runs as root, so every
// command it accepts is attack surface, and a protocol nobody can hold in their
// head is one nobody can review.
package ipc

// SocketPath is where the service listens on Linux.
//
// Under /run rather than /tmp: /tmp is world-writable, so an attacker could
// create the socket first and have the app talk to them instead. The directory
// is owned by root and the socket itself is created by systemd, which is what
// decides who may open it — see packaging/linux/systemd.
const SocketPath = "/run/caelo/caelo.sock"

// PipeName is where the service listens on Windows.
const PipeName = `\\.\pipe\caelo`

// Command names. Anything else is refused.
const (
	CommandConnect    = "connect"
	CommandDisconnect = "disconnect"
	CommandStatus     = "status"
	CommandVersion    = "version"
)

// Request is one command from the app.
type Request struct {
	Command string `json:"command"`

	// Config is the AmneziaWG .conf, sent with connect. It is passed over the
	// socket rather than by path: the service runs as root and would happily
	// read any file it were pointed at, which turns "connect" into "read any
	// file on this machine".
	Config string `json:"config,omitempty"`
}

// Response is what the service answers.
type Response struct {
	OK    bool   `json:"ok"`
	Error string `json:"error,omitempty"`

	Up         bool   `json:"up,omitempty"`
	Interface  string `json:"interface,omitempty"`
	Endpoint   string `json:"endpoint,omitempty"`
	Protocol   string `json:"protocol,omitempty"`
	Obfuscated bool   `json:"obfuscated,omitempty"`
	SinceUnix  int64  `json:"since_unix,omitempty"`

	Core      string `json:"core,omitempty"`
	AmneziaWG string `json:"amneziawg,omitempty"`
}
