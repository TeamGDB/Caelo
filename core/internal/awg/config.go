// Package awg translates AmneziaWG configuration into the form the device
// layer expects.
package awg

import (
	"encoding/base64"
	"encoding/hex"
	"fmt"
	"net/netip"
	"strconv"
	"strings"
)

// Config is an AmneziaWG tunnel as described by a `.conf` file.
//
// Only the fields Caelo actually uses are modelled. Obfuscation parameters are
// kept as the strings they arrived as: the device layer parses `H1` ranges and
// `I1` packet chains itself, and re-deriving that grammar here would only
// create a second implementation to disagree with.
type Config struct {
	PrivateKey string
	Addresses  []netip.Addr
	MTU        int
	DNS        []netip.Addr

	Obfuscation map[string]string

	Peer Peer
}

// Peer is the far end. AmneziaWG configs describe exactly one.
type Peer struct {
	PublicKey    string
	PresharedKey string
	Endpoint     string
	AllowedIPs   []string
	Keepalive    int
}

// obfuscationKeys are the interface-level parameters that shape traffic:
// junk packet counts and sizes, header magic ranges, and the signature packets
// that make a handshake look like something else. They are passed through
// untouched.
var obfuscationKeys = map[string]bool{
	"jc": true, "jmin": true, "jmax": true,
	"s1": true, "s2": true, "s3": true, "s4": true,
	"h1": true, "h2": true, "h3": true, "h4": true,
	"i1": true, "i2": true, "i3": true, "i4": true, "i5": true,

	// 3.1. A server with RandomTrailers on appends random bytes to every
	// handshake message, and a client that does not know to expect them
	// identifies the packet by its size and does not recognise it at all --
	// which is not weaker obfuscation but no connection.
	"headerprotectionkey": true, "contentpaddingaddition": true,
	"rekeyaftertime": true, "rekeytimeout": true, "rejectaftertime": true,
	"keepalivetimeout": true, "maxhandshakeattempts": true,
	"randomtrailers": true, "disablecookies": true,
}

// uapiValue converts a value written the way a .conf writes it into the way the
// device reads it.
//
// Only the flags need it, and they need it badly: a file says "on", the device
// parses with strconv.ParseBool, and ParseBool does not accept "on". Passed
// through unchanged, a perfectly ordinary configuration is rejected with
// "failed to parse random trailers" and nothing connects.
func uapiValue(key, value string) string {
	if key != "randomtrailers" && key != "disablecookies" {
		return value
	}
	switch strings.ToLower(strings.TrimSpace(value)) {
	case "on", "true", "1", "yes":
		return "true"
	case "off", "false", "0", "no":
		return "false"
	}
	// Anything else is passed on for the device to reject: guessing at a value
	// nobody wrote is how a tunnel comes up with obfuscation quietly disabled.
	return value
}

// uapiNames maps what a .conf calls a parameter to what the device calls it.
//
// The two disagree for everything added in 3.x: a file says
// HeaderProtectionKey and the device wants header_protection_key. The 2.x
// parameters are spelled the same in both, so they are absent here and pass
// through under their own name.
var uapiNames = map[string]string{
	"headerprotectionkey":    "header_protection_key",
	"contentpaddingaddition": "content_padding_addition",
	"rekeyaftertime":         "rekey_after_time",
	"rekeytimeout":           "rekey_timeout",
	"rejectaftertime":        "reject_after_time",
	"keepalivetimeout":       "keepalive_timeout",
	"maxhandshakeattempts":   "max_handshake_attempts",
	"randomtrailers":         "random_trailers",
	"disablecookies":         "disable_cookies",
}

// ParseConfig reads the `.conf` format Amnezia and WireGuard both use.
func ParseConfig(text string) (*Config, error) {
	cfg := &Config{MTU: 1420, Obfuscation: map[string]string{}}

	section := ""
	for lineNo, raw := range strings.Split(text, "\n") {
		line := strings.TrimSpace(raw)
		if line == "" || strings.HasPrefix(line, "#") || strings.HasPrefix(line, ";") {
			continue
		}

		if strings.HasPrefix(line, "[") && strings.HasSuffix(line, "]") {
			section = strings.ToLower(strings.Trim(line, "[]"))
			continue
		}

		key, value, found := strings.Cut(line, "=")
		if !found {
			return nil, fmt.Errorf("line %d: expected key = value, got %q", lineNo+1, line)
		}
		key = strings.ToLower(strings.TrimSpace(key))
		value = strings.TrimSpace(value)

		var err error
		switch section {
		case "interface":
			err = cfg.setInterface(key, value)
		case "peer":
			err = cfg.Peer.set(key, value)
		default:
			err = fmt.Errorf("key %q outside any section", key)
		}
		if err != nil {
			return nil, fmt.Errorf("line %d: %w", lineNo+1, err)
		}
	}

	if cfg.PrivateKey == "" {
		return nil, fmt.Errorf("no PrivateKey in [Interface]")
	}
	if cfg.Peer.PublicKey == "" {
		return nil, fmt.Errorf("no PublicKey in [Peer]")
	}
	if len(cfg.Addresses) == 0 {
		return nil, fmt.Errorf("no Address in [Interface]")
	}

	return cfg, nil
}

