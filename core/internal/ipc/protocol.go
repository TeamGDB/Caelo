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

// ProtocolVersion is the version of this wire format.
//
// Deliberately not the product version. It changes when the meaning of what
// crosses this socket changes — a field removed, a command's behaviour altered —
// and stays put through every release that does not touch the protocol, which is
// most of them. Tying it to the product version would force a lockstep upgrade
// on every release and teach people to ignore the resulting warnings.
//
// It exists because the app and the service stop moving together the moment
// updates apply themselves. Until then both halves only ever changed when a
// person installed something; afterwards, an AppImage can meet a service
// installed months earlier from a package, a Windows upgrade whose service
// restart failed leaves a new app talking to an old service, and someone can
// decline the macOS extension prompt and be left in exactly this state.
//
// The alternative to checking is not "it works anyway". It is a connect that
// hangs, and logs that do not say why.
const ProtocolVersion = 1

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

	// ProtocolVersion is what the app was built against. Absent means an app
	// from before this field existed, which reads as 0 and mismatches — which is
	// correct, because such an app is by definition older than the service
	// checking it.
	ProtocolVersion int `json:"protocol_version,omitempty"`

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

	// ProtocolVersion answers what the service speaks. Sent only with version,
	// which is the one command that is always answered — discovering a mismatch
	// must not itself require a matching protocol.
	ProtocolVersion int `json:"protocol_version,omitempty"`
}
