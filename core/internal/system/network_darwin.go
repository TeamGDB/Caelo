//go:build darwin

// Package system takes over the machine's routing so that every application's
// traffic goes through the tunnel, and puts it back afterwards.
//
// Everything here is reversible and every change is recorded before it is made.
// A tool that reroutes a machine and then fails to restore it has done more
// damage than the censorship it was meant to get around.
package system

import (
	"fmt"
	"net"
	"os/exec"
	"strings"
)

// State is what the machine looked like before we touched it.
type State struct {
	// DefaultGateway is the router traffic used before the tunnel. The tunnel's
	// own packets keep using it, or they would be routed into themselves.
	DefaultGateway string

	// DefaultInterface is the physical interface that gateway is reached over.
	DefaultInterface string

	// NetworkService is the name macOS uses for that interface in Network
	// settings, which is what the DNS and IPv6 commands take.
	NetworkService string

	// PreviousDNS is what the service was resolving with. Empty means it was
	// taking whatever DHCP offered.
	PreviousDNS []string

	// IPv6WasEnabled records whether we have to switch IPv6 back on.
	IPv6WasEnabled bool
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

	output, err := run("route", "-n", "get", "default")
	if err != nil {
		return nil, fmt.Errorf("finding the default route: %w", err)
	}
	for _, line := range strings.Split(output, "\n") {
		key, value, found := strings.Cut(strings.TrimSpace(line), ":")
		if !found {
			continue
		}
		switch strings.TrimSpace(key) {
		case "gateway":
			state.DefaultGateway = strings.TrimSpace(value)
		case "interface":
			state.DefaultInterface = strings.TrimSpace(value)
		}
	}
	if state.DefaultGateway == "" || state.DefaultInterface == "" {
		return nil, fmt.Errorf("no default route: this machine is not on a network")
	}

	state.NetworkService, err = serviceForInterface(state.DefaultInterface)
	if err != nil {
		return nil, err
	}

	if dns, err := run("networksetup", "-getdnsservers", state.NetworkService); err == nil {
		for _, line := range strings.Fields(dns) {
			if net.ParseIP(line) != nil {
				state.PreviousDNS = append(state.PreviousDNS, line)
			}
		}
	}

	if info, err := run("networksetup", "-getinfo", state.NetworkService); err == nil {
		state.IPv6WasEnabled = !strings.Contains(info, "IPv6: Off")
	}

	return state, nil
}

// serviceForInterface maps a BSD device name such as en0 onto the service name
// shown in Network settings, which is what networksetup wants.
func serviceForInterface(device string) (string, error) {
	output, err := run("networksetup", "-listnetworkserviceorder")
	if err != nil {
		return "", err
	}

	// Entries look like:
	//   (1) Wi-Fi
	//   (Hardware Port: Wi-Fi, Device: en0)
	var current string
	for _, line := range strings.Split(output, "\n") {
		line = strings.TrimSpace(line)
		if strings.HasPrefix(line, "(") && strings.Contains(line, ") ") {
			_, name, _ := strings.Cut(line, ") ")
			current = strings.TrimSpace(name)
			continue
		}
		if strings.Contains(line, "Device: "+device+")") {
			return current, nil
		}
	}
	return "", fmt.Errorf("no network service uses %s", device)
}

// Config describes the tunnel the routes should point at.
type Config struct {
	// Interface is the utun device, e.g. "utun4".
	Interface string

	// Address is the tunnel's own address.
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

// Apply points the machine's traffic at the tunnel.
//
// The default route is replaced with two halves — 0.0.0.0/1 and 128.0.0.0/1 —
// rather than overwritten. They are more specific than the real default route,
// so they win while they exist and leave nothing to reconstruct when they go.
func Apply(state *State, cfg Config) error {
	if _, err := run("ifconfig", cfg.Interface, "inet",
		cfg.Address, cfg.Address, "netmask", "255.255.255.255", "up"); err != nil {
		return fmt.Errorf("configuring %s: %w", cfg.Interface, err)
	}
	if cfg.MTU > 0 {
		if _, err := run("ifconfig", cfg.Interface, "mtu", fmt.Sprint(cfg.MTU)); err != nil {
			return fmt.Errorf("setting MTU on %s: %w", cfg.Interface, err)
		}
	}

	// The server has to stay reachable the ordinary way. This route goes in
	// first: if the split default landed first, the handshake packets would be
	// sent into the tunnel they are trying to establish.
	if _, err := run("route", "-n", "add", "-host", cfg.EndpointHost, state.DefaultGateway); err != nil {
		return fmt.Errorf("pinning the endpoint route: %w", err)
	}

	for _, half := range []string{"0.0.0.0/1", "128.0.0.0/1"} {
		if _, err := run("route", "-n", "add", "-net", half, "-interface", cfg.Interface); err != nil {
			return fmt.Errorf("routing %s into the tunnel: %w", half, err)
		}
	}

	// IPv6 is switched off rather than tunnelled. This configuration has no v6
	// address inside the tunnel, so v6 traffic would leave outside it — and a
	// tunnel that quietly leaks half your traffic is worse than no tunnel,
	// because you would not think to check.
	if state.IPv6WasEnabled {
		if _, err := run("networksetup", "-setv6off", state.NetworkService); err != nil {
			return fmt.Errorf("disabling IPv6: %w", err)
		}
	}

	if len(cfg.DNS) > 0 {
		args := append([]string{"-setdnsservers", state.NetworkService}, cfg.DNS...)
		if _, err := run("networksetup", args...); err != nil {
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
	attempt := func(what string, name string, args ...string) {
		if _, err := run(name, args...); err != nil {
			problems = append(problems, fmt.Sprintf("%s: %v", what, err))
		}
	}

	for _, half := range []string{"0.0.0.0/1", "128.0.0.0/1"} {
		attempt("removing route "+half, "route", "-n", "delete", "-net", half, "-interface", cfg.Interface)
	}
	attempt("removing the endpoint route", "route", "-n", "delete", "-host", cfg.EndpointHost)

	if len(state.PreviousDNS) > 0 {
		args := append([]string{"-setdnsservers", state.NetworkService}, state.PreviousDNS...)
		attempt("restoring DNS", "networksetup", args...)
	} else {
		// "Empty" is how networksetup spells "go back to DHCP".
		attempt("clearing DNS", "networksetup", "-setdnsservers", state.NetworkService, "Empty")
	}

	if state.IPv6WasEnabled {
		attempt("re-enabling IPv6", "networksetup", "-setv6automatic", state.NetworkService)
	}

	if problems != nil {
		return fmt.Errorf("the machine was not fully restored:\n  %s", strings.Join(problems, "\n  "))
	}
	return nil
}
