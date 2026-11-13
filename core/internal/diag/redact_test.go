package diag

import (
	"strings"
	"testing"
)

func TestRedactsAVLESSUserID(t *testing.T) {
	line := redact("dialing vless://00000000-0000-4000-8000-0000000000AA@192.0.2.1:443 for user 1b2c3d4e-0000-4000-8000-0000000000aa")
	if strings.Contains(strings.ToLower(line), "0000000000aa") {
		t.Fatalf("user id survived: %s", line)
	}
}

func TestLeavesOrdinaryTextAlone(t *testing.T) {
	line := "probe: fetching https://1.1.1.1/cdn-cgi/trace took 120ms"
	if got := redact(line); got != line {
		t.Fatalf("changed %q to %q", line, got)
	}
}