func (c *Config) setInterface(key, value string) error {
	if obfuscationKeys[key] {
		// Ключ защиты заголовков в файле записан base64, как и все ключи
		// WireGuard, а устройство читает его hex — как и все ключи WireGuard в
		// UAPI. Без перевода настройка падает на "invalid byte" и туннель не
		// поднимается вовсе.
		if key == "headerprotectionkey" {
			hexKey, err := keyToHex(value)
			if err != nil {
				return fmt.Errorf("HeaderProtectionKey: %w", err)
			}
			c.Obfuscation[key] = hexKey
			return nil
		}
		c.Obfuscation[key] = value
		return nil
	}

	switch key {
	case "privatekey":
		hexKey, err := keyToHex(value)
		if err != nil {
			return fmt.Errorf("PrivateKey: %w", err)
		}
		c.PrivateKey = hexKey
	case "address":
		addrs, err := parseAddrList(value)
		if err != nil {
			return fmt.Errorf("Address: %w", err)
		}
		c.Addresses = append(c.Addresses, addrs...)
	case "dns":
		addrs, err := parseAddrList(value)
		if err != nil {
			return fmt.Errorf("DNS: %w", err)
		}
		c.DNS = append(c.DNS, addrs...)
	case "mtu":
		mtu, err := strconv.Atoi(value)
		if err != nil {
			return fmt.Errorf("MTU: %w", err)
		}
		c.MTU = mtu
	default:
		// Unknown interface keys are ignored rather than rejected. Subscription
		// providers add their own, and refusing to connect over one we do not
		// recognise would be the wrong trade for a tool people reach for when
		// other things have already stopped working.
	}
	return nil
}

func (p *Peer) set(key, value string) error {
	switch key {
	case "publickey":
		hexKey, err := keyToHex(value)
		if err != nil {
			return fmt.Errorf("PublicKey: %w", err)
		}
		p.PublicKey = hexKey
	case "presharedkey":
		hexKey, err := keyToHex(value)
		if err != nil {
			return fmt.Errorf("PresharedKey: %w", err)
		}
		p.PresharedKey = hexKey
	case "endpoint":
		p.Endpoint = value
	case "allowedips":
		for _, part := range strings.Split(value, ",") {
			if part = strings.TrimSpace(part); part != "" {
				p.AllowedIPs = append(p.AllowedIPs, part)
			}
		}
	case "persistentkeepalive":
		seconds, err := strconv.Atoi(value)
		if err != nil {
			return fmt.Errorf("PersistentKeepalive: %w", err)
		}
		p.Keepalive = seconds
	}
	return nil
}

// IPC renders the configuration in the UAPI form the device layer consumes.
//
// Ordering is significant: interface-level settings come first, and
// `public_key` opens the peer section, so everything after it is read as
// belonging to that peer.
func (c *Config) IPC() string {
	var b strings.Builder

	fmt.Fprintf(&b, "private_key=%s\n", c.PrivateKey)

	// Sorted for reproducibility — the device does not care about the order of
	// these, but a config that renders differently run to run is one nobody can
	// diff when a connection stops working.
	for _, key := range []string{
		"jc", "jmin", "jmax",
		"s1", "s2", "s3", "s4",
		"h1", "h2", "h3", "h4",
		"i1", "i2", "i3", "i4", "i5",

		// 3.1, in the order amneziawg-tools parses them.
		"headerprotectionkey", "contentpaddingaddition",
		"rekeyaftertime", "rekeytimeout", "rejectaftertime",
		"keepalivetimeout", "maxhandshakeattempts",
		"randomtrailers", "disablecookies",
	} {
		if value, ok := c.Obfuscation[key]; ok {
			name := key
			if mapped, ok := uapiNames[key]; ok {
				name = mapped
			}
			fmt.Fprintf(&b, "%s=%s\n", name, uapiValue(key, value))
		}
	}

	fmt.Fprintf(&b, "public_key=%s\n", c.Peer.PublicKey)
	if c.Peer.PresharedKey != "" {
		fmt.Fprintf(&b, "preshared_key=%s\n", c.Peer.PresharedKey)
	}
	if c.Peer.Endpoint != "" {
		fmt.Fprintf(&b, "endpoint=%s\n", c.Peer.Endpoint)
	}
	for _, allowed := range c.Peer.AllowedIPs {
		fmt.Fprintf(&b, "allowed_ip=%s\n", allowed)
	}
	if c.Peer.Keepalive > 0 {
		fmt.Fprintf(&b, "persistent_keepalive_interval=%d\n", c.Peer.Keepalive)
	}

	return b.String()
}

// keyToHex converts a base64 Curve25519 key into the hex the UAPI expects.
func keyToHex(value string) (string, error) {
	raw, err := base64.StdEncoding.DecodeString(value)
	if err != nil {
		return "", fmt.Errorf("not valid base64: %w", err)
	}
	if len(raw) != 32 {
		return "", fmt.Errorf("expected 32 bytes, got %d", len(raw))
	}
	return hex.EncodeToString(raw), nil
}

func parseAddrList(value string) ([]netip.Addr, error) {
	var addrs []netip.Addr
	for _, part := range strings.Split(value, ",") {
		part = strings.TrimSpace(part)
		if part == "" {
			continue
		}
		// Addresses carry a prefix length that the netstack does not want.
		if prefix, err := netip.ParsePrefix(part); err == nil {
			addrs = append(addrs, prefix.Addr())
			continue
		}
		addr, err := netip.ParseAddr(part)
		if err != nil {
			return nil, fmt.Errorf("%q is neither an address nor a prefix", part)
		}
		addrs = append(addrs, addr)
	}
	return addrs, nil
}
