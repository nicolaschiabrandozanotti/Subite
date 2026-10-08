package main

import (
	"context"
	"errors"
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

func TestUpstreamCancellationReleasesCapacity(t *testing.T) {
	for _, session := range []bool{false, true} {
		t.Run(map[bool]string{false: "request", true: "session"}[session], func(t *testing.T) {
			s := NewBondiServer()
			if !session {
				s.cookie, s.cookieExpiry = "test", time.Now().Add(time.Hour)
			}
			started := make(chan struct{})
			s.client.Transport = arrivalsTransport(func(r *http.Request) (*http.Response, error) {
				close(started)
				<-r.Context().Done()
				return nil, r.Context().Err()
			})
			ctx, cancel := context.WithCancel(context.Background())
			defer cancel()
			done := make(chan error, 1)
			go func() { _, err := s.arrivals(ctx, "123"); done <- err }()
			select {
			case <-started:
			case <-time.After(time.Second):
				t.Fatal("upstream did not start")
			}
			cancel()
			select {
			case err := <-done:
				if !errors.Is(err, context.Canceled) {
					t.Fatalf("got %v", err)
				}
			case <-time.After(time.Second):
				t.Fatal("upstream ignored cancellation")
			}
			if len(s.upstreamSlots) != 0 || len(s.arrivalsSlots) != 0 || len(s.arrivalsFlights) != 0 || len(s.arrivalsCache) != 0 {
				t.Fatal("cancelled work retained capacity or cached response")
			}
		})
	}
}

type observedWaitContext struct {
	context.Context
	waiting chan struct{}
	once    sync.Once
}

func (c *observedWaitContext) Done() <-chan struct{} {
	c.once.Do(func() { close(c.waiting) })
	return c.Context.Done()
}

func TestConnectedWaiterRetriesCancelledFlight(t *testing.T) {
	s := NewBondiServer()
	s.cookie, s.cookieExpiry = "test", time.Now().Add(time.Hour)
	flight := &arrivalFlight{done: make(chan struct{}), err: context.Canceled}
	s.arrivalsFlights["123"] = flight
	s.client.Transport = arrivalsTransport(func(*http.Request) (*http.Response, error) {
		return &http.Response{StatusCode: 200, Body: io.NopCloser(strings.NewReader(`{"proximos_arribos":[]}`)), Header: make(http.Header)}, nil
	})
	done := make(chan error, 1)
	ctx := &observedWaitContext{Context: context.Background(), waiting: make(chan struct{})}
	go func() { _, err := s.arrivals(ctx, "123"); done <- err }()
	select {
	case <-ctx.waiting:
	case <-time.After(time.Second):
		t.Fatal("waiter did not join flight")
	}
	// Removal and completion have the same ordering as a cancelled leader.
	s.arrivalsMu.Lock()
	delete(s.arrivalsFlights, "123")
	close(flight.done)
	s.arrivalsMu.Unlock()
	select {
	case err := <-done:
		if err != nil {
			t.Fatal(err)
		}
	case <-time.After(time.Second):
		t.Fatal("waiter failed to retry")
	}
}
