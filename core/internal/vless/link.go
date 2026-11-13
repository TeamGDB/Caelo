// Package vless reads VLESS share links and runs them on Xray-core.
//
// A node arrives as a vless:// URI — the form every VLESS subscription already
// serves, one link per node. What the link says is checked here, next to the
// code that dials with it, so that a link this build cannot honour is refused
// with a reason a person can read rather than quietly connected some other
// way: a fingerprint that is not the one asked for, or a transport swapped for
// another, is a connection that looks different on the wire from what the
// server's operator chose, and on a network that filters by shape that is the
// difference between working and not.
//
// Xray-core is an ordinary module dependency. Everything about the protocol —
// REALITY, Vision, XHTTP, uTLS fingerprints, post-quantum key exchange — is
// Xray's; this package only translates a link into Xray's own configuration
// and asks it to run. Upgrading Xray is a version bump (see
// scripts/update-xray.sh), and nothing here re-implements what it does.
package vless

import (
	"encoding/json"
	"errors"
	"fmt"
	"net"
	"net/netip"
	"net/url"
	"strconv"
	"strings"

	utls "github.com/refraction-networking/utls"
	xtls "github.com/xtls/xray-core/transport/internet/tls"
)

// Scheme is how a VLESS node announces itself.
const Scheme = "vless"

// Transports this build carries. TCP is also spelled raw, which is what Xray
// has called it since it stopped being only TCP.
const (
	TransportTCP   = "tcp"
	TransportXHTTP = "xhttp"
)

// Security layers this build carries.
const (
	SecurityREALITY = "reality"
	SecurityTLS     = "tls"
)

// FlowVision is the only flow there is.
const FlowVision = "xtls-rprx-vision"

// Link is one node, as its share link described it.
//
// Every field is what the link said, after checking: nothing is filled in with
// a default that would change how the connection looks, except where the link
// format itself defines one (encryption absent means none).
type Link struct {
	// Name is the fragment, decoded. What the server called the node.
	Name string

	UUID string
	// Host is what to dial: a name or an address, without brackets.
	Host string
	Port int

	Encryption string
	Transport  string
	Security   string
	Flow       string

	// SNI is the server name in the ClientHello.
	SNI string
	// Fingerprint is the uTLS ClientHello to imitate, as named in the link.
	Fingerprint string
	ALPN        []string

	// REALITY.
	PublicKey     string
	ShortID       string
	SpiderX       string
	MLDSA65Verify string

	// XHTTP.
	Path     string
	HTTPHost string
	Mode     string
	// Extra is XHTTP's own JSON block, passed to Xray unread.
	Extra json.RawMessage
}

// Variant names the kind of connection, as capabilities spell it.
func (l *Link) Variant() string {
	switch {
	case l.Transport == TransportTCP && l.Flow == FlowVision:
		return "vless-" + l.Security + "-vision"
	default:
		return "vless-" + l.Security + "-" + l.Transport
	}
}

// Endpoint is host:port, as a host would print it.
func (l *Link) Endpoint() string {
	return net.JoinHostPort(l.Host, strconv.Itoa(l.Port))
}

// Variants are the kinds of VLESS connection this build carries, in the
// spelling a subscription is told them in. Only what has been run end to end
// is listed: declaring a capability is a promise to a server about what it may
// send.
var Variants = []string{
	"vless-reality-vision",
	"vless-reality-xhttp",
	"vless-tls-xhttp",
	"vless-tls-vision",
}

// Claims reports whether text is a VLESS link, without checking it.
func Claims(text string) bool {
	text = strings.TrimSpace(text)
	return len(text) > len(Scheme)+3 && strings.EqualFold(text[:len(Scheme)+3], Scheme+"://")
}

// ErrUnsupported marks a link that is well formed but asks for something this
// build does not do. Distinct from a malformed one: the first is a reason to
// tell a person which part, the second a reason to tell the server.
var ErrUnsupported = errors.New("not supported")

func unsupported(format string, args ...any) error {
	return fmt.Errorf("%s: %w", fmt.Sprintf(format, args...), ErrUnsupported)
}

