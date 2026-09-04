package fdtun

import (
	"errors"
	"testing"

	"github.com/amnezia-vpn/amneziawg-go/v3/tun"
)

// fakeTun — устройство, которое не знает своего MTU. Ровно так ведёт себя
// принятый дескриптор внутри Network Extension: интерфейс создан системой, а мы
// его не настраивали.
type fakeTun struct {
	tun.Device
	mtu int
	err error
}

func (f fakeTun) MTU() (int, error) { return f.mtu, f.err }

// Регрессия, стоившая рабочего подключения к серверу 3.1: ядро брало размер
// довеска к пакету из MTU устройства, при нуле не ограничивало его ничем, и
// пакеты вырастали за размер интерфейса. Снаружи — «подключено, трафика нет».
func TestReportsConfiguredMTU(t *testing.T) {
	for _, c := range []struct {
		name   string
		device fakeTun
		want   int
	}{
		{"устройство не знает MTU", fakeTun{mtu: 0}, 1376},
		{"устройство отвечает ошибкой", fakeTun{err: errors.New("нет такого интерфейса")}, 1376},
		{"устройство знает свой MTU", fakeTun{mtu: 1376}, 1376},
	} {
		t.Run(c.name, func(t *testing.T) {
			got, err := withMTU(c.device, 1376).MTU()
			if err != nil {
				t.Fatalf("MTU вернул ошибку: %v", err)
			}
			if got != c.want {
				t.Fatalf("ядру сообщили MTU %d, а должны были %d", got, c.want)
			}
		})
	}
}

// Выдумывать размер за систему нельзя: конфиг без MTU оставляет устройство
// говорить за себя.
func TestKeepsDeviceWhenNothingConfigured(t *testing.T) {
	device := fakeTun{mtu: 1420}
	if withMTU(device, 0) != tun.Device(device) {
		t.Fatal("при нулевом MTU из конфига устройство должно остаться нетронутым")
	}
}
