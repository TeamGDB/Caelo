//go:build linux

package main

import (
	"fmt"
	"os"
)

// platformCommand handles the subcommands a service manager needs. systemd
// installs units from a package rather than asking the program to register
// itself, so there are none.
func platformCommand() (bool, error) { return false, nil }

// runManaged reports whether a service manager owns the main goroutine.
// systemd does not: it starts an ordinary process and reads its exit status.
func runManaged(func()) (bool, error) { return false, nil }

func mustBePrivileged() error {
	if os.Geteuid() != 0 {
		return fmt.Errorf("must run as root: this program exists to do what the app may not")
	}
	return nil
}
