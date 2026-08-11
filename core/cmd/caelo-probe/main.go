// Command caelo-probe brings up a single AmneziaWG tunnel from a `.conf` file
// and makes one HTTP request through it.
//
// It exists to answer the only question that matters early on: does the
// handshake complete and does traffic come back.
package main

import (
	"flag"
	"fmt"
	"os"
	"time"

	"github.com/TeamGDB/Caelo/core/internal/awg"
	"github.com/TeamGDB/Caelo/core/internal/probe"
	"github.com/TeamGDB/Caelo/core/internal/version"
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

	// Parsed twice — once here to describe the tunnel before it is dialled, and
	// once inside the probe. A few microseconds buys the operator a description
	// of what is about to happen even when the handshake never completes.
	cfg, err := awg.ParseConfig(string(raw))
	if err != nil {
		return fmt.Errorf("reading %s: %w", configPath, err)
	}
	describe(cfg)

	result, err := probe.Run(string(raw), probe.Options{
		URL:     target,
		Timeout: timeout,
		Verbose: verbose,
	})
	if err != nil {
		return err
	}

	fmt.Printf("\ncore        %s (amneziawg-go %s)\n", version.Version, version.AmneziaWG())
	fmt.Printf("%s → %s in %s\n", target, result.Status, result.Elapsed.Round(time.Millisecond))
	fmt.Println(result.Body)
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

	shaping := ""
	for _, key := range []string{"jc", "jmin", "jmax", "s1", "s2", "s3", "s4"} {
		if value, ok := cfg.Obfuscation[key]; ok {
			shaping += fmt.Sprintf("%s=%s ", key, value)
		}
	}
	fmt.Printf("obfuscation %s\n", shaping)

	for _, key := range []string{"i1", "i2", "i3", "i4", "i5"} {
		if value, ok := cfg.Obfuscation[key]; ok {
			fmt.Printf("signature   %s (%d bytes of chain)\n", key, len(value))
		}
	}
}
