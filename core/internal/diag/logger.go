package diag

import "github.com/amnezia-vpn/amneziawg-go/v3/device"

// DeviceLogger routes the tunnel's own logging into the ring, so that what the
// handshake had to say is in the same place as everything else.
//
// The device layer distinguishes errors from verbose chatter, and so does this:
// errors are always kept, and the rest only when verbose logging is on. That
// distinction is the whole reason the ring is still readable after a minute of
// keepalives.
func DeviceLogger() *device.Logger {
	return &device.Logger{
		Verbosef: Verbosef,
		Errorf:   func(format string, args ...any) { Logf("error: "+format, args...) },
	}
}
