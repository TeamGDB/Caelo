// Package handshake reads when a device last heard from its peer.
//
// The device does not announce handshakes; the time of the last one is part of
// its state and is read through the same IPC that configured it.
package handshake

import (
	"strconv"
	"strings"
	"time"
)

// Parse finds the most recent handshake in a UAPI dump. Zero means none yet.
func Parse(uapi string) time.Time {
	var latest time.Time
	for _, line := range strings.Split(uapi, "\n") {
		value, ok := strings.CutPrefix(line, "last_handshake_time_sec=")
		if !ok {
			continue
		}
		seconds, err := strconv.ParseInt(strings.TrimSpace(value), 10, 64)
		if err != nil || seconds <= 0 {
			continue
		}
		if at := time.Unix(seconds, 0); at.After(latest) {
			latest = at
		}
	}
	return latest
}

// Wait polls read until it reports a handshake or timeout runs out.
func Wait(read func() (string, error), timeout time.Duration) bool {
	deadline := time.Now().Add(timeout)
	for {
		if uapi, err := read(); err == nil && !Parse(uapi).IsZero() {
			return true
		}
		if time.Now().After(deadline) {
			return false
		}
		time.Sleep(200 * time.Millisecond)
	}
}
