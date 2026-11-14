package vless

import (
	"context"
	"crypto/tls"
	"crypto/x509"
	"net"
	"net/netip"
	"runtime"
	"runtime/debug"
	"time"

	"github.com/TeamGDB/Caelo/core/internal/diag"
	"github.com/TeamGDB/Caelo/core/internal/protocol"
)

const ipv6ProbeTimeout = 3 * time.Second

type ipv6Target struct{ address, serverName string }

// IPv6-адрес задаётся явно: DNS-имя могло бы незаметно проверить IPv4.
// Два независимых сервиса, достаточно ответа любого. Передаются только TLS-
// рукопожатия через выбранный прокси, без запросов через физический интерфейс.
var ipv6Targets = []ipv6Target{
	{"[2606:4700:4700::1111]:443", "one.one.one.one"},
	{"[2001:4860:4860::8888]:443", "dns.google"},
}

func (c *config) Prepare(ctx context.Context) (protocol.Config, error) {
	if runtime.GOOS == "ios" {
		debug.SetMemoryLimit(iosMemoryLimit)
	}
	return c.prepareIPv6(ctx, ipv6Targets, nil, options{address: c.address})
}

func (c *config) prepareIPv6(ctx context.Context, targets []ipv6Target, roots *x509.CertPool, opts options) (protocol.Config, error) {
	parent := ctx
	in, err := start(c.link, opts)
	if err != nil {
		return nil, err
	}
	defer in.Close()
	ctx, cancel := context.WithTimeout(ctx, ipv6ProbeTimeout)
	defer cancel()
	prepared := *c
	prepared.ipv6Available = ipv6Reachable(ctx, in.Dial, targets, roots)
	if parent.Err() == context.Canceled {
		return nil, context.Canceled
	}
	prepared.ipv6Checked = true
	diag.Logf("vless: IPv6 exit available: %t", prepared.ipv6Available)
	return &prepared, nil
}

type ipv6Dial func(context.Context, string, string) (net.Conn, error)

func ipv6Reachable(ctx context.Context, dial ipv6Dial, targets []ipv6Target, roots *x509.CertPool) bool {
	ctx, cancel := context.WithCancel(ctx)
	defer cancel()
	results := make(chan bool, len(targets))
	for _, target := range targets {
		go func() { results <- checkIPv6Target(ctx, dial, target, roots) }()
	}
	available := false
	for range targets {
		if <-results {
			available = true
			cancel()
		}
	}
	return available
}

func checkIPv6Target(ctx context.Context, dial ipv6Dial, target ipv6Target, roots *x509.CertPool) bool {
	addr, err := netip.ParseAddrPort(target.address)
	if err != nil || !addr.Addr().Is6() || addr.Addr().Is4In6() || target.serverName == "" {
		return false
	}
	conn, err := dial(ctx, "tcp6", target.address)
	if err != nil {
		return false
	}
	defer conn.Close()
	stop := context.AfterFunc(ctx, func() { _ = conn.Close() })
	defer stop()
	if deadline, ok := ctx.Deadline(); ok {
		_ = conn.SetDeadline(deadline)
	}
	secured := tls.Client(conn, &tls.Config{ServerName: target.serverName, RootCAs: roots, MinVersion: tls.VersionTLS12})
	err = secured.HandshakeContext(ctx)
	if err != nil {
		diag.Logf("vless: IPv6 proof did not complete: %v", err)
	}
	return err == nil
}
