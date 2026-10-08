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

func TestFullRouteUsesStopCatalogAndStringCoordinates(t *testing.T) {
	s := NewBondiServer()
	s.cookie = "test"
	s.cookieExpiry = time.Now().Add(time.Hour)
	s.client.Transport = arrivalsTransport(func(r *http.Request) (*http.Response, error) {
		r.ParseForm()
		if r.URL.Query().Get("cmd") != "seleccionatraza" || r.Form.Get("ruta") != "211" {
			t.Fatal("wrong route command")
		}
		body := `{"color":"#D93062","traza":[[-64.2,-31.4]],"paradas":[{"codigo":"A","parada_nombre":"Primera","lat":"-31.4","lon":"-64.2"},{"codigo":"B","parada_nombre":"Segunda","lat":-31.41,"lon":-64.21}]}`
		return &http.Response{StatusCode: 200, Header: make(http.Header), Body: io.NopCloser(strings.NewReader(body))}, nil
	})
	response := httptest.NewRecorder()
	s.handleTraza(response, httptest.NewRequest("GET", "/api/traza?linea=70&ruta=211&cliente=422", nil))
	var data struct {
		Stops []struct {
			Code string  `json:"codigo"`
			Lat  float64 `json:"lat"`
		} `json:"paradas"`
	}
	if err := json.Unmarshal(response.Body.Bytes(), &data); err != nil {
		t.Fatal(err)
	}
	if len(data.Stops) != 2 || data.Stops[0].Lat != -31.4 || data.Stops[1].Code != "B" {
		t.Fatal(response.Body.String())
	}
}
