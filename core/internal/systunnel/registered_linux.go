//go:build linux

package systunnel

const registeredSupported = true

func registeredHandle(string) uint64 { return 0 }
