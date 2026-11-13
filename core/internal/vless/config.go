package vless

import (
	"encoding/json"
	"strings"
)

// outboundTag names the one way out. Statistics are read by it.
const outboundTag = "proxy"

// tunTag names the inbound that takes the host's packets.
const tunTag = "tun"

// tunOptions describe the device Xray reads packets from. Absent for a probe,
// which dials through the outbound directly and has no device at all.
type tunOptions struct {
	Name string
	MTU  int
	// Gateway is the device's address range, for the platforms where Xray
	// assigns it itself. Empty where the host already did.
	Gateway []string
}

// options are what the caller adds to what the link says.
type options struct {
	tun *tunOptions
	// address replaces the link's host as what is dialled, keeping the name
	// for SNI and the HTTP Host. Set when the host has been resolved once and
	// a route pinned to that address: dialling the name again could land on
	// another address of a CDN, outside the pinned route and into the tunnel
	// that needs it.
	address string
	// rootCAs are extra certificate authorities, PEM, for tests only. Links
	// cannot carry them: a server that brings its own trust anchor is a
	// server asking to be trusted because it says so.
	rootCAs []string
}

// xrayConfig renders what Xray is to run, in its own JSON format.
//
// JSON rather than Xray's protobuf types: the JSON is Xray's published
// configuration language, which it keeps compatible across releases, and the
// protobuf types are its internals, which it does not. Writing the first is
// what keeps updating Xray a version bump.
func xrayConfig(link *Link, opts options) ([]byte, error) {
	address := link.Host
	if opts.address != "" {
		address = opts.address
	}

	user := map[string]any{
		"address":    address,
		"port":       link.Port,
		"id":         link.UUID,
		"encryption": link.Encryption,
	}
	if link.Flow != "" {
		user["flow"] = link.Flow
	}

	stream := map[string]any{
		"network":  networkName(link.Transport),
		"security": link.Security,
	}

	switch link.Security {
	case SecurityREALITY:
		reality := map[string]any{
			"serverName":  link.SNI,
			"fingerprint": link.Fingerprint,
			"publicKey":   link.PublicKey,
			"shortId":     link.ShortID,
		}
		if link.SpiderX != "" {
			reality["spiderX"] = link.SpiderX
		}
		if link.MLDSA65Verify != "" {
			reality["mldsa65Verify"] = link.MLDSA65Verify
		}
		stream["realitySettings"] = reality

	case SecurityTLS:
		tls := map[string]any{}
		serverName := link.SNI
		if serverName == "" && link.HTTPHost != "" {
			serverName = link.HTTPHost
		}
		if serverName == "" && opts.address != "" {
			// The address was swapped for a resolved one, and the name it
			// replaced is what the certificate is for.
			serverName = link.Host
		}
		if serverName != "" {
			tls["serverName"] = serverName
		}
		if link.Fingerprint != "" {
			tls["fingerprint"] = link.Fingerprint
		}
		if len(link.ALPN) > 0 {
			tls["alpn"] = link.ALPN
		}
		if len(opts.rootCAs) > 0 {
			certificates := make([]map[string]any, 0, len(opts.rootCAs))
			for _, pem := range opts.rootCAs {
				certificates = append(certificates, map[string]any{
					"usage":       "verify",
					"certificate": strings.Split(strings.TrimSpace(pem), "\n"),
				})
			}
			tls["certificates"] = certificates
		}
		stream["tlsSettings"] = tls
	}

	if link.Transport == TransportXHTTP {
		xhttp := map[string]any{"path": link.Path}
		host := link.HTTPHost
		if host == "" && opts.address != "" {
			host = link.Host
		}
		if host != "" {
			xhttp["host"] = host
		}
		if link.Mode != "" {
			xhttp["mode"] = link.Mode
		}
		if len(link.Extra) > 0 {
			xhttp["extra"] = link.Extra
		}
		stream["xhttpSettings"] = xhttp
	}

	config := map[string]any{
		// Xray's own logging is turned off here and redirected into the
		// core's ring instead; see logs.go.
		"log": map[string]any{"loglevel": "none", "access": "none", "error": "none"},
		// Bytes from the server are the evidence that it is still there:
		// what the handshake is for AmneziaWG. Counting them costs an add.
		"stats": map[string]any{},
		"policy": map[string]any{
			"system": map[string]any{
				"statsOutboundDownlink": true,
				"statsOutboundUplink":   true,
			},
		},
		"outbounds": []any{
			map[string]any{
				"tag":            outboundTag,
				"protocol":       "vless",
				"settings":       user,
				"streamSettings": stream,
			},
		},
	}

	if opts.tun != nil {
		settings := map[string]any{"name": opts.tun.Name}
		if opts.tun.MTU > 0 {
			settings["mtu"] = opts.tun.MTU
		}
		if len(opts.tun.Gateway) > 0 {
			settings["gateway"] = opts.tun.Gateway
		}
		config["inbounds"] = []any{
			map[string]any{
				"tag":      tunTag,
				"protocol": "tun",
				"settings": settings,
			},
		}
	}

	return json.Marshal(config)
}

func networkName(transport string) string {
	if transport == TransportTCP {
		return "raw"
	}
	return transport
}
