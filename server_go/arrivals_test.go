package main

import (
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

type arrivalsTransport func(*http.Request) (*http.Response, error)

func (f arrivalsTransport) RoundTrip(r *http.Request) (*http.Response, error) { return f(r) }
func TestArrivalsUsesSelectedStop(t *testing.T) {
	s := NewBondiServer()
	s.cookie = "test"
	s.cookieExpiry = time.Now().Add(time.Hour)
	s.client.Transport = arrivalsTransport(func(r *http.Request) (*http.Response, error) {
		r.ParseForm()
		if r.URL.Query().Get("cmd") != "proximos_arribos" || r.Form.Get("codigo") != "123" || r.Form.Get("onlygps") != "true" {
			t.Fatal("incorrect upstream request")
		}
		return &http.Response{StatusCode: 200, Body: io.NopCloser(strings.NewReader(`{"proximos_arribos":[]}`)), Header: make(http.Header)}, nil
	})
	response := httptest.NewRecorder()
	s.handleArrivals(response, httptest.NewRequest("GET", "/api/arrivals?stop=123", nil))
	if response.Code != 200 || !strings.Contains(response.Body.String(), "proximos_arribos") {
		t.Fatal("response not preserved")
	}
}
func TestArrivalsRejectsMissingStop(t *testing.T) {
	response := httptest.NewRecorder()
	NewBondiServer().handleArrivals(response, httptest.NewRequest("GET", "/api/arrivals", nil))
	if response.Code != 400 {
		t.Fatal(response.Code)
	}
}
func TestMissingHeightFallsBackWithoutClaimingExactCoordinates(t *testing.T) {
	previous := placeClient
	defer func() { placeClient = previous }()
	placeCache.Lock()
	placeCache.entries = make(map[string]placeCacheEntry)
	placeCache.Unlock()
	placeClient = &http.Client{Transport: arrivalsTransport(func(r *http.Request) (*http.Response, error) {
		body := `{"features":[]}`
		if r.URL.Host == "apis.datos.gob.ar" {
			body = `{"direcciones":[{"nomenclatura":"NEVADO 1054, Córdoba","calle":{"id":"123","nombre":"NEVADO"},"ubicacion":{"lat":null,"lon":null}}]}`
		}
		if r.URL.Query().Get("q") == "nevado" {
			body = `{"features":[{"properties":{"osm_type":"W","osm_id":1,"name":"Nevado","type":"street","district":"Parque Capital","city":"Córdoba"},"geometry":{"coordinates":[-64.2165,-31.43527]}}]}`
		}
		return &http.Response{StatusCode: 200, Header: make(http.Header), Body: io.NopCloser(strings.NewReader(body))}, nil
	})}
	response := httptest.NewRecorder()
	handlePlaces(response, httptest.NewRequest("GET", "/api/places?q=Nevado%201054", nil))
	var data struct {
		Places []searchPlace `json:"places"`
	}
	if err := json.Unmarshal(response.Body.Bytes(), &data); err != nil {
		t.Fatal(err)
	}
	if response.Code != 200 || len(data.Places) != 2 {
		t.Fatalf("unexpected response %s", response.Body.String())
	}
	for _, p := range data.Places {
		if !p.NeedsMap || p.Lat == 0 || p.Lon == 0 {
			t.Fatal("unverified height must require map confirmation")
		}
	}
	if !strings.Contains(data.Places[1].Address, "Parque Capital") {
		t.Fatal("missing neighborhood")
	}
}
