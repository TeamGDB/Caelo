package vless

import (
	"bytes"
	"context"
	"crypto/tls"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"sync"
	"sync/atomic"
	"time"

	xnet "github.com/xtls/xray-core/common/net"
	"github.com/xtls/xray-core/core"
	"github.com/xtls/xray-core/features/stats"
	"github.com/xtls/xray-core/infra/conf/serial"

	// What the configurations rendered in config.go use, and nothing else.
	// The JSON loader above already pulls in the configuration types of
	// everything Xray has; these register the parts that run.
	_ "github.com/xtls/xray-core/app/dispatcher"
	_ "github.com/xtls/xray-core/app/log"
	_ "github.com/xtls/xray-core/app/policy"
	_ "github.com/xtls/xray-core/app/proxyman/inbound"
	_ "github.com/xtls/xray-core/app/proxyman/outbound"
	_ "github.com/xtls/xray-core/app/stats"
	_ "github.com/xtls/xray-core/proxy/tun"
	_ "github.com/xtls/xray-core/proxy/vless/outbound"
	_ "github.com/xtls/xray-core/transport/internet/reality"
	_ "github.com/xtls/xray-core/transport/internet/splithttp"
	_ "github.com/xtls/xray-core/transport/internet/tagged/taggedimpl"
	_ "github.com/xtls/xray-core/transport/internet/tcp"
	_ "github.com/xtls/xray-core/transport/internet/tls"

	"github.com/TeamGDB/Caelo/core/internal/diag"
)

// instance is one running Xray with the one outbound a link describes.
type instance struct {
	xray *core.Instance

	downlink stats.Counter

	// alive is when bytes last came back from the server, as Unix
	// nanoseconds. Zero until they have.
	alive atomic.Int64
	seen  atomic.Int64
	// proved is when a proof was last started, as Unix nanoseconds.
	proved atomic.Int64

	stop     chan struct{}
	stopOnce sync.Once
}

// start renders the link and runs it.
func start(link *Link, opts options) (*instance, error) {
	rendered, err := xrayConfig(link, opts)
	if err != nil {
		return nil, fmt.Errorf("rendering the configuration: %w", err)
	}
	config, err := serial.LoadJSONConfig(bytes.NewReader(rendered))
	if err != nil {
		return nil, fmt.Errorf("Xray refused the configuration: %w", scrub(err, link))
	}

	xray, err := core.New(config)
	if err != nil {
		return nil, fmt.Errorf("Xray could not be set up: %w", scrub(err, link))
	}
	// After New, which is where Xray's log app installs its own handler, and
	// for every instance, since each one does.
	installLogHandler()
	if err := xray.Start(); err != nil {
		xray.Close()
		return nil, fmt.Errorf("Xray could not start: %w", scrub(err, link))
	}

	in := &instance{xray: xray, stop: make(chan struct{})}
	if manager, ok := xray.GetFeature(stats.ManagerType()).(stats.Manager); ok {
		in.downlink = manager.GetCounter("outbound>>>" + outboundTag + ">>>traffic>>>downlink")
	}
	go in.watch()
	return in, nil
}

// watch turns the downlink counter into "the server last answered at".
//
// Polled, because Xray counts and does not tell. Twice a second is often
// enough for a figure that is read every twenty, and an add and a compare
// cost nothing.
func (in *instance) watch() {
	if in.downlink == nil {
		return
	}
	ticker := time.NewTicker(500 * time.Millisecond)
	defer ticker.Stop()
	for {
		select {
		case <-in.stop:
			return
		case <-ticker.C:
			if n := in.downlink.Value(); n != in.seen.Load() {
				in.seen.Store(n)
				in.alive.Store(time.Now().UnixNano())
			}
		}
	}
}

// A server that has been quiet this long is asked whether it is still there
// the next time anyone wants to know, and asked at most this often.
const (
	quietFor   = 90 * time.Second
	proveEvery = 60 * time.Second
)

