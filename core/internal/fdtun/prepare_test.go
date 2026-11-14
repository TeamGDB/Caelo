//go:build android || linux || darwin

package fdtun

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/TeamGDB/Caelo/core/internal/protocol"
)

type preparingNode struct {
	protocol.Config
	prepare func(context.Context) (protocol.Config, error)
}

func (n *preparingNode) Pin(context.Context) (protocol.Config, string, error) {
	return n, "203.0.113.1", nil
}
func (n *preparingNode) Prepare(ctx context.Context) (protocol.Config, error) {
	if n.prepare != nil {
		return n.prepare(ctx)
	}
	return n, nil
}

func TestPreparationIsBoundToExactConfigurationAndConsumedOnce(t *testing.T) {
	for _, mode := range []string{"same", "changed", "expired", "stopped"} {
		t.Run(mode, func(t *testing.T) {
			s := New()
			node := &preparingNode{}
			got, address, err := s.Prepare(context.Background(), "config-a", node)
			if err != nil || got != node || address != "203.0.113.1" {
				t.Fatalf("prepare: %v %s %v", got, address, err)
			}
			text := "config-a"
			switch mode {
			case "changed":
				text = "config-b"
			case "expired":
				s.preparedAt = time.Now().Add(-time.Minute)
			case "stopped":
				s.Stop()
			}
			s.mu.Lock()
			defer s.mu.Unlock()
			got = s.takePreparedLocked(text)
			if (got == node) != (mode == "same") {
				t.Fatalf("unexpected cached preparation: %v", got)
			}
			if s.takePreparedLocked("config-a") != nil {
				t.Fatal("preparation reused")
			}
		})
	}
}

func TestPreparationCancellationNeverPublishesStaleResult(t *testing.T) {
	for _, replace := range []bool{false, true} {
		s := New()
		started := make(chan struct{})
		result := make(chan error, 1)
		slow := &preparingNode{}
		slow.prepare = func(ctx context.Context) (protocol.Config, error) { close(started); <-ctx.Done(); return slow, nil }
		go func() { _, _, err := s.Prepare(context.Background(), "old", slow); result <- err }()
		<-started
		current := &preparingNode{}
		if replace {
			if _, _, err := s.Prepare(context.Background(), "new", current); err != nil {
				t.Fatal(err)
			}
		} else {
			s.Stop()
		}
		select {
		case err := <-result:
			if !errors.Is(err, context.Canceled) {
				t.Fatalf("stale result: %v", err)
			}
		case <-time.After(time.Second):
			t.Fatal("prepare was not cancelled")
		}
		s.mu.Lock()
		got := s.takePreparedLocked("new")
		s.mu.Unlock()
		if replace && got != current {
			t.Fatal("stale result overwrote replacement")
		}
		if !replace && got != nil {
			t.Fatal("stop retained configuration")
		}
	}
}

func TestFailedPreparationCannotBeUsed(t *testing.T) {
	s := New()
	failure := errors.New("probe failed")
	node := &preparingNode{prepare: func(context.Context) (protocol.Config, error) { return nil, failure }}
	if _, _, err := s.Prepare(context.Background(), "a", node); !errors.Is(err, failure) {
		t.Fatal(err)
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.takePreparedLocked("a") != nil {
		t.Fatal("failed preparation cached")
	}
}

func TestAlreadyCancelledPreparationCannotBeUsed(t *testing.T) {
	s := New()
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	if _, _, err := s.Prepare(ctx, "a", &preparingNode{}); !errors.Is(err, context.Canceled) {
		t.Fatalf("cancelled preparation succeeded: %v", err)
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.takePreparedLocked("a") != nil {
		t.Fatal("cancelled preparation cached")
	}
}
