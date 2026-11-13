//go:build linux

package systunnel

// handleRequired: the platform configures the device by handle, not name.
const handleRequired = false

const registeredSupported = true

func registeredHandle(string) uint64 { return 0 }
