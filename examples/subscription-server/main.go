// Command subscription-server serves a Caelo subscription.
//
// It is an example, not the service. There is no database, no billing, no
// account system and no way to add a subscriber except by editing a file — all
// of which the real thing needs and none of which teaches anybody the format.
// What it does do is implement the whole of docs/subscriptions.md, so that the
// contract has two sides that can be run against each other.
//
// The types below are declared here rather than imported from the client.
// Anyone implementing this contract will write their own, in whatever language
// their service is in, and an example that only works by importing Caelo would
// be demonstrating the wrong thing. docs/subscriptions.md is the authority, and
// the test beside this file is what keeps the two from drifting: it serves a
// document and hands it to the client's own reader.
//
//	subscription-server -config nodes.json -listen :8080
//	curl -i http://localhost:8080/sub/<token>
//
// Serve it over HTTPS. The document contains private keys, and this program
// speaks plain HTTP because terminating TLS is the job of whatever is in front
// of it in any deployment worth the name.
package main

import (
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"flag"
	"fmt"
	"log"
	"net/http"
	"net/url"
	"os"
	"sort"
	"strings"
	"sync"
	"time"
)

// endpointType is what a Caelo node calls itself. Everything else in a sing-box
// document is another protocol, and this server serves only this one.
const endpointType = "amneziawg"

// caeloDocumentType is what a client sends in Accept to say it can read more
// than the plain document, and what this server answers with when it can.
const caeloDocumentType = "application/vnd.caelo.subscription+json"

// document is what a subscription URL returns: plain sing-box JSON.
//
// Only endpoints: AmneziaWG. Nodes of other protocols are not sing-box
// endpoints and are not put here; they reach a client as links, in version 2
// of the Caelo document or in a plain list.
type document struct {
	Endpoints []endpoint `json:"endpoints"`
}

// caeloDocument is the richer answer: each node carries its own endpoint, so
// there is nothing to join the metadata to it on. A table beside the endpoints
// array would need a key, and the only candidate is the tag — which is exactly
// the unreliable thing an identity is being added to replace.
type caeloDocument struct {
	Version int         `json:"version"`
	Nodes   []caeloNode `json:"nodes"`
}

type caeloNode struct {
	// Stable for the same node across refreshes. This is what a client's "use
	// this one" is remembered by, so a server that renumbers them silently
	// unpins everybody.
	ID          string `json:"id"`
	Country     string `json:"country,omitempty"`
	Description string `json:"description,omitempty"`
	Maintenance bool   `json:"maintenance,omitempty"`

	// An AmneziaWG node carries its endpoint; a node of another protocol, in
	// version 2 only, carries the protocol and its share link instead.
	Endpoint *endpoint `json:"endpoint,omitempty"`
	Protocol string    `json:"protocol,omitempty"`
	URI      string    `json:"uri,omitempty"`
}

// endpoint is sing-box's WireGuard endpoint plus the obfuscation set. Fields
// that do not apply are omitted; a node with no obfuscation is plain WireGuard
// and works.
type endpoint struct {
	Type string `json:"type"`
	Tag  string `json:"tag,omitempty"`

	Address    []string `json:"address"`
	PrivateKey string   `json:"private_key"`
	MTU        int      `json:"mtu,omitempty"`
	DNS        []string `json:"dns,omitempty"`

	Peers []peer `json:"peers"`

	// Left as raw JSON so that a number stays a number and a string stays a
	// string. The client accepts either, and this server has no reason to have
	// an opinion about how an operator wrote them in the file.
	Jc   json.RawMessage `json:"jc,omitempty"`
	Jmin json.RawMessage `json:"jmin,omitempty"`
	Jmax json.RawMessage `json:"jmax,omitempty"`
	S1   json.RawMessage `json:"s1,omitempty"`
	S2   json.RawMessage `json:"s2,omitempty"`
	S3   json.RawMessage `json:"s3,omitempty"`
	S4   json.RawMessage `json:"s4,omitempty"`
	H1   json.RawMessage `json:"h1,omitempty"`
	H2   json.RawMessage `json:"h2,omitempty"`
	H3   json.RawMessage `json:"h3,omitempty"`
	H4   json.RawMessage `json:"h4,omitempty"`
	I1   json.RawMessage `json:"i1,omitempty"`
	I2   json.RawMessage `json:"i2,omitempty"`
	I3   json.RawMessage `json:"i3,omitempty"`
	I4   json.RawMessage `json:"i4,omitempty"`
	I5   json.RawMessage `json:"i5,omitempty"`
}