// LastAlive is when bytes last came back from the server; zero if never.
//
// A tunnel nobody is using receives nothing, and silence from a proxy is not
// evidence of anything — unlike a WireGuard peer, which handshakes every two
// minutes whether or not there is traffic. So when the answer would be old,
// one request goes out through the server in the background and the next
// reading has a fresh one. Only when asked: the watchdog asks while
// connected, and a tunnel nobody watches sends nothing of its own.
func (in *instance) LastAlive() time.Time {
	at := in.alive.Load()
	if at == 0 {
		return time.Time{}
	}
	if time.Since(time.Unix(0, at)) >= quietFor {
		in.proveSoon()
	}
	return time.Unix(0, at)
}

func (in *instance) proveSoon() {
	now := time.Now().UnixNano()
	last := in.proved.Load()
	if now-last < int64(proveEvery) || !in.proved.CompareAndSwap(last, now) {
		return
	}
	go func() {
		ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
		defer cancel()
		if err := in.prove(ctx); err != nil {
			diag.Logf("vless: the server did not answer while the tunnel was quiet")
		}
	}()
}

// Dial opens a TCP connection to address through the server.
//
// The connection to the server itself is made when the first byte is
// written: that is how Xray's dispatcher works, and it is why a successful
// Dial proves nothing. Only an answer does.
func (in *instance) Dial(ctx context.Context, network, address string) (net.Conn, error) {
	if network != "tcp" && network != "tcp4" && network != "tcp6" {
		return nil, fmt.Errorf("network %q is not dialled through the server", network)
	}
	destination, err := xnet.ParseDestination("tcp:" + address)
	if err != nil {
		return nil, err
	}
	return core.Dial(ctx, in.xray, destination)
}

// Close stops Xray. Idempotent.
func (in *instance) Close() {
	in.stopOnce.Do(func() {
		close(in.stop)
		in.xray.Close()
	})
}

// checkURL is fetched through the server to prove it carries traffic, when
// nothing else has. An address rather than a name so that nothing has to be
// resolved to ask, and HTTPS because a plain HTTP answer can be forged by
// anyone on the path, which is the network in question.
const checkURL = "https://1.1.1.1/cdn-cgi/trace"

// prove fetches checkURL through the server.
func (in *instance) prove(ctx context.Context) error {
	client := &http.Client{
		Transport: &http.Transport{
			DialContext:       in.Dial,
			TLSClientConfig:   &tls.Config{MinVersion: tls.VersionTLS12},
			DisableKeepAlives: true,
		},
	}
	request, err := http.NewRequestWithContext(ctx, http.MethodGet, checkURL, nil)
	if err != nil {
		return err
	}
	response, err := client.Do(request)
	if err != nil {
		return errors.New("the server did not carry a request")
	}
	_, _ = io.Copy(io.Discard, io.LimitReader(response.Body, 4096))
	response.Body.Close()
	in.alive.Store(time.Now().UnixNano())
	return nil
}

// WaitAlive returns once the server has carried traffic, or false after
// timeout.
//
// A REALITY or TLS server answers its handshake before it has checked who is
// asking, and Xray reports a connection open before the first byte is sent,
// so neither says the node works. A request that came back does.
func (in *instance) WaitAlive(timeout time.Duration) bool {
	ctx, cancel := context.WithTimeout(context.Background(), timeout)
	defer cancel()
	if err := in.prove(ctx); err != nil {
		diag.Logf("vless: %v", err)
		return false
	}
	return true
}

// scrub keeps the user id out of an error, which is shown to people and
// lands in logs. Xray's own errors sometimes quote the configuration back.
func scrub(err error, link *Link) error {
	if err == nil || link == nil || link.UUID == "" {
		return err
	}
	message := err.Error()
	if !bytes.Contains([]byte(message), []byte(link.UUID)) {
		return err
	}
	return errors.New(string(bytes.ReplaceAll([]byte(message), []byte(link.UUID), []byte("<redacted>"))))
}
