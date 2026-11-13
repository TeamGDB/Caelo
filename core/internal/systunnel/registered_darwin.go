//go:build darwin

package systunnel

// On macOS the app runs every protocol through its network extension;
// caelo-tun, the only caller of this package there, is a tool for AmneziaWG.
// handleRequired: the platform configures the device by handle, not name.
const handleRequired = false

const registeredSupported = false

func registeredHandle(string) uint64 { return 0 }
