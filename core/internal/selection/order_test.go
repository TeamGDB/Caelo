package selection

import (
	"slices"
	"testing"
)

func ms(value int) *int { return &value }

func names(nodes []Node) []string {
	result := make([]string, len(nodes))
	for i, node := range nodes {
		result[i] = node.Name
	}
	return result
}

func TestGradeOutranksLatency(t *testing.T) {
	// The whole point of grading: a slow trusted node beats a fast untrusted
	// one, because the fast one is fast right up until it is not.
	got := names(Order([]Node{
		{Name: "Testing-fast", Grade: Testing, LatencyMs: ms(10)},
		{Name: "Main-slow", Grade: Main, LatencyMs: ms(200)},
	}))

	if want := []string{"Main-slow", "Testing-fast"}; !slices.Equal(got, want) {
		t.Errorf("order = %v, want %v", got, want)
	}
}

func TestLatencyBreaksGradeTies(t *testing.T) {
	got := names(Order([]Node{
		{Name: "Nord", Grade: Stable, LatencyMs: ms(36)},
		{Name: "Rhein", Grade: Stable, LatencyMs: ms(48)},
		{Name: "Aurora", Grade: Main, LatencyMs: ms(24)},
	}))

	if want := []string{"Aurora", "Nord", "Rhein"}; !slices.Equal(got, want) {
		t.Errorf("order = %v, want %v", got, want)
	}
}

func TestUnmeasuredSortsLast(t *testing.T) {
	// A node nobody has probed is not a fast node. Treating a missing
	// measurement as zero would put every new node at the front.
	got := names(Order([]Node{
		{Name: "Unmeasured", Grade: Stable},
		{Name: "Slow", Grade: Stable, LatencyMs: ms(400)},
	}))

	if want := []string{"Slow", "Unmeasured"}; !slices.Equal(got, want) {
		t.Errorf("order = %v, want %v", got, want)
	}
}

func TestNameIsTheFinalTiebreak(t *testing.T) {
	// Without this the order of equal nodes depends on the order they arrived
	// in, and a list that reshuffles between refreshes reads as the app doing
	// something when it is not.
	input := []Node{
		{Name: "Zulu", Grade: Main, LatencyMs: ms(50)},
		{Name: "Alfa", Grade: Main, LatencyMs: ms(50)},
	}
	first := names(Order(input))

	slices.Reverse(input)
	second := names(Order(input))

	if !slices.Equal(first, second) {
		t.Errorf("order depends on input order: %v then %v", first, second)
	}
	if want := []string{"Alfa", "Zulu"}; !slices.Equal(first, want) {
		t.Errorf("order = %v, want %v", first, want)
	}
}

func TestOrderDoesNotMutateItsInput(t *testing.T) {
	input := []Node{
		{Name: "Second", Grade: Stable},
		{Name: "First", Grade: Main},
	}
	Order(input)

	if input[0].Name != "Second" {
		t.Error("Order reordered the slice it was given")
	}
}

func TestOfflineIsNotUsable(t *testing.T) {
	for grade, usable := range map[Grade]bool{
		Main: true, Stable: true, Testing: true, Offline: false,
	} {
		if got := Usable(Node{Grade: grade}); got != usable {
			t.Errorf("Usable(grade %d) = %v, want %v", grade, got, usable)
		}
	}
}
