package main

import (
	"compress/gzip"
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

func transportServer(body string) *BondiServer {
	s := NewBondiServer()
	s.cookie, s.cookieExpiry = "test", time.Now().Add(time.Hour)
	s.client.Transport = arrivalsTransport(func(*http.Request) (*http.Response, error) {
		return &http.Response{StatusCode: 200, Header: make(http.Header), Body: io.NopCloser(strings.NewReader(body))}, nil
	})
	return s
}

func TestInvalidCatalogsAreNotCached(t *testing.T) {
	s := transportServer(`{"err":1}`)
	for _, path := range []string{"/api/lineas", "/api/traza?linea=70&ruta=211&cliente=422", "/api/coches?ruta=211"} {
		response := httptest.NewRecorder()
		newHandler(s).ServeHTTP(response, httptest.NewRequest("GET", path, nil))
		if response.Code != 502 {
			t.Fatalf("%s accepted invalid data: %d", path, response.Code)
		}
	}
	if len(s.lineasCache) != 0 || len(s.trazaCache) != 0 {
		t.Fatal("invalid response cached")
	}
}

func TestArrivalsRejectsProviderErrorEvenWithEmptyList(t *testing.T) {
	s := transportServer(`{"err":1,"proximos_arribos":[]}`)
	if _, err := s.arrivals(context.Background(), "123"); err == nil {
		t.Fatal("provider error accepted")
	}
	if len(s.arrivalsCache) != 0 {
		t.Fatal("provider error cached")
	}
}

func TestArrivalsOverloadIsBounded(t *testing.T) {
	s := transportServer(`{"proximos_arribos":[]}`)
	for i := 0; i < cap(s.arrivalsSlots); i++ {
		s.arrivalsSlots <- struct{}{}
	}
	response := httptest.NewRecorder()
	s.handleArrivals(response, httptest.NewRequest("GET", "/api/arrivals?stop=123", nil))
	if response.Code != 503 || response.Header().Get("Retry-After") != "2" {
		t.Fatal(response.Code, response.Header())
	}
}

func TestRouteConcurrentLoadsAndExpiry(t *testing.T) {
	s := transportServer(`{"traza":[[-64.2,-31.4]],"paradas":[{"codigo":"123","lat":-31.4,"lon":-64.2}]}`)
	original := s.client.Transport
	var calls atomic.Int32
	s.client.Transport = arrivalsTransport(func(r *http.Request) (*http.Response, error) {
		calls.Add(1)
		time.Sleep(10 * time.Millisecond)
		return original.RoundTrip(r)
	})
	request := func() {
		response := httptest.NewRecorder()
		s.handleTraza(response, httptest.NewRequest("GET", "/api/traza?linea=70&ruta=211&cliente=422", nil))
		if response.Code != 200 {
			t.Error(response.Code)
		}
	}
	var wg sync.WaitGroup
	for i := 0; i < 20; i++ {
		wg.Add(1)
		go func() { defer wg.Done(); request() }()
	}
	wg.Wait()
	if calls.Load() != 1 {
		t.Fatal("duplicate route requests", calls.Load())
	}
	s.mu.Lock()
	for key, entry := range s.trazaCache {
		entry.expires = time.Now().Add(-time.Second)
		s.trazaCache[key] = entry
	}
	s.mu.Unlock()
	request()
	if calls.Load() != 2 {
		t.Fatal("route never refreshed")
	}
}

func TestCatalogCompressionPreservesJSON(t *testing.T) {
	s := NewBondiServer()
	s.lineasCache = []byte(`{"lineas":[{"id":"70"}]}`)
	s.lineasTime = time.Now()
	request := httptest.NewRequest("GET", "/api/lineas", nil)
	request.Header.Set("Accept-Encoding", "gzip")
	response := httptest.NewRecorder()
	newHandler(s).ServeHTTP(response, request)
	reader, err := gzip.NewReader(response.Body)
	if err != nil {
		t.Fatal(err)
	}
	defer reader.Close()
	body, err := io.ReadAll(reader)
	if err != nil || string(body) != string(s.lineasCache) || response.Header().Get("Content-Encoding") != "gzip" {
		t.Fatal(string(body), err)
	}
}

func TestResponseCacheBoundsBytesAndPurgesExpired(t *testing.T) {
	cache := map[string]arrivalCacheEntry{"expired": {[]byte("old"), time.Now().Add(-time.Second)}}
	storeResponse(cache, "one", []byte("123456"), time.Hour, 10)
	storeResponse(cache, "two", []byte("abcdef"), time.Hour, 10)
	if len(cache) != 1 || string(cache["two"].data) != "abcdef" {
		t.Fatal(cache)
	}
	storeResponse(cache, "oversized", []byte("12345678901"), time.Hour, 10)
	if _, ok := cache["oversized"]; ok {
		t.Fatal("oversized response cached")
	}
}

func BenchmarkCachedArrivals(b *testing.B) {
	s := NewBondiServer()
	s.arrivalsCache["123"] = arrivalCacheEntry{[]byte(`{"proximos_arribos":[]}`), time.Now().Add(time.Hour)}
	b.ReportAllocs()
	b.RunParallel(func(pb *testing.PB) {
		for pb.Next() {
			if _, err := s.arrivals(context.Background(), "123"); err != nil {
				b.Fatal(err)
			}
		}
	})
}

func TestSessionRetryStopsAfterSecond408(t *testing.T) {
	s := transportServer("")
	var calls int
	s.client.Transport = arrivalsTransport(func(r *http.Request) (*http.Response, error) {
		if r.URL.Query().Get("cmd") == "" {
			return &http.Response{StatusCode: 200, Header: http.Header{"Set-Cookie": {"PHPSESSID=renewed"}}, Body: io.NopCloser(strings.NewReader(""))}, nil
		}
		calls++
		return &http.Response{StatusCode: 408, Header: make(http.Header), Body: io.NopCloser(strings.NewReader(""))}, nil
	})
	if _, err := s.makeRequest(context.Background(), "cmd=test", nil, true); err == nil || calls != 2 {
		t.Fatal(err, calls)
	}
}