// peer is the far end. A list because sing-box's is; AmneziaWG describes one.
type peer struct {
	Address                     string   `json:"address"`
	Port                        int      `json:"port"`
	PublicKey                   string   `json:"public_key"`
	PreSharedKey                string   `json:"pre_shared_key,omitempty"`
	AllowedIPs                  []string `json:"allowed_ips,omitempty"`
	PersistentKeepaliveInterval int      `json:"persistent_keepalive_interval,omitempty"`
}

// config is the file this example is driven by.
//
// Subscribers name nodes rather than embedding them, so that a node's key can
// be rotated in one place. The order in which a subscriber names them is the
// order they are served in, which is the priority the client obeys.
type config struct {
	UpdateIntervalHours int                   `json:"update_interval_hours"`
	Subscribers         map[string]subscriber `json:"subscribers"`
	Nodes               map[string]endpoint   `json:"nodes"`
	// Links are nodes of other protocols, by name: a vless:// share link
	// each. A subscriber names them in the same list as nodes.
	Links map[string]string `json:"links,omitempty"`
	Meta  map[string]meta   `json:"meta,omitempty"`
}

// meta is what a node looks like to a person, kept beside the configuration
// rather than inside it: none of it can go in the endpoint, which has to stay
// valid sing-box JSON.
type meta struct {
	Country     string `json:"country,omitempty"`
	Description string `json:"description,omitempty"`
	Maintenance bool   `json:"maintenance,omitempty"`
}

type subscriber struct {
	// Title is what the subscription is called in a client: profile-title.
	Title      string    `json:"title,omitempty"`
	Expires    time.Time `json:"expires"`
	QuotaBytes int64     `json:"quota_bytes"`
	UsedBytes  int64     `json:"used_bytes"`
	Nodes      []string  `json:"nodes"`
}

func main() {
	path := flag.String("config", "nodes.json", "the subscribers and nodes to serve")
	listen := flag.String("listen", ":8080", "address to listen on")
	flag.Parse()

	log.SetPrefix("subscription-server: ")
	log.SetFlags(log.LstdFlags)

	store := &store{path: *path}
	if err := store.reload(); err != nil {
		log.Fatal(err)
	}

	// The optional half of the contract. A server may implement neither and be
	// correct; these exist because a client cannot solve either problem alone.
	http.HandleFunc("/sub/", store.route)
	log.Printf("listening on %s with %d subscribers", *listen, store.count())

	server := &http.Server{
		Addr: *listen,
		// A subscription is one small document. A client that has not finished
		// asking within this has a network problem, and holding the connection
		// open helps nobody.
		ReadHeaderTimeout: 5 * time.Second,
		WriteTimeout:      15 * time.Second,
	}
	log.Fatal(server.ListenAndServe())
}

type store struct {
	path string

	mu     sync.RWMutex
	loaded config
}

func (s *store) reload() error {
	raw, err := os.ReadFile(s.path)
	if err != nil {
		return fmt.Errorf("reading %s: %w", s.path, err)
	}

	var loaded config
	decoder := json.NewDecoder(strings.NewReader(string(raw)))
	// Strict, unlike the client's reader. A typo in a file somebody is editing
	// by hand should be a refusal to start rather than a subscriber who
	// silently has no nodes.
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(&loaded); err != nil {
		return fmt.Errorf("reading %s: %w", s.path, err)
	}

	for token, who := range loaded.Subscribers {
		for _, name := range who.Nodes {
			_, isNode := loaded.Nodes[name]
			_, isLink := loaded.Links[name]
			if !isNode && !isLink {
				return fmt.Errorf("a subscriber names node %q, which is not defined", name)
			}
			if isNode && isLink {
				return fmt.Errorf("%q is both a node and a link", name)
			}
		}
		if len(token) < 24 {
			// Refused rather than warned about. The token is the entire
			// credential, and a short one in an example is a short one in
			// production three weeks later.
			return fmt.Errorf("a token is %d characters; make it at least 24 and random", len(token))
		}
	}

	for name, link := range loaded.Links {
		if variant(link) == "" {
			return fmt.Errorf("link %q is not a vless:// share link this example understands", name)
		}
	}

	s.mu.Lock()
	s.loaded = loaded
	s.mu.Unlock()
	return nil
}

func (s *store) count() int {
	s.mu.RLock()
	defer s.mu.RUnlock()
	return len(s.loaded.Subscribers)
}

