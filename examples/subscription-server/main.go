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
	"encoding/json"
	"flag"
	"fmt"
	"log"
	"net/http"
	"os"
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
// Only endpoints, because only AmneziaWG is implemented. A server that also
// carries vless puts it in "outbounds" beside this, and the client reads past
// what it cannot run.
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
	ID          string   `json:"id"`
	Country     string   `json:"country,omitempty"`
	Description string   `json:"description,omitempty"`
	Maintenance bool     `json:"maintenance,omitempty"`
	Endpoint    endpoint `json:"endpoint"`
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
	Meta                map[string]meta       `json:"meta,omitempty"`
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

	http.HandleFunc("/sub/", store.serve)
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
			if _, ok := loaded.Nodes[name]; !ok {
				return fmt.Errorf("a subscriber names node %q, which is not defined", name)
			}
		}
		if len(token) < 24 {
			// Refused rather than warned about. The token is the entire
			// credential, and a short one in an example is a short one in
			// production three weeks later.
			return fmt.Errorf("a token is %d characters; make it at least 24 and random", len(token))
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

	// Offered rather than assumed. A client that did not ask gets plain sing-box
	// JSON, which is what keeps the same link usable in other clients.
	var answer any
	if strings.Contains(r.Header.Get("Accept"), caeloDocumentType) {
		w.Header().Set("Content-Type", caeloDocumentType)
		answer = caeloAnswer(loaded, who)
	} else {
		w.Header().Set("Content-Type", "application/json")
		answer = plainAnswer(loaded, who)
	}

	if err := json.NewEncoder(w).Encode(answer); err != nil {
		// Too late to change the status code; the client will fail to parse and
		// keep the copy it already had, which is the behaviour that exists for
		// exactly this.
		log.Printf("writing a response: %v", err)
	}
}

func plainAnswer(loaded config, who subscriber) document {
	answer := document{}
	for _, name := range who.Nodes {
		node := loaded.Nodes[name]
		node.Type = endpointType
		answer.Endpoints = append(answer.Endpoints, node)
	}
	return answer
}

func caeloAnswer(loaded config, who subscriber) caeloDocument {
	answer := caeloDocument{Version: 1}
	for _, name := range who.Nodes {
		node := loaded.Nodes[name]
		node.Type = endpointType
		about := loaded.Meta[name]
		answer.Nodes = append(answer.Nodes, caeloNode{
			// The name in the file, which is what an operator renames a node
			// away from rather than to: it is not shown anywhere and has no
			// reason to change when the tag does.
			ID:          name,
			Country:     about.Country,
			Description: about.Description,
			Maintenance: about.Maintenance,
			Endpoint:    node,
		})
	}
	return answer
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
