// Package rtttest gives a Meter something to measure, for tests of what
// carries its figure. Only tests import it.
package rtttest

import (
	"encoding/binary"

	"github.com/TeamGDB/Caelo/core/internal/rtt"
)

// Connect shows meter one TCP connection opening: a SYN out and its SYN-ACK
// straight back. The figure it leaves is a millisecond or so, never none.
func Connect(meter *rtt.Meter) {
	meter.Outbound(packet([4]byte{10, 8, 1, 2}, [4]byte{1, 1, 1, 1}, 50000, 443, 0x02, 1000, 0))
	meter.Inbound(packet([4]byte{1, 1, 1, 1}, [4]byte{10, 8, 1, 2}, 443, 50000, 0x12, 9000, 1001))
}

func packet(src, dst [4]byte, sport, dport uint16, flags byte, seq, ack uint32) []byte {
	p := make([]byte, 40)
	p[0] = 0x45
	binary.BigEndian.PutUint16(p[2:4], 40)
	p[9] = 6
	copy(p[12:16], src[:])
	copy(p[16:20], dst[:])
	binary.BigEndian.PutUint16(p[20:22], sport)
	binary.BigEndian.PutUint16(p[22:24], dport)
	binary.BigEndian.PutUint32(p[24:28], seq)
	binary.BigEndian.PutUint32(p[28:32], ack)
	p[32] = 5 << 4
	p[33] = flags
	return p
}