func (s *store) serve(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		w.Header().Set("Allow", http.MethodGet)
		http.Error(w, "", http.StatusMethodNotAllowed)
		return
	}

	token := strings.TrimPrefix(r.URL.Path, "/sub/")

	s.mu.RLock()
	loaded := s.loaded
	who, known := loaded.Subscribers[token]
	s.mu.RUnlock()

	// The same answer for an unknown token as for a revoked one, and nothing
	// logged that contains either. The difference is information nobody outside
	// this service needs, and a log of tokens is a log of credentials.
	if !known {
		http.NotFound(w, r)
		return
	}
	if !who.Expires.IsZero() && time.Now().After(who.Expires) {
		http.NotFound(w, r)
		return
	}

	w.Header().Set("Cache-Control", "no-store")
	w.Header().Set("subscription-userinfo", userinfo(who))
	if loaded.UpdateIntervalHours > 0 {
		w.Header().Set("profile-update-interval", fmt.Sprint(loaded.UpdateIntervalHours))
	}

	if who.Title != "" {
		// base64: so that a title in any language survives a header.
		w.Header().Set("profile-title", "base64:"+base64.StdEncoding.EncodeToString([]byte(who.Title)))
	}

	// Offered rather than assumed. What a client asked for and said it can
	// run decides the shape; nothing is sent that it did not say it reads.
	accept := r.Header.Get("Accept")
	can := capabilities(r)
	var answer any
	switch {
	case strings.Contains(accept, caeloDocumentType) && (strings.Contains(accept, "version=2") || can["subscription-v2"]):
		w.Header().Set("Content-Type", caeloDocumentType)
		answer = caeloAnswer(loaded, who, 2, can)
	case strings.Contains(accept, caeloDocumentType):
		// A Caelo that runs AmneziaWG only gets exactly what it always got.
		w.Header().Set("Content-Type", caeloDocumentType)
		answer = caeloAnswer(loaded, who, 1, nil)
	case hasLinks(loaded, who) && (strings.Contains(accept, "text/plain") || !hasEndpoints(loaded, who)):
		// The list every V2Ray-family client reads: to whoever asks for it,
		// and to anybody when there is nothing a sing-box document could
		// carry. Otherwise a client that did not ask gets sing-box JSON, as
		// it always did.
		w.Header().Set("Content-Type", "text/plain; charset=utf-8")
		fmt.Fprint(w, linksAnswer(loaded, who))
		return
	default:
		w.Header().Set("Content-Type", "application/json")
		answer = plainAnswer(loaded, who)
	}

	// Servers for this subscriber and none this client runs: say so, rather
	// than send an empty document a client would show as an empty
	// subscription.
	if document, ok := answer.(caeloDocument); ok && len(document.Nodes) == 0 && len(who.Nodes) > 0 {
		w.Header().Del("Content-Type")
		http.Error(w, "no servers this client can run", http.StatusNotAcceptable)
		return
	}

	if err := json.NewEncoder(w).Encode(answer); err != nil {
		// Too late to change the status code; the client will fail to parse and
		// keep the copy it already had, which is the behaviour that exists for
		// exactly this.
		log.Printf("writing a response: %v", err)
	}
}

func plainAnswer(loaded config, who subscriber) document {
	answer := document{Endpoints: []endpoint{}}
	for _, name := range who.Nodes {
		node, ok := loaded.Nodes[name]
		if !ok {
			continue // a link: not a sing-box endpoint
		}
		node.Type = endpointType
		answer.Endpoints = append(answer.Endpoints, node)
	}
	return answer
}

// caeloAnswer renders the Caelo document. Version 1 carries AmneziaWG only;
// version 2 adds the links whose kind of connection the client said it runs.
func caeloAnswer(loaded config, who subscriber, version int, can map[string]bool) caeloDocument {
	answer := caeloDocument{Version: version, Nodes: []caeloNode{}}
	for _, name := range who.Nodes {
		about := loaded.Meta[name]
		entry := caeloNode{
			// The name in the file, which is what an operator renames a node
			// away from rather than to: it is not shown anywhere and has no
			// reason to change when the tag does.
			ID:          name,
			Country:     about.Country,
			Description: about.Description,
			Maintenance: about.Maintenance,
		}
		if node, ok := loaded.Nodes[name]; ok {
			node.Type = endpointType
			entry.Endpoint = &node
		} else {
			link := loaded.Links[name]
			if version < 2 || !can[variant(link)] {
				continue
			}
			entry.Protocol = "vless"
			entry.URI = link
		}
		answer.Nodes = append(answer.Nodes, entry)
	}
	return answer
}

// linksAnswer is the plain list: one share link per line, base64 as is
// customary. Only links — an AmneziaWG endpoint has no share link.
func linksAnswer(loaded config, who subscriber) string {
	var lines []string
	for _, name := range who.Nodes {
		if link, ok := loaded.Links[name]; ok {
			lines = append(lines, link)
		}
	}
	return base64.StdEncoding.EncodeToString([]byte(strings.Join(lines, "\n") + "\n"))
}

func hasEndpoints(loaded config, who subscriber) bool {
	for _, name := range who.Nodes {
		if _, ok := loaded.Nodes[name]; ok {
			return true
		}
	}
	return false
}