// Parse reads and checks a vless:// link.
func Parse(text string) (*Link, error) {
	text = strings.TrimSpace(text)
	if !Claims(text) {
		return nil, errors.New("not a vless:// link")
	}

	u, err := url.Parse(text)
	if err != nil {
		// url.Error repeats the whole input, and the input carries the UUID.
		return nil, errors.New("the link is not a valid URI")
	}

	link := &Link{Name: u.Fragment}

	if u.User == nil || u.User.Username() == "" {
		return nil, errors.New("the link has no user id")
	}
	link.UUID = u.User.Username()
	if _, hasPassword := u.User.Password(); hasPassword {
		return nil, errors.New("the user id contains a colon")
	}
	if !validUUID(link.UUID) {
		// Xray also accepts any string of up to 30 bytes and derives a UUID
		// from it. Servers do not hand those out in links, and a link whose
		// id is not a UUID is far more likely broken than clever.
		return nil, errors.New("the user id is not a UUID")
	}

	link.Host = u.Hostname()
	if link.Host == "" {
		return nil, errors.New("the link has no server address")
	}
	if strings.HasPrefix(u.Host, "[") {
		if _, err := netip.ParseAddr(link.Host); err != nil {
			return nil, errors.New("the server address in brackets is not an IPv6 address")
		}
	}
	portText := u.Port()
	if portText == "" {
		return nil, errors.New("the link has no port")
	}
	port, err := strconv.Atoi(portText)
	if err != nil || port < 1 || port > 65535 {
		return nil, fmt.Errorf("port %q is out of range", portText)
	}
	link.Port = port

	// Every value a link carries is percent-encoded, and url.Values decodes
	// once, as the format intends. A parameter given twice is a link written
	// by something confused; the first is taken, as every other client does.
	query := u.Query()
	get := func(key string) string { return strings.TrimSpace(query.Get(key)) }

	link.Encryption = get("encryption")
	if link.Encryption == "" {
		link.Encryption = "none"
	}

	switch transport := strings.ToLower(get("type")); transport {
	case "", "tcp", "raw":
		link.Transport = TransportTCP
	case "xhttp", "splithttp":
		link.Transport = TransportXHTTP
	default:
		return nil, unsupported("transport %q", transport)
	}

	switch security := strings.ToLower(get("security")); security {
	case SecurityREALITY, SecurityTLS:
		link.Security = security
	case "", "none":
		// Plain VLESS is readable by anyone on the path, which is the thing
		// this client exists to avoid.
		return nil, unsupported("a connection without TLS or REALITY")
	default:
		return nil, unsupported("security %q", security)
	}

	switch flow := get("flow"); flow {
	case "":
	case FlowVision, FlowVision + "-udp443":
		if link.Transport != TransportTCP {
			return nil, unsupported("Vision over %s; it runs only over TCP", link.Transport)
		}
		link.Flow = flow
	default:
		return nil, unsupported("flow %q", flow)
	}

	if header := strings.ToLower(get("headerType")); header != "" && header != "none" {
		// HTTP header camouflage is a different shape of connection; quietly
		// dropping it would send something the server is not expecting.
		return nil, unsupported("TCP header type %q", header)
	}

	link.SNI = get("sni")
	if link.SNI == "" {
		link.SNI = get("peer") // what some older links call it
	}

	link.Fingerprint = strings.ToLower(get("fp"))
	if link.Fingerprint != "" && !knownFingerprint(link.Fingerprint) {
		// Asked of Xray rather than listed here, so that a fingerprint a new
		// Xray learns is one this client accepts without being edited.
		return nil, unsupported("fingerprint %q", link.Fingerprint)
	}

	if alpn := get("alpn"); alpn != "" {
		for _, protocol := range strings.Split(alpn, ",") {
			if protocol = strings.TrimSpace(protocol); protocol != "" {
				link.ALPN = append(link.ALPN, protocol)
			}
		}
	}

	switch link.Security {
	case SecurityREALITY:
		link.PublicKey = get("pbk")
		link.ShortID = get("sid")
		link.SpiderX = get("spx")
		link.MLDSA65Verify = get("pqv")
		if link.PublicKey == "" {
			return nil, errors.New("a REALITY link has no public key (pbk)")
		}
		if link.SNI == "" {
			return nil, errors.New("a REALITY link has no server name (sni)")
		}
		if !hexString(link.ShortID) || len(link.ShortID) > 16 {
			return nil, fmt.Errorf("short id %q is not up to 16 hex digits", link.ShortID)
		}
		if link.Fingerprint == "" {
			// REALITY has no ClientHello of its own; Xray refuses to start
			// without one. Chrome is what Xray's own share links default to.
			link.Fingerprint = "chrome"
		}
	case SecurityTLS:
		if get("allowInsecure") == "1" || strings.EqualFold(get("allowInsecure"), "true") || get("insecure") == "1" {
			// A certificate that is not checked is a server that is not
			// known. Someone in the middle is exactly who this is for.
			return nil, unsupported("turning certificate checks off")
		}
	}

	if link.Transport == TransportXHTTP {
		link.Path = get("path")
		if link.Path == "" {
			link.Path = "/"
		}
		if !strings.HasPrefix(link.Path, "/") {
			return nil, fmt.Errorf("XHTTP path %q does not start with /", link.Path)
		}
		link.HTTPHost = get("host")
		link.Mode = get("mode")
		switch link.Mode {
		case "", "auto", "packet-up", "stream-up", "stream-one":
		default:
			return nil, unsupported("XHTTP mode %q", link.Mode)
		}
		if extra := get("extra"); extra != "" {
			if !json.Valid([]byte(extra)) {
				return nil, errors.New("XHTTP extra is not JSON")
			}
			link.Extra = json.RawMessage(extra)
		}
	}

	return link, nil
}

// knownFingerprint asks Xray's own tables. Some of their entries are nil until
// Xray picks one at startup (random), so presence is what counts, not value.
func knownFingerprint(name string) bool {
	for _, table := range []map[string]*utls.ClientHelloID{
		xtls.PresetFingerprints, xtls.ModernFingerprints, xtls.OtherFingerprints,
	} {
		if _, ok := table[name]; ok {
			return true
		}
	}
	return false
}

func validUUID(s string) bool {
	if len(s) != 36 {
		return false
	}
	for i, r := range s {
		switch i {
		case 8, 13, 18, 23:
			if r != '-' {
				return false
			}
		default:
			if !isHex(r) {
				return false
			}
		}
	}
	return true
}

func hexString(s string) bool {
	for _, r := range s {
		if !isHex(r) {
			return false
		}
	}
	return true
}

func isHex(r rune) bool {
	return (r >= '0' && r <= '9') || (r >= 'a' && r <= 'f') || (r >= 'A' && r <= 'F')
}
