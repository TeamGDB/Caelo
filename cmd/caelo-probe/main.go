// Command caelo-probe brings up a single AmneziaWG tunnel from a `.conf` file
// and makes one HTTP request through it.
//
// It exists to answer the only question that matters early on: does the
// handshake complete and does traffic come back. It runs entirely in userspace
// on a gVisor netstack, so it needs no privileges and creates no interface on
// the host — nothing outside this process is routed through the tunnel.
package main

import (
	"context"
	"flag"
	"fmt"
	"io"
	"net/http"
	"net/netip"
	"os"
	"strings"
	"time"

	"github.com/amnezia-vpn/amneziawg-go/v3/conn"
	"github.com/amnezia-vpn/amneziawg-go/v3/device"
	"github.com/amnezia-vpn/amneziawg-go/v3/tun/netstack"

	"github.com/TeamGDB/caelo-core/internal/awg"
)

func main() {
	configPath := flag.String("config", "", "path to an AmneziaWG .conf file")
	target := flag.String("url", "https://ifconfig.me/ip", "URL to fetch through the tunnel")
	timeout := flag.Duration("timeout", 30*time.Second, "how long to wait before giving up")
	verbose := flag.Bool("v", false, "log device internals, including handshake progress")
	flag.Parse()

	if *configPath == "" {
		fmt.Fprintln(os.Stderr, "caelo-probe: -config is required")
		flag.Usage()
		os.Exit(2)
	}

	if err := run(*configPath, *target, *timeout, *verbose); err != nil {
		fmt.Fprintf(os.Stderr, "caelo-probe: %v\n", err)
		os.Exit(1)
	}
}

func run(configPath, target string, timeout time.Duration, verbose bool) error {
	raw, err := os.ReadFile(configPath)
	if err != nil {
		return err
	}

	cfg, err := awg.ParseConfig(string(raw))
	if err != nil {
		return fmt.Errorf("reading %s: %w", configPath, err)
	}

	dns := cfg.DNS
	if len(dns) == 0 {
		// Resolution happens inside the tunnel, so a resolver reachable only
		// from there is the point, not a fallback.
		dns = []netip.Addr{netip.MustParseAddr("1.1.1.1")}
	}

	tunnel, tnet, err := netstack.CreateNetTUN(cfg.Addresses, dns, cfg.MTU)
	if err != nil {
		return fmt.Errorf("creating netstack device: %w", err)
	}

	level := device.LogLevelError
	if verbose {
		level = device.LogLevelVerbose
	}
	dev := device.NewDevice(tunnel, conn.NewDefaultBind(), device.NewLogger(level, "caelo "))
	defer dev.Close()

	if err := dev.IpcSet(cfg.IPC()); err != nil {
		return fmt.Errorf("configuring device: %w", err)
	}
	if err := dev.Up(); err != nil {
		return fmt.Errorf("bringing device up: %w", err)
	}

	describe(cfg)

	ctx, cancel := context.WithTimeout(context.Background(), timeout)
	defer cancel()

	client := &http.Client{Transport: &http.Transport{DialContext: tnet.DialContext}}

	request, err := http.NewRequestWithContext(ctx, http.MethodGet, target, nil)
	if err != nil {
		return err
	}

	started := time.Now()
	response, err := client.Do(request)
	if err != nil {
		return fmt.Errorf("fetching %s through the tunnel: %w", target, err)
	}
	defer response.Body.Close()

	body, err := io.ReadAll(io.LimitReader(response.Body, 4096))
	if err != nil {
		return fmt.Errorf("reading response: %w", err)
	}

	fmt.Printf("\n%s → %s in %s\n", target, response.Status, time.Since(started).Round(time.Millisecond))
	fmt.Printf("%s\n", strings.TrimSpace(string(body)))
	return nil
}

// describe prints what the tunnel was told to do, without printing any of the
// key material it was told to do it with.
func describe(cfg *awg.Config) {
	fmt.Printf("endpoint    %s\n", cfg.Peer.Endpoint)
	fmt.Printf("address     %v\n", cfg.Addresses)
	fmt.Printf("mtu         %d\n", cfg.MTU)

	if len(cfg.Obfuscation) == 0 {
		fmt.Println("obfuscation none — plain WireGuard")
		return
	}

	var shaping []string
	for _, key := range []string{"jc", "jmin", "jmax", "s1", "s2", "s3", "s4"} {
		if value, ok := cfg.Obfuscation[key]; ok {
			shaping = append(shaping, fmt.Sprintf("%s=%s", key, value))
		}
	}
	var signatures []string
	for _, key := range []string{"i1", "i2", "i3", "i4", "i5"} {
		if value, ok := cfg.Obfuscation[key]; ok {
			signatures = append(signatures, fmt.Sprintf("%s (%d bytes of chain)", key, len(value)))
		}
	}

	fmt.Printf("obfuscation %s\n", strings.Join(shaping, " "))
	if signatures != nil {
		fmt.Printf("signatures  %s\n", strings.Join(signatures, ", "))
	}
}
