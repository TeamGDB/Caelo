//go:build windows

package vless

import "errors"

func newIPv6Guard(int, int) (packetGuard, error) {
	return nil, errors.New("a descriptor guard is unavailable on Windows")
}
