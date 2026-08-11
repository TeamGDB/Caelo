// Package selection orders the nodes a subscription offers.
//
// This is the first half of automatic selection: a stable preference order to
// probe in. The second half — deciding when a node is good enough, remembering
// what worked on which network, and refusing to jump between nodes over jitter
// — needs measurements this package does not have.
//
// The rule comes from the Android prototype, where it was the one piece of real
// product logic in an otherwise simulated interface. It lives here rather than
// in the interface because both the ordering and the probing have to agree, and
// two implementations of an ordering eventually disagree.
package selection

import (
	"cmp"
	"slices"
)

// Grade is how much a node is trusted, independent of how fast it is.
//
// A slow main node beats a fast experimental one: the fast one is fast until
// the day it is not, and someone finds out at the worst possible moment.
type Grade int

const (
	// Main carries traffic by default.
	Main Grade = iota
	// Stable is proven but not preferred.
	Stable
	// Testing works and is not trusted with a default.
	Testing
	// Offline is known not to be usable.
	Offline
)

// Node is a candidate to connect through.
type Node struct {
	Name  string
	Grade Grade

	// LatencyMs is the last measurement, or nil if it has never been probed.
	// Never probed sorts after every measurement rather than before, so an
	// unknown node does not outrank one that has actually answered.
	LatencyMs *int
}

// Order returns nodes in the order they should be tried: by grade, then by
// latency, then by name.
//
// The name is the final tiebreak so the order does not shuffle between runs.
// A list that reorders itself while someone is looking at it reads as the app
// doing something, and it is not.
func Order(nodes []Node) []Node {
	ordered := slices.Clone(nodes)
	slices.SortStableFunc(ordered, func(a, b Node) int {
		if c := cmp.Compare(a.Grade, b.Grade); c != 0 {
			return c
		}
		if c := cmp.Compare(latency(a), latency(b)); c != 0 {
			return c
		}
		return cmp.Compare(a.Name, b.Name)
	})
	return ordered
}

// Usable reports whether a node is worth trying at all.
func Usable(node Node) bool { return node.Grade != Offline }

func latency(node Node) int {
	if node.LatencyMs == nil {
		return int(^uint(0) >> 1)
	}
	return *node.LatencyMs
}
