package main

import (
	"context"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"
)

func TestClientAddressTrustBoundary(t *testing.T) {
	trusted, err := trustedProxyRanges("10.0.0.0/24,2001:db8:1::/64")
	if err != nil {
		t.Fatal(err)
	}
	for _, tc := range []struct{ name, peer, forwarded, want string }{
		{"direct ignores forged header", "203.0.113.8:123", "192.0.2.1", "203.0.113.8"},
		{"trusted chain ignores forged prefix", "10.0.0.2:123", "192.0.2.99, 203.0.113.8, 10.0.0.3", "203.0.113.8"},
		{"malformed fails closed", "10.0.0.2:123", "203.0.113.8, garbage", "10.0.0.2"},
		{"ipv6 subnet", "[2001:db8:2::a]:123", "", "2001:db8:2::/64"},
		{"ipv4 mapped address", "[::ffff:203.0.113.8]:123", "192.0.2.1", "203.0.113.8"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			r := httptest.NewRequest("GET", "/api/lineas", nil)
			r.RemoteAddr = tc.peer
			r.Header.Set("X-Forwarded-For", tc.forwarded)
			if got := clientAddress(r, trusted); got != tc.want {
				t.Fatalf("got %s want %s", got, tc.want)
			}
		})
	}
	for _, raw := range []string{"*", "0.0.0.0/0", "::/0", "invalid"} {
		if _, err := trustedProxyRanges(raw); err == nil {
			t.Fatal("trusted invalid range", raw)
		}
	}
}

func TestRateLimitCannotBeBypassedWithHeadersAndHealthStaysAvailable(t *testing.T) {
	var calls int
	h := protectAPI(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { calls++; w.WriteHeader(200) }), nil)
	request := func(path, peer string, n int) *httptest.ResponseRecorder {
		r := httptest.NewRequest("GET", path, nil)
		r.RemoteAddr = peer
		r.Header.Set("X-Forwarded-For", fmt.Sprintf("192.0.2.%d", n))
		w := httptest.NewRecorder()
		h.ServeHTTP(w, r)
		return w
	}
	for i := 0; i < 30; i++ {
		if w := request("/api/places?q=cordoba", "203.0.113.1:5", i); w.Code != 200 {
			t.Fatal(w.Code)
		}
	}
	if w := request("/api/places?q=otra", "203.0.113.1:5", 31); w.Code != 429 || w.Header().Get("Retry-After") == "" {
		t.Fatal(w.Code)
	}
	if calls != 30 {
		t.Fatal("limited request reached handler")
	}
	if w := request("/api/places?q=cordoba", "203.0.113.2:5", 1); w.Code != 200 {
		t.Fatal("other client denied")
	}
	if w := request("/api/health", "203.0.113.1:5", 1); w.Code != 200 {
		t.Fatal("health denied")
	}
	for i := 30; i < 600; i++ {
		if w := request("/api/lineas", "203.0.113.1:5", i); w.Code != 200 {
			t.Fatal(w.Code, i)
		}
	}
	if w := request("/api/lineas", "203.0.113.1:5", 601); w.Code != 429 {
		t.Fatal(w.Code)
	}
}

func TestInFlightRequestsAreBoundedAndReleaseCapacity(t *testing.T) {
	started := make(chan struct{}, 64)
	release := make(chan struct{})
	h := protectAPI(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { started <- struct{}{}; <-release; w.WriteHeader(200) }), nil)
	var wg sync.WaitGroup
	for i := 0; i < 12; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			r := httptest.NewRequest("GET", "/api/lineas", nil)
			r.RemoteAddr = "203.0.113.1:5"
			h.ServeHTTP(httptest.NewRecorder(), r)
		}()
	}
	for i := 0; i < 12; i++ {
		select {
		case <-started:
		case <-time.After(time.Second):
			t.Fatal("request never started")
		}
	}
	w := httptest.NewRecorder()
	r := httptest.NewRequest("GET", "/api/lineas", nil)
	r.RemoteAddr = "203.0.113.1:5"
	h.ServeHTTP(w, r)
	if w.Code != 429 {
		t.Fatal("unbounded client concurrency", w.Code)
	}
	close(release)
	wg.Wait()
	w = httptest.NewRecorder()
	h.ServeHTTP(w, r)
	if w.Code != 200 {
		t.Fatal("capacity not released", w.Code)
	}
}

