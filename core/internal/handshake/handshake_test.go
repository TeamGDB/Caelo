package handshake

import (
	"testing"
	"time"
)

func TestParseTakesTheLatestHandshake(t *testing.T) {
	uapi := "public_key=aa\nlast_handshake_time_sec=0\nlast_handshake_time_sec=1700000000\nlast_handshake_time_nsec=5\n"
	if got := Parse(uapi); got.Unix() != 1700000000 {
		t.Fatalf("got %v", got)
	}
}

func TestParseWithoutAHandshakeIsZero(t *testing.T) {
	if got := Parse("public_key=aa\nlast_handshake_time_sec=0\n"); !got.IsZero() {
		t.Fatalf("got %v, want zero", got)
	}
}

func TestWaitGivesUpWhenTheServerNeverAnswers(t *testing.T) {
	start := time.Now()
	ok := Wait(func() (string, error) { return "last_handshake_time_sec=0\n", nil }, 300*time.Millisecond)
	if ok {
		t.Fatal("reported a handshake that never happened")
	}
	if time.Since(start) < 300*time.Millisecond {
		t.Fatal("gave up before the timeout")
	}
}

func TestWaitReturnsOnceTheServerAnswers(t *testing.T) {
	calls := 0
	ok := Wait(func() (string, error) {
		calls++
		if calls < 3 {
			return "last_handshake_time_sec=0\n", nil
		}
		return "last_handshake_time_sec=1700000000\n", nil
	}, 5*time.Second)
	if !ok || calls != 3 {
		t.Fatalf("ok=%v calls=%d", ok, calls)
	}
}
