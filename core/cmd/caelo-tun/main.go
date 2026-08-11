//go:build darwin || linux

// Command caelo-tun routes the whole machine through an AmneziaWG tunnel.
//
// Unlike caelo-probe, which keeps its tunnel inside its own process, this
// creates a real interface and takes over the default route, so every
// application's traffic goes through it. That needs root.
//
//	sudo caelo-tun -config tunnel.conf
//
// It restores the machine's routing and DNS when it stops, including on Ctrl-C
// and on SIGTERM. Use -duration while developing: the tunnel tears itself down
// after the given time whatever else happens, so a mistake costs you that long
// and not your network.
//
// This is the hands-on path, and a development tool only. The app ships a
// NetworkExtension, where the system owns the tunnel and nothing runs as root.
package main

import (
	"flag"
	"fmt"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/TeamGDB/Caelo/core/internal/systunnel"
	"github.com/TeamGDB/Caelo/core/internal/version"
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

	controller := systunnel.New(verbose)

	// Registered before Start, so a failure partway through still unwinds.
	defer func() {
		fmt.Println("\nrestoring the machine's routing")
		if err := controller.Stop(); err != nil {
			// Worth shouting about. Someone whose network is broken needs to
			// know what to put back by hand.
			fmt.Fprintf(os.Stderr, "caelo-tun: %v\n", err)
			return
		}
		fmt.Println("restored")
	}()

	status, err := controller.Start(string(raw))
	if err != nil {
		return err
	}

	fmt.Printf("core        %s (amneziawg-go %s)\n", version.Version, version.AmneziaWG())
	fmt.Printf("interface   %s\n", status.Interface)
	fmt.Printf("endpoint    %s\n", status.Endpoint)
	fmt.Printf("protocol    %s\n", status.Protocol)
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