func hasLinks(loaded config, who subscriber) bool {
	for _, name := range who.Nodes {
		if _, ok := loaded.Links[name]; ok {
			return true
		}
	}
	return false
}

// capabilities reads X-Caelo-Capabilities: a comma-separated list. Absent
// means AmneziaWG only.
func capabilities(r *http.Request) map[string]bool {
	out := map[string]bool{}
	for _, each := range strings.Split(r.Header.Get("X-Caelo-Capabilities"), ",") {
		if each = strings.TrimSpace(each); each != "" {
			out[each] = true
		}
	}
	return out
}

// variant names a link's kind of connection the way capabilities do:
// vless-reality-vision, vless-tls-xhttp. Empty for a link this example does
// not recognise.
func variant(link string) string {
	u, err := url.Parse(link)
	if err != nil || u.Scheme != "vless" {
		return ""
	}
	q := u.Query()
	security := q.Get("security")
	if security != "reality" && security != "tls" {
		return ""
	}
	switch q.Get("type") {
	case "", "tcp", "raw":
		if strings.HasPrefix(q.Get("flow"), "xtls-rprx-vision") {
			return "vless-" + security + "-vision"
		}
		return ""
	case "xhttp":
		return "vless-" + security + "-xhttp"
	}
	return ""
}

// userinfo renders the header the V2Ray and Clash ecosystems already use, so
// that a Caelo subscription can be read by other clients.
func userinfo(who subscriber) string {
	var expire int64
	if !who.Expires.IsZero() {
		expire = who.Expires.Unix()
	}
	return fmt.Sprintf("upload=0; download=%d; total=%d; expire=%d",
		who.UsedBytes, who.QuotaBytes, expire)
}

// route sends /sub/<token> to the document and /sub/<token>/state to the cheap
// summary. Written by hand rather than with a router so that the example brings
// in nothing a reader has to go and learn.
func (s *store) route(w http.ResponseWriter, r *http.Request) {
	rest := strings.TrimPrefix(r.URL.Path, "/sub/")
	if token, ok := strings.CutSuffix(rest, "/state"); ok {
		s.serveState(w, r, token)
		return
	}
	s.serve(w, r)
}

// serveState answers "has anything changed" without sending the keys.
//
// The versions are hashes of the content rather than counters kept beside it. A
// counter has to be incremented by every piece of code that changes a node, and
// the day somebody forgets, a client keeps a configuration that no longer works
// and has no way to find out. A hash cannot be forgotten.
func (s *store) serveState(w http.ResponseWriter, r *http.Request, token string) {
	if r.Method != http.MethodGet {
		w.Header().Set("Allow", http.MethodGet)
		http.Error(w, "", http.StatusMethodNotAllowed)
		return
	}

	s.mu.RLock()
	loaded := s.loaded
	who, known := loaded.Subscribers[token]
	s.mu.RUnlock()

	if !known || (!who.Expires.IsZero() && time.Now().After(who.Expires)) {
		http.NotFound(w, r)
		return
	}

	// Devices, if this server keeps per-device sets. Here the header only
	// changes what is hashed, because the example serves one set; a real server
	// would look up that device's own nodes. What matters for the contract is
	// that an unknown header is ignored rather than rejected.
	device := r.Header.Get("X-Caelo-Device")
	// X-Caelo-Device-Name (percent-encoded UTF-8) and X-Caelo-Platform
	// ("android 14") say what the device is, for a server that lists devices
	// to a person. Descriptive only and optional; this example lists nothing,
	// so it reads neither.

	type nodeState struct {
		ID      string `json:"id"`
		Version string `json:"version"`
		Server  string `json:"server"`
	}
	states := make([]nodeState, 0, len(who.Nodes))
	parts := make([]string, 0, len(who.Nodes))
	for _, name := range who.Nodes {
		var raw []byte
		server := ""
		if node, ok := loaded.Nodes[name]; ok {
			raw, _ = json.Marshal(node)
			server = node.Tag
		} else {
			// A link's version covers the link: a new user id, fingerprint
			// or path is a new version.
			raw = []byte(loaded.Links[name])
			if u, err := url.Parse(loaded.Links[name]); err == nil {
				server = u.Fragment
			}
		}
		sum := sha256.Sum256(append([]byte(device), raw...))
		version := hex.EncodeToString(sum[:8])
		states = append(states, nodeState{ID: name, Version: version, Server: server})
		parts = append(parts, name+":"+version)
	}
	sort.Strings(parts)
	whole := sha256.Sum256([]byte(strings.Join(parts, "\n")))

	w.Header().Set("Cache-Control", "no-store")
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(map[string]any{
		"version": hex.EncodeToString(whole[:8]),
		"nodes":   states,
	})
}
