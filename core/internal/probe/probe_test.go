package probe

import (
	"context"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestFetchReadsPastTheOldFourKilobytes(t *testing.T) {
	t.Parallel()

	manifest := strings.Repeat("x", 10*1024)
	server := httptest.NewServer(http.HandlerFunc(func(response http.ResponseWriter, _ *http.Request) {
		_, _ = response.Write([]byte(manifest))
	}))
	defer server.Close()

	_, body, _, err := fetch(context.Background(), server.Client(), server.URL)
	if err != nil {
		t.Fatal(err)
	}
	if len(body) != len(manifest) {
		t.Fatalf("body is %d bytes, want all %d", len(body), len(manifest))
	}
}

func TestFetchRefusesRatherThanTruncates(t *testing.T) {
	t.Parallel()

	server := httptest.NewServer(http.HandlerFunc(func(response http.ResponseWriter, _ *http.Request) {
		_, _ = response.Write([]byte(strings.Repeat("x", MaxBody+1)))
	}))
	defer server.Close()

	if _, _, _, err := fetch(context.Background(), server.Client(), server.URL); err == nil {
		t.Fatal("an oversized body was accepted; it should be refused, not cut short")
	}
}