func TestOneClientCannotOccupyEveryArrivalSlot(t *testing.T) {
	started := make(chan struct{}, 4)
	release := make(chan struct{})
	h := protectAPI(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		started <- struct{}{}
		<-release
		w.WriteHeader(200)
	}), nil)
	var wg sync.WaitGroup
	for i := 0; i < 3; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			r := httptest.NewRequest("GET", "/api/arrivals?stop=123", nil)
			r.RemoteAddr = "203.0.113.1:5"
			h.ServeHTTP(httptest.NewRecorder(), r)
		}()
	}
	for i := 0; i < 3; i++ {
		select {
		case <-started:
		case <-time.After(time.Second):
			t.Fatal("request never started")
		}
	}
	w := httptest.NewRecorder()
	r := httptest.NewRequest("GET", "/api/arrivals?stop=other", nil)
	r.RemoteAddr = "203.0.113.1:5"
	h.ServeHTTP(w, r)
	if w.Code != 429 {
		t.Fatal("one address occupied all arrival slots", w.Code)
	}
	wg.Add(1)
	go func() {
		defer wg.Done()
		r := httptest.NewRequest("GET", "/api/arrivals?stop=other", nil)
		r.RemoteAddr = "203.0.113.2:5"
		h.ServeHTTP(httptest.NewRecorder(), r)
	}()
	select {
	case <-started:
	case <-time.After(time.Second):
		t.Fatal("another client was blocked")
	}
	close(release)
	wg.Wait()
}

func TestLoadMutexWaitHonorsCancellation(t *testing.T) {
	var lock loadMutex
	if err := lock.lock(context.Background()); err != nil {
		t.Fatal(err)
	}
	defer lock.unlock()
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	observed := &observedWaitContext{Context: ctx, waiting: make(chan struct{})}
	done := make(chan error, 1)
	go func() { done <- lock.lock(observed) }()
	<-observed.waiting
	cancel()
	select {
	case err := <-done:
		if !errors.Is(err, context.Canceled) {
			t.Fatal(err)
		}
	case <-time.After(time.Second):
		t.Fatal("cancelled waiter blocked")
	}
}

func TestRouteAliasesCannotFillCacheOrQueryProvider(t *testing.T) {
	s := transportServer(`{"traza":[[-64.2,-31.4]],"paradas":[{"codigo":"123","lat":-31.4,"lon":-64.2}]}`)
	seedRouteCatalog(s)
	original := s.client.Transport
	var calls atomic.Int32
	s.client.Transport = arrivalsTransport(func(r *http.Request) (*http.Response, error) { calls.Add(1); return original.RoundTrip(r) })
	for i := 0; i < 257; i++ {
		w := httptest.NewRecorder()
		s.handleTraza(w, httptest.NewRequest("GET", fmt.Sprintf("/api/traza?linea=alias%d&ruta=211&cliente=422", i), nil))
		if w.Code != 400 {
			t.Fatal(w.Code)
		}
	}
	if calls.Load() != 0 || len(s.trazaCache) != 0 {
		t.Fatal("arbitrary lines reached provider/cache")
	}
	w := httptest.NewRecorder()
	s.handleTraza(w, httptest.NewRequest("GET", "/api/traza?linea=70&ruta=211&cliente=422", nil))
	if w.Code != 200 || calls.Load() != 1 {
		t.Fatal(w.Code, calls.Load())
	}
}

func TestVehicleRequestsShareCacheWithoutMixingLabels(t *testing.T) {
	s := transportServer(`{"coches":[{"coche":1,"lat":-31.4,"lon":-64.2}]}`)
	original := s.client.Transport
	var calls atomic.Int32
	s.client.Transport = arrivalsTransport(func(r *http.Request) (*http.Response, error) { calls.Add(1); return original.RoundTrip(r) })
	var wg sync.WaitGroup
	for i := 0; i < 20; i++ {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			w := httptest.NewRecorder()
			s.handleCoches(w, httptest.NewRequest("GET", fmt.Sprintf("/api/coches?ruta=211&cliente=422&linea=L%d", i), nil))
			if w.Code != 200 || !strings.Contains(w.Body.String(), fmt.Sprintf(`"linea":"L%d"`, i)) {
				t.Error(w.Code, w.Body.String())
			}
		}(i)
	}
	wg.Wait()
	if calls.Load() != 1 {
		t.Fatal("duplicate upstream calls", calls.Load())
	}
}

func TestRouteCatalogIsLoadedBeforeValidation(t *testing.T) {
	s := transportServer("")
	var calls atomic.Int32
	s.client.Transport = arrivalsTransport(func(r *http.Request) (*http.Response, error) {
		calls.Add(1)
		body := `{"lineas":[{"linea_id":"70","linea_nombre":"70","cliente":422,"rutas":[{"ruta_id":"211"}]}]}`
		if r.URL.Query().Get("cmd") == "seleccionatraza" {
			body = `{"traza":[[-64.2,-31.4]],"paradas":[{"codigo":"123","lat":-31.4,"lon":-64.2}]}`
		}
		return &http.Response{StatusCode: 200, Header: make(http.Header), Body: io.NopCloser(strings.NewReader(body))}, nil
	})
	for _, client := range []string{"422", "999"} {
		w := httptest.NewRecorder()
		s.handleTraza(w, httptest.NewRequest("GET", "/api/traza?linea=70&ruta=211&cliente="+client, nil))
		want := 200
		if client == "999" {
			want = 400
		}
		if w.Code != want {
			t.Fatal(w.Code, w.Body.String())
		}
	}
	if calls.Load() != 2 {
		t.Fatal(calls.Load())
	}
}
