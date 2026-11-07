package probe

import (
	"sync"
	"time"

	"github.com/amnezia-vpn/amneziawg-go/v3/device"
)

// The device layer's own words for the two ends of a handshake. They are the
// only place it says when an initiation went out and when a response was
// accepted. Packets on the wire cannot tell us, because header protection and
// the H1–H4 ranges hide the message type.
//
// TestHandshakeClockTimesARealHandshake fails if an upgrade rewords them.
const (
	sendingInitiation = "%v - Sending handshake initiation"
	receivedResponse  = "%v - Received handshake response"
)

// handshakeClock times the round trip of a handshake: from sending the
// initiation to accepting the server's response.
//
// That is the round trip to the server itself, and the closest thing a
// WireGuard tunnel has to a ping. Unlike a request through the tunnel, it does
// not include whatever lies beyond the server or how long a website took to
// answer (#154).
//
// Only the last initiation counts. A retry replaces the device's handshake
// state, so a late reply to an earlier initiation is rejected as invalid and
// never logged as received, and pairing it with the retry would be wrong anyway.
type handshakeClock struct {
	mu   sync.Mutex
	sent time.Time
	rtt  time.Duration
	done bool
	now  func() time.Time
}

func newHandshakeClock() *handshakeClock {
	return &handshakeClock{now: time.Now}
}

// logger passes everything on to base and watches it go by. The device calls
// both functions unconditionally, so a level base leaves out is discarded
// rather than left nil.
func (c *handshakeClock) logger(base *device.Logger) *device.Logger {
	verbose, errorf := base.Verbosef, base.Errorf
	if verbose == nil {
		verbose = device.DiscardLogf
	}
	if errorf == nil {
		errorf = device.DiscardLogf
	}
	return &device.Logger{
		Verbosef: func(format string, args ...any) {
			c.observe(format)
			verbose(format, args...)
		},
		Errorf: errorf,
	}
}

func (c *handshakeClock) observe(format string) {
	switch format {
	case sendingInitiation:
		c.mu.Lock()
		c.sent = c.now()
		c.mu.Unlock()
	case receivedResponse:
		c.mu.Lock()
		if !c.sent.IsZero() {
			c.rtt = c.now().Sub(c.sent)
			c.done = true
			c.sent = time.Time{}
		}
		c.mu.Unlock()
	}
}

// roundTrip is the most recent completed handshake's round trip, if any.
func (c *handshakeClock) roundTrip() (time.Duration, bool) {
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.rtt, c.done
}
