package awg

import (
	"encoding/json"
	"fmt"
	"strconv"
	"strings"
)

// EndpointType is what a Caelo node calls itself inside a sing-box document.
const EndpointType = "amneziawg"

// Endpoint is one node as a subscription delivers it.
//
// The shape is sing-box's WireGuard endpoint with the obfuscation fields added,
// deliberately: when the type is registered with sing-box's endpoint registry,
// that registration should describe what is already being served rather than
// change it. Field names and their JSON spellings are taken from
// option.WireGuardEndpointOptions.
//
// This is the configuration half of a subscription. The list -- which nodes,
// in what order, under what names -- is the app's, and nothing in this file
// knows that a subscription exists.
type Endpoint struct {
	Type string `json:"type"`
	Tag  string `json:"tag,omitempty"`

	Address    []string `json:"address"`
	PrivateKey string   `json:"private_key"`
	MTU        int      `json:"mtu,omitempty"`
	DNS        []string `json:"dns,omitempty"`

	Peers []EndpointPeer `json:"peers"`

	// The obfuscation set. Junk packet counts and sizes are numbers, header
	// magic and the signature packets are strings with a grammar of their own,
	// and all of them are carried to the device layer as they arrived. Every
	// one accepts either spelling on the way in: a server that writes "6" where
	// 6 was expected is a server we can still connect through.
	Jc   Scalar `json:"jc,omitempty"`
	Jmin Scalar `json:"jmin,omitempty"`
	Jmax Scalar `json:"jmax,omitempty"`
	S1   Scalar `json:"s1,omitempty"`
	S2   Scalar `json:"s2,omitempty"`
	S3   Scalar `json:"s3,omitempty"`
	S4   Scalar `json:"s4,omitempty"`
	H1   Scalar `json:"h1,omitempty"`
	H2   Scalar `json:"h2,omitempty"`
	H3   Scalar `json:"h3,omitempty"`
	H4   Scalar `json:"h4,omitempty"`
	I1   Scalar `json:"i1,omitempty"`
	I2   Scalar `json:"i2,omitempty"`
	I3   Scalar `json:"i3,omitempty"`
	I4   Scalar `json:"i4,omitempty"`
	I5   Scalar `json:"i5,omitempty"`
}

// EndpointPeer is the far end. AmneziaWG describes exactly one, but the field
// is a list because sing-box's is, and a shape that differs from the one it
// will be registered as is a shape that has to be translated twice.
type EndpointPeer struct {
	Address                     string   `json:"address"`
	Port                        int      `json:"port"`
	PublicKey                   string   `json:"public_key"`
	PreSharedKey                string   `json:"pre_shared_key,omitempty"`
	AllowedIPs                  []string `json:"allowed_ips,omitempty"`
	PersistentKeepaliveInterval int      `json:"persistent_keepalive_interval,omitempty"`
}

// Scalar is a value that may arrive as a number or as a string.
//
// H1 through H4 can be ranges and I1 through I5 are packet descriptions, so
// those are strings; Jc and S1 through S4 are counts. Insisting on the right
// JSON type for each would turn a server's harmless choice of quoting into a
// tunnel that will not come up, and the device layer takes them all as text
// regardless.
type Scalar string

func (s *Scalar) UnmarshalJSON(data []byte) error {
	text := string(data)
	if text == "null" {
		return nil
	}
	if strings.HasPrefix(text, `"`) {
		var value string
		if err := json.Unmarshal(data, &value); err != nil {
			return err
		}
		*s = Scalar(value)
		return nil
	}
	// A number, which may be large enough to lose precision as a float, so it
	// is kept as written.
	if _, err := strconv.ParseFloat(text, 64); err != nil {
		return fmt.Errorf("expected a number or a string, got %s", text)
	}
	*s = Scalar(text)
	return nil
}

func (s Scalar) MarshalJSON() ([]byte, error) { return json.Marshal(string(s)) }

// ParseEndpoint reads one node of a sing-box document into the same
// configuration a `.conf` produces.
//
// The two paths converge here on purpose. Everything downstream -- the UAPI
// rendering, the addresses a platform needs to build a tun device, the probe --
// works on Config and cannot tell which form it arrived in.
func ParseEndpoint(data []byte) (*Config, error) {
	var endpoint Endpoint
	if err := json.Unmarshal(data, &endpoint); err != nil {
		return nil, fmt.Errorf("reading the endpoint: %w", err)
	}
	return endpoint.Config()
}

