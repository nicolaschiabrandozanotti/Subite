package main

import (
	"encoding/json"
	"net/http"
	"net/url"
	"strings"
)

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
	raw, err := s.makeRequest("cmd=proximos_arribos", url.Values{
		"codigo": {code}, "conf": {"cbaciudad"}, "onlygps": {"true"}, "show80min": {"false"},
	}, false)
	if err != nil || !json.Valid(raw) {
		http.Error(w, "Arrivals unavailable", 502)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	w.Header().Set("Cache-Control", "no-store")
	w.Write(raw)
}
