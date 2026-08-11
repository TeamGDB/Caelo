//go:build darwin

package systunnel

// deviceName is a prefix on macOS: the kernel appends the first free number,
// which is why the controller asks the device what it ended up being called.
const deviceName = "utun"
