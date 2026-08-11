// Package system takes over the machine's routing so that every application's
// traffic goes through the tunnel, and puts it back afterwards.
//
// Everything here is reversible and every change is recorded before it is made.
// A tool that reroutes a machine and then fails to restore it has done more
// damage than the censorship it was meant to get around.
//
// Each platform has its own file, because there is no useful abstraction over
// "how this operating system is told where packets go" — only three ways of
// saying it. What they share is the shape: Snapshot before touching anything,
// Apply, and Restore from the snapshot. State is per platform; what has to be
// remembered on macOS is not what has to be remembered on Linux.
package system

// Config describes the tunnel the routes should point at.
//
// Declared once rather than per platform: three copies of the same five fields
// would drift, and the drift would show up as a platform quietly ignoring
// something the others act on.
type Config struct {
	// Interface is the tunnel device: utun4 on macOS, caelo0 on Linux, Caelo
	// on Windows.
	Interface string

	// Handle identifies the device to the platform's own API where a name will
	// not do. On Windows it is the adapter's LUID, which is what every call
	// that configures an adapter takes; elsewhere it is zero and unused.
	Handle uint64

	// Address is the tunnel's own address, without a prefix length.
	Address string

	// MTU for the tunnel interface.
	MTU int

	// EndpointHost is the server's address. Its traffic must keep using the
	// physical route, or the tunnel would carry its own packets.
	EndpointHost string

	// DNS is what to resolve with while the tunnel is up. These must be
	// reachable through it.
	DNS []string
}