// Config converts a parsed endpoint into the internal form.
func (e Endpoint) Config() (*Config, error) {
	// Refused rather than assumed. A document that names a type we do not
	// implement is a document whose other fields we have no business guessing
	// at, and connecting anyway would produce a tunnel to somewhere nobody
	// asked for.
	if e.Type != "" && e.Type != EndpointType {
		return nil, fmt.Errorf("endpoint type %q is not %s", e.Type, EndpointType)
	}
	if len(e.Peers) == 0 {
		return nil, fmt.Errorf("the endpoint has no peers")
	}
	if len(e.Peers) > 1 {
		return nil, fmt.Errorf("the endpoint has %d peers; AmneziaWG describes one", len(e.Peers))
	}

	cfg := &Config{MTU: 1420, Obfuscation: map[string]string{}}
	if e.MTU > 0 {
		cfg.MTU = e.MTU
	}

	privateKey, err := keyToHex(e.PrivateKey)
	if err != nil {
		return nil, fmt.Errorf("private_key: %w", err)
	}
	cfg.PrivateKey = privateKey

	if len(e.Address) == 0 {
		return nil, fmt.Errorf("the endpoint has no address")
	}
	for _, address := range e.Address {
		addrs, err := parseAddrList(address)
		if err != nil {
			return nil, fmt.Errorf("address: %w", err)
		}
		cfg.Addresses = append(cfg.Addresses, addrs...)
	}
	if len(cfg.Addresses) == 0 {
		return nil, fmt.Errorf("the endpoint has no address")
	}

	for _, server := range e.DNS {
		addrs, err := parseAddrList(server)
		if err != nil {
			return nil, fmt.Errorf("dns: %w", err)
		}
		cfg.DNS = append(cfg.DNS, addrs...)
	}

	peer := e.Peers[0]
	publicKey, err := keyToHex(peer.PublicKey)
	if err != nil {
		return nil, fmt.Errorf("public_key: %w", err)
	}
	cfg.Peer.PublicKey = publicKey

	if peer.PreSharedKey != "" {
		presharedKey, err := keyToHex(peer.PreSharedKey)
		if err != nil {
			return nil, fmt.Errorf("pre_shared_key: %w", err)
		}
		cfg.Peer.PresharedKey = presharedKey
	}

	if peer.Address == "" || peer.Port == 0 {
		return nil, fmt.Errorf("the peer has no address and port")
	}
	// Rendered rather than carried as two fields, because everything that reads
	// an endpoint downstream splits host from port itself, and two
	// representations of the same thing is one too many.
	cfg.Peer.Endpoint = joinHostPort(peer.Address, peer.Port)

	cfg.Peer.AllowedIPs = peer.AllowedIPs
	if len(cfg.Peer.AllowedIPs) == 0 {
		cfg.Peer.AllowedIPs = []string{"0.0.0.0/0"}
	}
	cfg.Peer.Keepalive = peer.PersistentKeepaliveInterval

	for key, value := range map[string]Scalar{
		"jc": e.Jc, "jmin": e.Jmin, "jmax": e.Jmax,
		"s1": e.S1, "s2": e.S2, "s3": e.S3, "s4": e.S4,
		"h1": e.H1, "h2": e.H2, "h3": e.H3, "h4": e.H4,
		"i1": e.I1, "i2": e.I2, "i3": e.I3, "i4": e.I4, "i5": e.I5,
	} {
		if value != "" {
			cfg.Obfuscation[key] = string(value)
		}
	}

	return cfg, nil
}

// joinHostPort keeps an IPv6 literal in the brackets the rest of the world
// expects, without pretending to parse a name.
func joinHostPort(host string, port int) string {
	if strings.Contains(host, ":") && !strings.HasPrefix(host, "[") {
		return "[" + host + "]:" + strconv.Itoa(port)
	}
	return host + ":" + strconv.Itoa(port)
}

// Parse reads a configuration in either form.
//
// Every entry point calls this rather than choosing, so that a node delivered
// by a subscription and the same node pasted as a file take the same path from
// here on. A caller that had to pick would eventually pick differently in one
// place, and the difference would show up as one of the two working.
func Parse(text string) (*Config, error) {
	if LooksLikeJSON(text) {
		return ParseEndpoint([]byte(text))
	}
	return ParseConfig(text)
}

// LooksLikeJSON reports whether text is a configuration in the subscription's
// form rather than a `.conf`.
//
// The two are told apart by their first character, which is enough: a `.conf`
// begins with a section header or a comment, and a JSON object begins with a
// brace. Guessing wrong in either direction produces a parse error naming the
// format that was tried, rather than silence.
func LooksLikeJSON(text string) bool {
	return strings.HasPrefix(strings.TrimSpace(text), "{")
}
