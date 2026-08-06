//go:build darwin

// Command caelo-tun routes the whole machine through an AmneziaWG tunnel.
//
// Unlike caelo-probe, which keeps its tunnel inside its own process, this
// creates a real utun interface and takes over the default route, so every
// application's traffic goes through it. That needs root.
//
//	sudo caelo-tun -config tunnel.conf
//
// It restores the machine's routing and DNS when it stops, including on Ctrl-C
// and on SIGTERM. Use -duration while developing: the tunnel tears itself down
// after the given time whatever else happens, so a mistake costs you that long
// and not your network.
//
// This is the development path. What ships is a NetworkExtension, because a
// user-facing application should not ask anyone to type sudo.
package main

import (
	"flag"
	"fmt"
	"net"
	"os"
	"os/signal"
	"strings"
	"syscall"
	"time"

	"github.com/amnezia-vpn/amneziawg-go/v3/conn"
	"github.com/amnezia-vpn/amneziawg-go/v3/device"
	"github.com/amnezia-vpn/amneziawg-go/v3/tun"

	"github.com/TeamGDB/caelo-core/internal/awg"
	"github.com/TeamGDB/caelo-core/internal/system"
	"github.com/TeamGDB/caelo-core/internal/version"
)

func main() {
	configPath := flag.String("config", "", "path to an AmneziaWG .conf file")
	duration := flag.Duration("duration", 0, "tear the tunnel down after this long (0 means run until interrupted)")
	verbose := flag.Bool("v", false, "log device internals, including handshake progress")
	flag.Parse()

	if *configPath == "" {
		fmt.Fprintln(os.Stderr, "caelo-tun: -config is required")
		flag.Usage()
		os.Exit(2)
	}
	if os.Geteuid() != 0 {
		fmt.Fprintln(os.Stderr, "caelo-tun: must run as root — creating a utun interface and changing routes needs it")
		os.Exit(1)
	}

	if err := run(*configPath, *duration, *verbose); err != nil {
		fmt.Fprintf(os.Stderr, "caelo-tun: %v\n", err)
		os.Exit(1)
	}
}

func run(configPath string, duration time.Duration, verbose bool) error {
	raw, err := os.ReadFile(configPath)
	if err != nil {
		return err
	}
	cfg, err := awg.ParseConfig(string(raw))
	if err != nil {
		return fmt.Errorf("reading %s: %w", configPath, err)
	}

	endpointHost, err := endpointAddress(cfg.Peer.Endpoint)
	if err != nil {
		return err
	}

	// Snapshot before anything is touched, so there is always something to
	// restore from even if the very first change fails.
	state, err := system.Snapshot()
	if err != nil {
		return err
	}
	fmt.Printf("was routing via %s on %s (%s)\n",
		state.DefaultGateway, state.DefaultInterface, state.NetworkService)

	tunDevice, err := tun.CreateTUN("utun", cfg.MTU)
	if err != nil {
		return fmt.Errorf("creating a utun interface: %w", err)
	}
	name, err := tunDevice.Name()
	if err != nil {
		tunDevice.Close()
		return fmt.Errorf("naming the utun interface: %w", err)
	}

	level := device.LogLevelError
	if verbose {
		level = device.LogLevelVerbose
	}
	dev := device.NewDevice(tunDevice, conn.NewDefaultBind(), device.NewLogger(level, "caelo "))
	defer dev.Close()

	if err := dev.IpcSet(cfg.IPC()); err != nil {
		return fmt.Errorf("configuring the device: %w", err)
	}
	if err := dev.Up(); err != nil {
		return fmt.Errorf("bringing the device up: %w", err)
	}

	dns := []string{"1.1.1.1"}
	if len(cfg.DNS) > 0 {
		dns = dns[:0]
		for _, addr := range cfg.DNS {
			dns = append(dns, addr.String())
		}
	}

	networkCfg := system.Config{
		Interface:    name,
		Address:      cfg.Addresses[0].String(),
		MTU:          cfg.MTU,
		EndpointHost: endpointHost,
		DNS:          dns,
	}

	// Registered before Apply, not after: a failure halfway through Apply still
	// leaves changes that have to come back out.
	defer func() {
		fmt.Println("\nrestoring the machine's routing")
		if err := system.Restore(state, networkCfg); err != nil {
			// Worth shouting about. Someone whose network is broken needs to
			// know what to put back by hand.
			fmt.Fprintf(os.Stderr, "caelo-tun: %v\n", err)
		} else {
			fmt.Println("restored")
		}
	}()

	if err := system.Apply(state, networkCfg); err != nil {
		return err
	}

	protocol := "AmneziaWG"
	if len(cfg.Obfuscation) == 0 {
		protocol = "WireGuard"
	}
	fmt.Printf("\ncore        %s (amneziawg-go %s)\n", version.Version, version.AmneziaWG())
	fmt.Printf("interface   %s\n", name)
	fmt.Printf("endpoint    %s\n", cfg.Peer.Endpoint)
	fmt.Printf("protocol    %s\n", protocol)
	fmt.Printf("dns         %s\n", strings.Join(dns, ", "))
	fmt.Println("\nthe whole machine is going through the tunnel — press Ctrl-C to stop")

	return waitForStop(duration)
}

// waitForStop blocks until the operator interrupts, or until the safety timer
// fires if one was set.
func waitForStop(duration time.Duration) error {
	stop := make(chan os.Signal, 1)
	signal.Notify(stop, os.Interrupt, syscall.SIGTERM)

	if duration <= 0 {
		<-stop
		return nil
	}

	fmt.Printf("will stop on its own in %s\n", duration)
	select {
	case <-stop:
	case <-time.After(duration):
	}
	return nil
}

// endpointAddress resolves the host part of an endpoint to an address that can
// be pinned to the physical route.
func endpointAddress(endpoint string) (string, error) {
	if endpoint == "" {
		return "", fmt.Errorf("the configuration has no Endpoint")
	}

	host, _, err := net.SplitHostPort(endpoint)
	if err != nil {
		return "", fmt.Errorf("endpoint %q is not host:port: %w", endpoint, err)
	}
	if ip := net.ParseIP(host); ip != nil {
		return host, nil
	}

	// Resolved once, now, while the ordinary resolver still works. Once the
	// tunnel is up, resolution goes through it, and looking the endpoint up
	// then would need the tunnel that needs the endpoint.
	addrs, err := net.LookupHost(host)
	if err != nil {
		return "", fmt.Errorf("resolving endpoint %q: %w", host, err)
	}
	for _, addr := range addrs {
		if ip := net.ParseIP(addr); ip != nil && ip.To4() != nil {
			return addr, nil
		}
	}
	return "", fmt.Errorf("endpoint %q has no IPv4 address", host)
}
