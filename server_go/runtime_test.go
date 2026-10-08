package main

import (
	"context"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"
)

func TestThirtyUsersShareArrivalsAndRefreshExpiredCache(t *testing.T) {
	s := NewBondiServer()
	s.cookie, s.cookieExpiry = "test", time.Now().Add(time.Hour)
	var calls atomic.Int32
	s.client.Transport = arrivalsTransport(func(*http.Request) (*http.Response, error) {
		calls.Add(1)
		time.Sleep(20 * time.Millisecond)
		return &http.Response{StatusCode: 200, Body: io.NopCloser(strings.NewReader(`{"proximos_arribos":[]}`)), Header: make(http.Header)}, nil
	})
	var wg sync.WaitGroup
	start := make(chan struct{})
	for i := 0; i < 30; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			<-start
			if _, err := s.arrivals(context.Background(), "123"); err != nil {
				t.Error(err)
			}
		}()
	}
	close(start)
	wg.Wait()
	if calls.Load() != 1 {
		t.Fatalf("30 users made %d upstream calls", calls.Load())
	}
	s.arrivalsMu.Lock()
	s.arrivalsCache["123"] = arrivalCacheEntry{expires: time.Now().Add(-time.Second)}
	s.arrivalsMu.Unlock()
	if _, err := s.arrivals(context.Background(), "123"); err != nil {
		t.Fatal(err)
	}
	if calls.Load() != 2 {
		t.Fatal("expired cache did not refresh")
	}
}

func TestInvalidArrivalsAreNotCached(t *testing.T) {
	s := NewBondiServer()
	s.cookie, s.cookieExpiry = "test", time.Now().Add(time.Hour)
	s.client.Transport = arrivalsTransport(func(*http.Request) (*http.Response, error) {
		return &http.Response{StatusCode: 200, Body: io.NopCloser(strings.NewReader(`{"error":"unavailable"}`)), Header: make(http.Header)}, nil
	})
	if _, err := s.arrivals(context.Background(), "123"); err == nil {
		t.Fatal("invalid response accepted")
	}
	if len(s.arrivalsCache) != 0 {
		t.Fatal("error cached")
	}
}

func TestHealthDoesNotNeedTransport(t *testing.T) {
	s := NewBondiServer()
	s.client.Transport = arrivalsTransport(func(*http.Request) (*http.Response, error) { t.Fatal("health queried upstream"); return nil, nil })
	response := httptest.NewRecorder()
	newHandler(s).ServeHTTP(response, httptest.NewRequest("GET", "/api/health", nil))
	if response.Code != 200 {
		t.Fatal(response.Code)
	}
}

func TestPortValidation(t *testing.T) {
	for _, value := range []string{"0", "65536", "invalid", "-1"} {
		if _, err := listenAddress(value); err == nil {
			t.Fatal(value)
		}
	}
	if addr, err := listenAddress(""); err != nil || addr != ":3001" {
		t.Fatal(addr, err)
	}
	if addr, err := listenAddress("8080"); err != nil || addr != ":8080" {
		t.Fatal(addr, err)
	}
}
