package main

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/url"
	"strings"
	"time"
)

type arrivalCacheEntry struct {
	data    []byte
	expires time.Time
}
type arrivalFlight struct {
	done chan struct{}
	data []byte
	err  error
}

var errArrivalsBusy = errors.New("arrivals busy")

func (s *BondiServer) arrivals(ctx context.Context, code string) ([]byte, error) {
	s.arrivalsMu.Lock()
	if entry, ok := s.arrivalsCache[code]; ok && time.Now().Before(entry.expires) {
		s.arrivalsMu.Unlock()
		return entry.data, nil
	}
	if flight, ok := s.arrivalsFlights[code]; ok {
		s.arrivalsMu.Unlock()
		select {
		case <-ctx.Done():
			return nil, ctx.Err()
		case <-flight.done:
			return flight.data, flight.err
		}
	}
	select {
	case s.arrivalsSlots <- struct{}{}:
	default:
		s.arrivalsMu.Unlock()
		return nil, errArrivalsBusy
	}
	flight := &arrivalFlight{done: make(chan struct{})}
	s.arrivalsFlights[code] = flight
	s.arrivalsMu.Unlock()
	raw, err := s.makeRequest("cmd=proximos_arribos", url.Values{
		"codigo": {code}, "conf": {"cbaciudad"}, "onlygps": {"true"}, "show80min": {"false"},
	}, false)
	var payload struct {
		Arrivals json.RawMessage `json:"proximos_arribos"`
		Error    json.RawMessage `json:"err"`
	}
	var entries []json.RawMessage
	if err == nil && (json.Unmarshal(raw, &payload) != nil || len(payload.Arrivals) == 0 || string(payload.Arrivals) == "null" || json.Unmarshal(payload.Arrivals, &entries) != nil) {
		err = errors.New("invalid arrivals response")
	}
	if err == nil && len(payload.Error) > 0 {
		switch string(payload.Error) {
		case "0", "\"0\"", "\"\"", "false", "null":
		default:
			err = errors.New("upstream arrivals error")
		}
	}
	s.arrivalsMu.Lock()
	if err == nil {
		storeResponse(s.arrivalsCache, code, raw, 15*time.Second, 8*1024*1024)
	}
	flight.data, flight.err = raw, err
	delete(s.arrivalsFlights, code)
	close(flight.done)
	<-s.arrivalsSlots
	s.arrivalsMu.Unlock()
	return raw, err
}

func (s *BondiServer) handleArrivals(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "GET required", 405)
		return
	}
	code := strings.TrimSpace(r.URL.Query().Get("stop"))
	if code == "" || len(code) > 100 {
		http.Error(w, "Invalid stop", 400)
		return
	}
	raw, err := s.arrivals(r.Context(), code)
	if errors.Is(err, errArrivalsBusy) {
		w.Header().Set("Retry-After", "2")
		http.Error(w, "Try again shortly", 503)
		return
	}
	if err != nil {
		http.Error(w, "Arrivals unavailable", 502)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	w.Header().Set("Cache-Control", "no-store")
	w.Write(raw)
}
