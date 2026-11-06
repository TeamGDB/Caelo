package probe

import (
	"context"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestRequestMeasurementsKeepsAvailabilityAndLatencySeparate(t *testing.T) {
	t.Parallel()

	requests := 0
	server := httptest.NewServer(http.HandlerFunc(func(response http.ResponseWriter, _ *http.Request) {
		requests++
		_, _ = fmt.Fprintf(response, " request-%d ", requests)
	}))
	defer server.Close()

	status, body, _, latency, err := requestMeasurements(
		context.Background(),
		server.Client(),
		server.URL,
		true,
	)
	if err != nil {
		t.Fatal(err)
	}
	if requests != 2 {
		t.Fatalf("requests = %d, want proving request plus latency request", requests)
	}
	if status != http.StatusText(http.StatusOK) && status != "200 OK" {
		t.Fatalf("status = %q, want 200 OK", status)
	}
	if body != "request-1" {
		t.Fatalf("body = %q, want first proving response", body)
	}
	if latency == nil || *latency < 0 {
		t.Fatalf("latency = %v, want non-negative warm measurement", latency)
	}
}

func TestRequestMeasurementsDoesNotChangeProbeRequestCount(t *testing.T) {
	t.Parallel()

	requests := 0
	server := httptest.NewServer(http.HandlerFunc(func(response http.ResponseWriter, _ *http.Request) {
		requests++
		_, _ = response.Write([]byte("ok"))
	}))
	defer server.Close()

	_, _, _, latency, err := requestMeasurements(
		context.Background(),
		server.Client(),
		server.URL,
		false,
	)
	if err != nil {
		t.Fatal(err)
	}
	if requests != 1 {
		t.Fatalf("requests = %d, want existing single probe request", requests)
	}
	if latency != nil {
		t.Fatalf("latency = %v, want no UI latency from a plain probe", latency)
	}
}

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
