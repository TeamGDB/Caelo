package vless

import (
	"encoding/binary"
	"net"

	"golang.org/x/net/icmp"
	"golang.org/x/net/ipv6"
)

// rejectIPv6 отвечает до TCP SYN-ACK: отказ после принятия TCP-соединения
// уже не заставляет браузер выбрать IPv4. Пакет остаётся внутри VPN.
func rejectIPv6(packet []byte) []byte {
	if len(packet) < 40 || packet[0]>>4 != 6 {
		return nil
	}
	length := 40 + int(binary.BigEndian.Uint16(packet[4:6]))
	if length > len(packet) {
		return nil
	}
	packet = packet[:length]
	source, dest := net.IP(packet[8:24]), net.IP(packet[24:40])
	if source.IsUnspecified() || source.IsMulticast() || dest.IsMulticast() {
		return nil
	}
	next, offset := packet[6], 40
	for steps := 0; steps < 8; steps++ {
		switch next {
		case 0, 43, 60:
			if offset+2 > len(packet) {
				return nil
			}
			size := (int(packet[offset+1]) + 1) * 8
			if offset+size > len(packet) {
				return nil
			}
			next = packet[offset]
			offset += size
		case 44:
			if offset+8 > len(packet) || binary.BigEndian.Uint16(packet[offset+2:offset+4])&0xfff8 != 0 {
				return nil
			}
			next = packet[offset]
			offset += 8
		case 51:
			if offset+2 > len(packet) {
				return nil
			}
			size := (int(packet[offset+1]) + 2) * 4
			if offset+size > len(packet) {
				return nil
			}
			next = packet[offset]
			offset += size
		default:
			if next == 58 && (offset >= len(packet) || packet[offset] < 128) {
				return nil
			}
			// RFC 4443: ошибка с цитатой должна помещаться в минимальный MTU IPv6.
			quote := packet
			if len(quote) > 1232 {
				quote = quote[:1232]
			}
			message := icmp.Message{Type: ipv6.ICMPTypeDestinationUnreachable, Code: 0, Body: &icmp.DstUnreach{Data: quote}}
			body, err := message.Marshal(icmp.IPv6PseudoHeader(dest, source))
			if err != nil {
				return nil
			}
			reply := make([]byte, 40+len(body))
			reply[0] = 0x60
			binary.BigEndian.PutUint16(reply[4:6], uint16(len(body)))
			reply[6] = 58
			reply[7] = 64
			copy(reply[8:24], dest)
			copy(reply[24:40], source)
			copy(reply[40:], body)
			return reply
		}
	}
	return nil
}
