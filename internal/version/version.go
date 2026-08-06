// Package version reports what this build of the core is.
package version

import "runtime/debug"

// Version is the core's own version, set at build time with
// -ldflags "-X github.com/TeamGDB/caelo-core/internal/version.Version=..."
var Version = "dev"

// AmneziaWG is the amneziawg-go release this core was built against. It is read
// from the build info rather than written down, so it cannot drift away from
// what is actually linked in.
func AmneziaWG() string {
	info, ok := debug.ReadBuildInfo()
	if !ok {
		return "unknown"
	}
	for _, dep := range info.Deps {
		if dep.Path == "github.com/amnezia-vpn/amneziawg-go/v3" {
			return dep.Version
		}
	}
	return "unknown"
}
