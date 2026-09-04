package fdtun

import (
	"github.com/amnezia-vpn/amneziawg-go/v3/tun"

	"github.com/TeamGDB/Caelo/core/internal/diag"
)

// statedMTU оборачивает принятое устройство и отвечает тем MTU, который задан
// конфигурацией.
//
// Само устройство мы не трогаем: выставлять MTU интерфейса нам нельзя — на
// Apple это делает Network Extension, и попытка сделать это ioctl'ом проваливает
// приём дескриптора целиком. Но *сообщить* ядру размер обязаны, и вот почему.
//
// В AmneziaWG 3.1 появилось ContentPaddingAddition: к каждому пакету данных
// добавляется случайный довесок, и ограничивается он размером, который отдаёт
// сам TUN:
//
//	mtu := int(device.tun.mtu.Load())
//	paddingSize := device.randomPaddingAddition(packetSize, mtu)
//
// а внутри — `if mtu != 0 { ... }`. То есть при нулевом MTU ограничения нет
// вовсе: пакет вырастает за размер интерфейса и теряется по дороге. Снаружи это
// выглядит как «подключено, а трафика нет» — рукопожатие проходит, потому что
// оно не padding'уется, а данные не доходят. На серверах 2.x довеска нет, и
// потому они работали.
type statedMTU struct {
	tun.Device
	mtu int
}

func (s statedMTU) MTU() (int, error) { return s.mtu, nil }

// withMTU возвращает устройство, которое сообщает заданный MTU.
//
// Нулевой или отрицательный не подставляется: выдумывать размер за систему
// хуже, чем оставить как есть, — а «как есть» это то, что вернёт само
// устройство.
func withMTU(device tun.Device, mtu int) tun.Device {
	if mtu <= 0 {
		return device
	}
	if actual, err := device.MTU(); err != nil || actual != mtu {
		diag.Logf("tun reports MTU %d (%v); telling the device %d from the configuration", actual, err, mtu)
	}
	return statedMTU{Device: device, mtu: mtu}
}
