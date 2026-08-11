//go:build android || linux || darwin

package main

/*
#include <stdlib.h>
*/
import "C"

import (
	"github.com/TeamGDB/Caelo/core/internal/fdtun"
)

// hosted is the tunnel running on a device the platform created for us. One
// application, one tunnel; an opaque handle would imply otherwise.
var hosted = fdtun.New()

// caelo_connect_fd runs AmneziaWG over a tun descriptor the host has already
// created, addressed and routed.
//
// This is the Android path, where the application is not permitted to open a
// tun device: VpnService does it and hands back a descriptor. Ownership of the
// descriptor passes to the core, which closes it on disconnect.
//
//export caelo_connect_fd
func caelo_connect_fd(tunFd C.int, configText *C.char) *C.char {
	status, err := hosted.Start(int(tunFd), C.GoString(configText))
	if err != nil {
		return failure(err)
	}
	return success(status)
}

// caelo_socket_fds reports the sockets carrying tunnel traffic, so the host can
// exclude them from its own routing.
//
// On Android that is VpnService.protect. This never fails: either descriptor
// may come back as -1, on a device without that address family or before the
// bind has opened, and the caller simply skips it. Treating that as an error
// would refuse to connect on a working network.
//
//export caelo_socket_fds
func caelo_socket_fds() *C.char {
	v4, v6 := hosted.SocketFds()
	return marshal(map[string]any{"ok": true, "v4": v4, "v6": v6})
}

// caelo_disconnect_fd stops the hosted tunnel and closes its descriptor.
//
//export caelo_disconnect_fd
func caelo_disconnect_fd() *C.char {
	hosted.Stop()
	return marshal(map[string]any{"ok": true})
}

// caelo_status_fd reports whether the hosted tunnel is up.
//
//export caelo_status_fd
func caelo_status_fd() *C.char {
	return success(hosted.Status())
}
