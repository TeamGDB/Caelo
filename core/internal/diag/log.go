// Package diag keeps the recent history of what the core did, so that a person
// whose tunnel will not come up can hand someone else something to read.
//
// It is a ring in memory rather than a file: the core is a library inside
// somebody else's process and has no business choosing where that process
// writes. The application owns persistence.
//
// Everything here is safe for concurrent use and none of it blocks — the
// device layer logs from the middle of packet handling, and a logger that can
// stall the tunnel is worse than no logger.
package diag

import (
	"fmt"
	"regexp"
	"sync"
	"time"
)

// capacity is how many lines are kept. Enough to cover a failed connection
// attempt and the minute around it, small enough to hand to someone.
const capacity = 400

var (
	mu      sync.Mutex
	lines   = make([]string, 0, capacity)
	verbose bool
)

// secrets matches things that must never reach a log someone might send on:
// base64 Curve25519 keys, their hex form, and anything a UAPI line labels as
// key material.
//
// This runs on every line rather than at the call sites. Call sites are added
// by people, and the one that forgets is the one that matters.
var secrets = regexp.MustCompile(
	`(?i)((?:private|public|preshared)[_ ]?key\s*[=:]\s*)\S+` +
		`|[A-Za-z0-9+/]{42}[A-Za-z0-9+/=]{1,2}` +
		`|\b[0-9a-f]{64}\b`,
)

func redact(message string) string {
	return secrets.ReplaceAllStringFunc(message, func(match string) string {
		if i := indexOfAssignment(match); i >= 0 {
			return match[:i+1] + "<redacted>"
		}
		return "<redacted>"
	})
}

func indexOfAssignment(s string) int {
	for i, r := range s {
		if r == '=' || r == ':' {
			return i
		}
	}
	return -1
}

// Logf records a line. Timestamps are UTC so that logs from two machines can
// be read side by side.
func Logf(format string, args ...any) {
	line := fmt.Sprintf("%s  %s",
		time.Now().UTC().Format("15:04:05.000"),
		redact(fmt.Sprintf(format, args...)),
	)

	mu.Lock()
	defer mu.Unlock()

	if len(lines) == capacity {
		// Drop the oldest. Copying is cheap at this size and keeps the read
		// path a plain slice rather than a ring anyone has to reason about.
		copy(lines, lines[1:])
		lines = lines[:capacity-1]
	}
	lines = append(lines, line)
}

// Verbosef records a line only when verbose logging is on.
//
// The device layer calls this for every handshake and every keepalive. Left on
// by default it would fill the ring in a minute and push out the connection
// attempt someone is trying to read.
func Verbosef(format string, args ...any) {
	mu.Lock()
	on := verbose
	mu.Unlock()

	if on {
		Logf(format, args...)
	}
}

// SetVerbose turns detailed logging on or off. It takes effect immediately,
// including for a tunnel that is already up.
func SetVerbose(on bool) {
	mu.Lock()
	defer mu.Unlock()
	verbose = on
	lines = append(lines, fmt.Sprintf("%s  verbose logging %s",
		time.Now().UTC().Format("15:04:05.000"),
		map[bool]string{true: "on", false: "off"}[on]))
}

// Verbose reports whether detailed logging is on.
func Verbose() bool {
	mu.Lock()
	defer mu.Unlock()
	return verbose
}

// Lines returns a copy of everything kept, oldest first.
func Lines() []string {
	mu.Lock()
	defer mu.Unlock()
	return append([]string(nil), lines...)
}

// Clear forgets everything.
func Clear() {
	mu.Lock()
	defer mu.Unlock()
	lines = lines[:0]
}
