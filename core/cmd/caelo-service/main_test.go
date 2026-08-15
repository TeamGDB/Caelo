//go:build linux || windows

package main

import (
	"strings"
	"testing"

	"github.com/TeamGDB/Caelo/core/internal/ipc"
)

// The controller is nil throughout. That is the property being tested as much
// as the replies are: a request the service will refuse must be refused before
// anything privileged is reached, and a nil pointer is the bluntest way to
// prove nothing touched it.

func TestVersionIsAnsweredWhateverTheCallerSpeaks(t *testing.T) {
	t.Parallel()

	// An app from before this field existed sends nothing, which reads as 0.
	// It still has to get an answer: this is the call it would use to find out
	// that it is the one out of date.
	for _, spoken := range []int{0, ipc.ProtocolVersion, ipc.ProtocolVersion + 7} {
		response := handle(ipc.Request{Command: ipc.CommandVersion, ProtocolVersion: spoken}, nil)
		if !response.OK {
			t.Errorf("version from protocol %d was refused: %s", spoken, response.Error)
		}
		if response.ProtocolVersion != ipc.ProtocolVersion {
			t.Errorf("version from protocol %d answered %d, want %d",
				spoken, response.ProtocolVersion, ipc.ProtocolVersion)
		}
	}
}

func TestMismatchedProtocolIsRefusedBeforeAnythingPrivileged(t *testing.T) {
	t.Parallel()

	for _, command := range []string{ipc.CommandConnect, ipc.CommandDisconnect, ipc.CommandStatus} {
		response := handle(ipc.Request{
			Command:         command,
			ProtocolVersion: ipc.ProtocolVersion + 1,
			Config:          "[Interface]\n",
		}, nil)

		if response.OK {
			t.Errorf("%s was accepted from a protocol this service does not speak", command)
		}
		if response.Error == "" {
			t.Errorf("%s was refused without saying why", command)
		}
	}
}

// Which side is behind decides what the person has to do about it, and the two
// remedies are different: one reinstalls Caelo, the other updates it. A message
// that named the wrong one would send someone to do the wrong thing and find it
// did not help.
func TestRefusalNamesWhichSideIsBehind(t *testing.T) {
	t.Parallel()

	older := handle(ipc.Request{Command: ipc.CommandStatus, ProtocolVersion: 0}, nil)
	if !strings.Contains(older.Error, "application is older") {
		t.Errorf("an old app was not told it is the old one: %q", older.Error)
	}

	newer := handle(ipc.Request{
		Command:         ipc.CommandStatus,
		ProtocolVersion: ipc.ProtocolVersion + 1,
	}, nil)
	if !strings.Contains(newer.Error, "service is older") {
		t.Errorf("a new app was not told the service is the old one: %q", newer.Error)
	}
}

func TestUnknownCommandStillRefusedOnAMatchingProtocol(t *testing.T) {
	t.Parallel()

	response := handle(ipc.Request{
		Command:         "read-every-file",
		ProtocolVersion: ipc.ProtocolVersion,
	}, nil)

	if response.OK {
		t.Fatal("an unknown command was accepted")
	}
	// The refusal must not describe what would have worked; there is no
	// audience for that except someone probing.
	if strings.Contains(response.Error, ipc.CommandConnect) {
		t.Errorf("the refusal lists valid commands: %q", response.Error)
	}
}
