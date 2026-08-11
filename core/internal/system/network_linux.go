//go:build linux

package system

import (
	"fmt"
	"net"
	"os"
	"os/exec"
	"strings"
)

// resolvConf is rewritten only when systemd-resolved is not the one answering.
const resolvConf = "/etc/resolv.conf"

// State is what the machine looked like before we touched it.
type State struct {
	// DefaultGateway is the router traffic used before the tunnel. The tunnel's
	// own packets keep using it, or they would be routed into themselves.
	DefaultGateway string

	// DefaultInterface is the physical interface that gateway is reached over.
	DefaultInterface string

	// Resolved records that systemd-resolved is answering, in which case DNS is
	// set per interface and reverted per interface, and /etc/resolv.conf is
	// left alone. Overwriting it under resolved produces a machine that
	// resolves correctly until resolved next rewrites the file, which is a
	// failure that arrives minutes after the change that caused it.
	Resolved bool

	// PreviousResolvConf is the file as it was, kept only when we are the ones
	// rewriting it.
	PreviousResolvConf []byte

	// ResolvConfLink is where /etc/resolv.conf pointed, if it was a symlink.
	// Restoring the contents of a symlink as a regular file would silently
	// detach the machine from whatever manages it.
	ResolvConfLink string
}

func run(name string, args ...string) (string, error) {
	output, err := exec.Command(name, args...).CombinedOutput()
	if err != nil {
		return "", fmt.Errorf("%s %s: %w: %s",
			name, strings.Join(args, " "), err, strings.TrimSpace(string(output)))
	}
	return string(output), nil
}

// Snapshot records the current routing and DNS configuration.
func Snapshot() (*State, error) {
	state := &State{}

	output, err := run("ip", "-4", "route", "show", "default")
	if err != nil {
		return nil, fmt.Errorf("finding the default route: %w", err)
	}

	// "default via 192.168.1.1 dev wlan0 proto dhcp metric 600". More than one
	// line means more than one default; ip lists them by metric, so the first
	// is the one in use.
	for _, line := range strings.Split(output, "\n") {
		fields := strings.Fields(line)
		if len(fields) == 0 || fields[0] != "default" {
			continue
		}
		for i := 0; i+1 < len(fields); i++ {
			switch fields[i] {
			case "via":
				state.DefaultGateway = fields[i+1]
			case "dev":
				state.DefaultInterface = fields[i+1]
			}
		}
		break
	}
	if state.DefaultGateway == "" || state.DefaultInterface == "" {
		return nil, fmt.Errorf("no default route: this machine is not on a network")
	}

	state.Resolved = resolvedIsAnswering()
	if !state.Resolved {
		if target, err := os.Readlink(resolvConf); err == nil {
			state.ResolvConfLink = target
		}
		// Read through the link either way: if writing our own file fails
		// later, this is what goes back.
		if contents, err := os.ReadFile(resolvConf); err == nil {
			state.PreviousResolvConf = contents
		}
	}

	return state, nil
}

// resolvedIsAnswering reports whether systemd-resolved is running and can be
// told about an interface.
//
// Presence of the binary is not enough: resolvectl is installed on machines
// where the service is masked, and there it exits non-zero with a message
// nobody reads.
func resolvedIsAnswering() bool {
	if _, err := exec.LookPath("resolvectl"); err != nil {
		return false
	}
	_, err := run("resolvectl", "status")
	return err == nil
}

// Apply points the machine's traffic at the tunnel.
//
// The default route is replaced with two halves — 0.0.0.0/1 and 128.0.0.0/1 —
// rather than overwritten. They are more specific than the real default route,
// so they win while they exist and leave nothing to reconstruct when they go.
func Apply(state *State, cfg Config) error {
	// A host address rather than a subnet. The peer is reached over the routes
	// below, not by being on the same link, and claiming a /24 here would put
	// addresses on the tunnel that the peer never agreed to route.
	if _, err := run("ip", "address", "add", cfg.Address+"/32", "dev", cfg.Interface); err != nil {
		return fmt.Errorf("addressing %s: %w", cfg.Interface, err)
	}
	if cfg.MTU > 0 {
		if _, err := run("ip", "link", "set", "dev", cfg.Interface, "mtu", fmt.Sprint(cfg.MTU)); err != nil {
			return fmt.Errorf("setting MTU on %s: %w", cfg.Interface, err)
		}
	}
	if _, err := run("ip", "link", "set", "dev", cfg.Interface, "up"); err != nil {
		return fmt.Errorf("bringing %s up: %w", cfg.Interface, err)
	}

	// The server has to stay reachable the ordinary way. This route goes in
	// first: if the split default landed first, the handshake packets would be
	// sent into the tunnel they are trying to establish.
	if _, err := run("ip", "route", "add", cfg.EndpointHost+"/32",
		"via", state.DefaultGateway, "dev", state.DefaultInterface); err != nil {
		return fmt.Errorf("pinning the endpoint route: %w", err)
	}

	for _, half := range defaultHalves {
		if _, err := run("ip", "route", "add", half, "dev", cfg.Interface); err != nil {
			return fmt.Errorf("routing %s into the tunnel: %w", half, err)
		}
	}

	// IPv6 is blocked rather than tunnelled. This configuration has no v6
	// address inside the tunnel, so v6 traffic would leave outside it — and a
	// tunnel that quietly carries half your traffic in the clear is worse than
	// no tunnel, because you would not think to check.
	//
	// Unreachable routes rather than the sysctl: they are as specific as the
	// halves above, so they undo cleanly, and a machine whose IPv6 was already
	// off is not left with a sysctl we set and have to remember not to unset.
	for _, half := range v6Halves {
		// Failure is not fatal. A kernel built without IPv6 refuses these, and
		// on that machine there is nothing to leak.
		_, _ = run("ip", "-6", "route", "add", "unreachable", half)
	}

	if len(cfg.DNS) > 0 {
		if err := applyDNS(state, cfg); err != nil {
			return err
		}
	}

	return nil
}

