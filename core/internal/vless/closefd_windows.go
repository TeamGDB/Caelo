//go:build windows

package vless

// Windows hands nobody a descriptor; Attach is never reached there.
func closeFd(int) {}
