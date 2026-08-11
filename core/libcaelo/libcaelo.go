// Package main builds the core as a C shared library for the desktop apps to
// load.
//
// The surface is deliberately tiny and string-shaped: every call takes and
// returns C strings, and every returned string is owned by the caller, who must
// hand it back to caelo_free. This is scaffolding for the gRPC contract, not a
// replacement for it — the core cannot push events through a function that
// returns once, so the app has to ask rather than be told.
//
// Every call blocks. Callers must not make them on a thread that renders.
package main

/*
#include <stdlib.h>
*/
import "C"

import (
	"encoding/json"
	"time"
	"unsafe"

	"github.com/TeamGDB/caelo-core/internal/awg"
	"github.com/TeamGDB/caelo-core/internal/tunnel"
	"github.com/TeamGDB/caelo-core/internal/version"
)

func main() {}

// session is process-wide because the tunnel is. One application, one tunnel;
// handing the app an opaque handle would imply it could have two, which it
// cannot.
var session = tunnel.New()

// caelo_version returns a JSON object describing this build.
//
//export caelo_version
func caelo_version() *C.char {
	return marshal(map[string]string{
		"core":      version.Version,
		"amneziawg": version.AmneziaWG(),
	})
}

// caelo_connect brings up the tunnel described by an AmneziaWG .conf file and
// leaves it up.
//
// Returning successfully means the device is configured and running. It does
// not mean the peer answered: WireGuard has no connect step, and only traffic
// proves the far end is there. Follow with caelo_check.
//
//export caelo_connect
func caelo_connect(configText *C.char) *C.char {
	info, err := session.Connect(C.GoString(configText))
	if err != nil {
		return failure(err)
	}
	return success(info)
}

// caelo_check fetches url through the live tunnel and reports what came back.
//
//export caelo_check
func caelo_check(url *C.char, timeoutMs C.int) *C.char {
	result, err := session.Check(C.GoString(url), time.Duration(timeoutMs)*time.Millisecond)
	if err != nil {
		return failure(err)
	}
	return success(result)
}

// caelo_disconnect tears the tunnel down.
//
//export caelo_disconnect
func caelo_disconnect() *C.char {
	session.Disconnect()
	return marshal(map[string]any{"ok": true})
}

// caelo_status reports whether a tunnel is up without disturbing it.
//
//export caelo_status
func caelo_status() *C.char {
	up, endpoint := session.Up()
	return marshal(map[string]any{"ok": true, "up": up, "endpoint": endpoint})
}

// caelo_describe reports the parameters a host needs to create a tun device for
// a configuration, without connecting anything.
//
// Android's VpnService.Builder wants the address, MTU, DNS servers and routes
// before it will hand back a descriptor. They come from here rather than from a
// parser on the platform side: a second implementation of this format would
// eventually disagree with the one that actually dials.
//
//export caelo_describe
func caelo_describe(configText *C.char) *C.char {
	cfg, err := awg.ParseConfig(C.GoString(configText))
	if err != nil {
		return failure(err)
	}

	addresses := make([]string, 0, len(cfg.Addresses))
	for _, address := range cfg.Addresses {
		addresses = append(addresses, address.String())
	}

	dns := make([]string, 0, len(cfg.DNS))
	for _, server := range cfg.DNS {
		dns = append(dns, server.String())
	}
	if len(dns) == 0 {
		// Resolution has to happen inside the tunnel, so a device with no DNS
		// configured still needs one that is reachable through it.
		dns = []string{"1.1.1.1"}
	}

	return marshal(map[string]any{
		"ok":          true,
		"addresses":   addresses,
		"mtu":         cfg.MTU,
		"dns":         dns,
		"allowed_ips": cfg.Peer.AllowedIPs,
		"endpoint":    cfg.Peer.Endpoint,
		"obfuscated":  len(cfg.Obfuscation) > 0,
	})
}

// caelo_free releases a string returned by any function in this library.
//
//export caelo_free
func caelo_free(s *C.char) {
	if s != nil {
		C.free(unsafe.Pointer(s))
	}
}

// success renders v as a JSON object with ok set.
//
// Failures are reported inside the payload rather than through a status code:
// the caller is a user interface that has to show something either way, and a
// tunnel that did not come up is an ordinary outcome for this product.
func success(v any) *C.char {
	payload := map[string]any{}
	encoded, err := json.Marshal(v)
	if err != nil {
		return failure(err)
	}
	if err := json.Unmarshal(encoded, &payload); err != nil {
		return failure(err)
	}
	payload["ok"] = true
	return marshal(payload)
}

func failure(err error) *C.char {
	return marshal(map[string]any{"ok": false, "error": err.Error()})
}

func marshal(v any) *C.char {
	encoded, err := json.Marshal(v)
	if err != nil {
		// Losing the real error here is acceptable; failing to return a
		// parseable object is not, because the caller has no other channel.
		return C.CString(`{"ok":false,"error":"failed to encode result"}`)
	}
	return C.CString(string(encoded))
}
