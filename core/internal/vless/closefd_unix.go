//go:build !windows

package vless

import "golang.org/x/sys/unix"

func closeFd(fd int) { _ = unix.Close(fd) }
