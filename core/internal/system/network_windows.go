//go:build windows

package system

import (
	"fmt"
	"net/netip"

	"golang.org/x/sys/windows"
	"golang.zx2c4.com/wireguard/windows/tunnel/winipcfg"
)

// State is what the machine looked like before we touched it.
//
// Less is remembered here than on the other platforms, because less is changed:
// everything done to the tunnel adapter disappears with the adapter. The one
// change made to something that outlives us is the route pinning the endpoint
// to the physical interface, so that is what has to be undone by hand.
type State struct {
	// DefaultInterface is the adapter carrying the default route.
	DefaultInterface uint64

	// NextHop is the router reached over it. The tunnel's own packets keep
	// using it, or they would be routed into themselves.
	NextHop netip.Addr
}

// Snapshot records which interface currently carries the default route.
//
// Read from the routing table through the IP Helper API rather than by running
// `route print` and reading it back. The commands print in the machine's own
// language, so parsing them works until the first machine that is not in
// English, and then fails in a way nobody can reproduce.
func Snapshot() (*State, error) {
	rows, err := winipcfg.GetIPForwardTable2(windows.AF_INET)
	if err != nil {
		return nil, fmt.Errorf("reading the routing table: %w", err)
	}

	state := &State{}
	best := ^uint32(0)
	for i := range rows {
		row := &rows[i]
		if row.DestinationPrefix.PrefixLength != 0 {
			continue
		}
		// Windows chooses between several defaults by adding the route's metric
		// to its interface's. Comparing route metrics alone would pick the
		// wrong adapter on a machine with both Wi-Fi and Ethernet plugged in.
		ipif, err := row.InterfaceLUID.IPInterface(windows.AF_INET)
		if err != nil {
			continue
		}
		total := row.Metric + ipif.Metric
		if total >= best {
			continue
		}
		best = total
		state.DefaultInterface = uint64(row.InterfaceLUID)
		state.NextHop = row.NextHop.Addr()
	}

	if !state.NextHop.IsValid() {
		return nil, fmt.Errorf("no default route: this machine is not on a network")
	}
	return state, nil
}

// Apply points the machine's traffic at the tunnel.
//
// The default route is replaced with two halves — 0.0.0.0/1 and 128.0.0.0/1 —
// rather than overwritten. They are more specific than the real default route,
// so they win while they exist and leave nothing to reconstruct when they go.
func Apply(state *State, cfg Config) error {
	luid := winipcfg.LUID(cfg.Handle)

	address, err := netip.ParseAddr(cfg.Address)
	if err != nil {
		return fmt.Errorf("the tunnel address %q is not an address: %w", cfg.Address, err)
	}
	endpoint, err := netip.ParseAddr(cfg.EndpointHost)
	if err != nil {
		return fmt.Errorf("the endpoint %q is not an address: %w", cfg.EndpointHost, err)
	}

	// A host address. The peer is reached over the routes below, not by being
	// on the same link, and claiming a subnet here would put addresses on the
	// tunnel that the peer never agreed to route.
	if err := luid.SetIPAddresses([]netip.Prefix{netip.PrefixFrom(address, 32)}); err != nil {
		return fmt.Errorf("addressing the tunnel adapter: %w", err)
	}

	if cfg.MTU > 0 {
		ipif, err := luid.IPInterface(windows.AF_INET)
		if err != nil {
			return fmt.Errorf("reading the adapter's settings: %w", err)
		}
		ipif.NLMTU = uint32(cfg.MTU)
		// A fixed metric of zero, so the halves below are preferred over the
		// physical default even where the two would otherwise tie. Automatic
		// metrics are derived from link speed, and a wired connection would
		// win against a tunnel that has no speed to report.
		ipif.UseAutomaticMetric = false
		ipif.Metric = 0
		if err := ipif.Set(); err != nil {
			return fmt.Errorf("setting MTU and metric: %w", err)
		}
	}

	// The server has to stay reachable the ordinary way. This route goes in
	// first: if the split default landed first, the handshake packets would be
	// sent into the tunnel they are trying to establish.
	physical := winipcfg.LUID(state.DefaultInterface)
	if err := physical.AddRoute(netip.PrefixFrom(endpoint, 32), state.NextHop, 0); err != nil {
		return fmt.Errorf("pinning the endpoint route: %w", err)
	}

	unspecified := netip.IPv4Unspecified()
	for _, half := range []netip.Prefix{
		netip.PrefixFrom(unspecified, 1),
		netip.PrefixFrom(netip.AddrFrom4([4]byte{128, 0, 0, 0}), 1),
	} {
		if err := luid.AddRoute(half, unspecified, 0); err != nil {
			return fmt.Errorf("routing %s into the tunnel: %w", half, err)
		}
	}

	// IPv6 is blocked rather than tunnelled, because this configuration has no
	// v6 address inside the tunnel and v6 traffic would otherwise leave outside
	// it. Failure is not fatal: on a machine with IPv6 switched off there is
	// nothing to leak, and refusing to bring up a working v4 tunnel over that
	// would be the wrong trade.
	v6 := netip.IPv6Unspecified()
	for _, half := range []netip.Prefix{
		netip.PrefixFrom(v6, 1),
		netip.PrefixFrom(netip.AddrFrom16([16]byte{0x80}), 1),
	} {
		_ = luid.AddRoute(half, v6, 0)
	}

	if len(cfg.DNS) > 0 {
		servers := make([]netip.Addr, 0, len(cfg.DNS))
		for _, server := range cfg.DNS {
			addr, err := netip.ParseAddr(server)
			if err != nil {
				return fmt.Errorf("DNS server %q is not an address: %w", server, err)
			}
			servers = append(servers, addr)
		}
		if err := luid.SetDNS(windows.AF_INET, servers, nil); err != nil {
			return fmt.Errorf("setting DNS: %w", err)
		}
	}

	return nil
}

// Restore puts everything back the way Snapshot found it.
//
// It keeps going after a failure and reports everything that went wrong,
// because stopping at the first error would leave the rest of the machine's
// configuration in the state we imposed on it.
func Restore(state *State, cfg Config) error {
	var problems []string
	note := func(what string, err error) {
		if err != nil {
			problems = append(problems, fmt.Sprintf("%s: %v", what, err))
		}
	}

	// The one change made to an adapter that outlives the tunnel. Everything
	// else went onto the tunnel adapter and goes away with it, which is why
	// this is the only thing that must not be skipped.
	if endpoint, err := netip.ParseAddr(cfg.EndpointHost); err == nil {
		physical := winipcfg.LUID(state.DefaultInterface)
		note("removing the endpoint route",
			physical.DeleteRoute(netip.PrefixFrom(endpoint, 32), state.NextHop))
	}

	// Belt and braces. Closing the adapter removes these, but Restore is also
	// called to unwind a failed Apply, where the adapter is still there.
	luid := winipcfg.LUID(cfg.Handle)
	note("clearing the tunnel's DNS", luid.FlushDNS(windows.AF_INET))
	note("clearing the tunnel's routes", luid.FlushRoutes(windows.AF_INET))
	_ = luid.FlushRoutes(windows.AF_INET6)

	if problems != nil {
		return fmt.Errorf("the machine was not fully restored:\n  %s", joinLines(problems))
	}
	return nil
}

func joinLines(lines []string) string {
	out := ""
	for i, line := range lines {
		if i > 0 {
			out += "\n  "
		}
		out += line
	}
	return out
}
