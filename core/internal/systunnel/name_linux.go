//go:build linux

package systunnel

// deviceName is taken literally on Linux. Named for the application rather than
// given a tun0 that anything else on the machine might also have chosen.
const deviceName = "caelo0"
