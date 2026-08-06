// Package main builds the core as a C shared library for the desktop apps to
// load.
//
// The surface is deliberately tiny and string-shaped: every call takes and
// returns C strings, and every returned string is owned by the caller, who must
// hand it back to caelo_free. This is scaffolding for the gRPC contract, not a
// replacement for it — a real connection has a lifecycle and pushes events,
// which does not fit through a function that returns once.
package main

/*
#include <stdlib.h>
*/
import "C"

import (
	"encoding/json"
	"time"
	"unsafe"

	"github.com/TeamGDB/caelo-core/internal/probe"
	"github.com/TeamGDB/caelo-core/internal/version"
)

func main() {}

// caelo_version returns a JSON object describing this build.
//
//export caelo_version
func caelo_version() *C.char {
	return marshal(map[string]string{
		"core":      version.Version,
		"amneziawg": version.AmneziaWG(),
	})
}

// caelo_probe brings up the tunnel described by configText, fetches url through
// it, and returns the outcome as JSON.
//
// Errors are returned in the JSON rather than through a status code: the caller
// is a UI that has to show the user something either way, and a failed probe is
// an ordinary result, not an exceptional one.
//
//export caelo_probe
func caelo_probe(configText, url *C.char, timeoutMs C.int) *C.char {
	result, err := probe.Run(C.GoString(configText), probe.Options{
		URL:     C.GoString(url),
		Timeout: time.Duration(timeoutMs) * time.Millisecond,
	})
	if err != nil {
		return marshal(map[string]any{"ok": false, "error": err.Error()})
	}

	payload := map[string]any{"ok": true}
	encoded, _ := json.Marshal(result)
	_ = json.Unmarshal(encoded, &payload)
	payload["ok"] = true
	return marshal(payload)
}

// caelo_free releases a string returned by any function in this library.
//
//export caelo_free
func caelo_free(s *C.char) {
	if s != nil {
		C.free(unsafe.Pointer(s))
	}
}

// marshal renders v as a C string the caller owns.
func marshal(v any) *C.char {
	encoded, err := json.Marshal(v)
	if err != nil {
		// Losing the real error here is acceptable; failing to return a
		// parseable object is not, because the caller has no other channel.
		return C.CString(`{"ok":false,"error":"failed to encode result"}`)
	}
	return C.CString(string(encoded))
}