var (
	defaultHalves = []string{"0.0.0.0/1", "128.0.0.0/1"}
	v6Halves      = []string{"::/1", "8000::/1"}
)

func applyDNS(state *State, cfg Config) error {
	if state.Resolved {
		args := append([]string{"dns", cfg.Interface}, cfg.DNS...)
		if _, err := run("resolvectl", args...); err != nil {
			return fmt.Errorf("setting DNS on %s: %w", cfg.Interface, err)
		}
		// Without a routing domain, resolved sends only names it considers to
		// belong to this interface here, and everything else to the resolver it
		// was using before — which is off-tunnel, and is the leak this exists
		// to prevent. "~." claims every name.
		if _, err := run("resolvectl", "domain", cfg.Interface, "~."); err != nil {
			return fmt.Errorf("claiming DNS for %s: %w", cfg.Interface, err)
		}
		return nil
	}

	var file strings.Builder
	file.WriteString("# Written by Caelo while a tunnel is up.\n")
	file.WriteString("# The previous contents are restored when it comes down.\n")
	for _, server := range cfg.DNS {
		if net.ParseIP(server) == nil {
			return fmt.Errorf("DNS server %q is not an address", server)
		}
		fmt.Fprintf(&file, "nameserver %s\n", server)
	}

	// Replaced rather than written through: /etc/resolv.conf is very often a
	// symlink into a directory owned by something else, and writing through it
	// hands that owner our contents to overwrite at its leisure.
	if state.ResolvConfLink != "" {
		if err := os.Remove(resolvConf); err != nil {
			return fmt.Errorf("replacing %s: %w", resolvConf, err)
		}
	}
	if err := os.WriteFile(resolvConf, []byte(file.String()), 0o644); err != nil {
		return fmt.Errorf("writing %s: %w", resolvConf, err)
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
	attempt := func(what string, name string, args ...string) {
		_, err := run(name, args...)
		note(what, err)
	}

	for _, half := range defaultHalves {
		attempt("removing route "+half, "ip", "route", "del", half, "dev", cfg.Interface)
	}
	attempt("removing the endpoint route", "ip", "route", "del", cfg.EndpointHost+"/32")

	// Symmetrical with Apply: added without complaint, removed without one.
	for _, half := range v6Halves {
		_, _ = run("ip", "-6", "route", "del", "unreachable", half)
	}

	note("restoring DNS", restoreDNS(state, cfg))

	if problems != nil {
		return fmt.Errorf("the machine was not fully restored:\n  %s", strings.Join(problems, "\n  "))
	}
	return nil
}

func restoreDNS(state *State, cfg Config) error {
	if state.Resolved {
		// Reverting the interface is enough, and is what resolved would do
		// itself once the device disappeared. Doing it explicitly means a
		// tunnel that is torn down without the device going away — a failed
		// Apply, unwinding — does not leave the claim on "~." behind.
		if _, err := run("resolvectl", "revert", cfg.Interface); err != nil {
			return err
		}
		return nil
	}

	if state.ResolvConfLink != "" {
		if err := os.Remove(resolvConf); err != nil && !os.IsNotExist(err) {
			return err
		}
		return os.Symlink(state.ResolvConfLink, resolvConf)
	}
	if state.PreviousResolvConf == nil {
		// There was no file before, so leaving ours would invent configuration
		// the machine never had.
		if err := os.Remove(resolvConf); err != nil && !os.IsNotExist(err) {
			return err
		}
		return nil
	}
	return os.WriteFile(resolvConf, state.PreviousResolvConf, 0o644)
}
