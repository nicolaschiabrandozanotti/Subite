package main

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"regexp"
	"strings"
	"sync"
	"time"
)

func normalizePlaceQuery(q string) string {
	q = strings.ToLower(strings.TrimSpace(q))
	q = strings.NewReplacer("á", "a", "é", "e", "í", "i", "ó", "o", "ú", "u", "ü", "u").Replace(q)
	q = strings.Join(strings.Fields(q), " ")
	q = streetPrefix.ReplaceAllString(q, "")
	switch q {
	case "utn", "utn frc", "frc", "universidad tecnologica":
		return "Universidad Tecnológica Nacional"
	case "arquitectura", "universidad de arquitectura", "facultad de arquitectura", "faud", "faud unc", "facu de arquitectura", "facu arquitectura":
		return "Facultad Arquitectura"
	}
	return q
}

type placeCacheEntry struct {
	body    []byte
	expires time.Time
}

var placeCache = struct {
	sync.Mutex
	entries map[string]placeCacheEntry
}{entries: make(map[string]placeCacheEntry)}
var placeClient = &http.Client{Timeout: 5 * time.Second}
var addressHeight = regexp.MustCompile(`^(.*\D)\s+(\d+)\s*$`)
var streetPrefix = regexp.MustCompile(`^(avenida|av\.?|avda\.?|calle)\s+`)
var placeSlots = make(chan struct{}, 8)

type searchPlace struct {
	Street   string  `json:"-"`
	Code     string  `json:"codigo"`
	Name     string  `json:"nombre"`
	Address  string  `json:"direccion"`
	Lat      float64 `json:"lat"`
	Lon      float64 `json:"lon"`
	NeedsMap bool    `json:"requiresMap"`
	Source   string  `json:"source"`
}

func inCordoba(lat, lon float64) bool {
	return lat >= -31.55 && lat <= -31.25 && lon >= -64.35 && lon <= -64.05
}
func placeJSON(ctx context.Context, endpoint string, target interface{}) error {
	req, err := http.NewRequestWithContext(ctx, "GET", endpoint, nil)
	if err != nil {
		return err
	}
	req.Header.Set("User-Agent", "BondiCba-local-prototype/1.0")
	response, err := placeClient.Do(req)
	if err != nil {
		return err
	}
	defer response.Body.Close()
	if response.StatusCode != 200 {
		return fmt.Errorf("search provider status %d", response.StatusCode)
	}
	return json.NewDecoder(io.LimitReader(response.Body, 1048576)).Decode(target)
}
func photonPlaces(ctx context.Context, query, height string) ([]searchPlace, error) {
	params := url.Values{"q": {query}, "bbox": {"-64.35,-31.55,-64.05,-31.25"}, "limit": {"8"}, "lat": {"-31.4167"}, "lon": {"-64.1833"}}
	var data struct {
		Features []struct {
			Properties map[string]interface{} `json:"properties"`
			Geometry   struct {
				Coordinates []float64 `json:"coordinates"`
			} `json:"geometry"`
		} `json:"features"`
	}
	if err := placeJSON(ctx, "https://photon.komoot.io/api/?"+params.Encode(), &data); err != nil {
		return nil, err
	}
	places := []searchPlace{}
	for _, feature := range data.Features {
		coords := feature.Geometry.Coordinates
		if len(coords) < 2 || !inCordoba(coords[1], coords[0]) {
			continue
		}
		value := func(key string) string { text, _ := feature.Properties[key].(string); return text }
		name := value("name")
		if name == "" {
			name = value("street")
		}
		if name == "" {
			continue
		}
		address := strings.TrimSpace(value("street") + " " + value("housenumber"))
		for _, part := range []string{value("district"), value("city")} {
			if part != "" {
				if address != "" {
					address += ", "
				}
				address += part
			}
		}
		needsMap := value("type") == "street" || (height != "" && value("housenumber") != height)
		places = append(places, searchPlace{Code: fmt.Sprintf("poi_%v_%v", feature.Properties["osm_type"], feature.Properties["osm_id"]), Name: name, Address: address, Lat: coords[1], Lon: coords[0], NeedsMap: needsMap, Source: "Photon / OpenStreetMap"})
	}
	return places, nil
}
func georefPlaces(ctx context.Context, query string, seeds []searchPlace) ([]searchPlace, error) {
	params := url.Values{"direccion": {query}, "provincia": {"cordoba"}, "departamento": {"capital"}, "max": {"5"}}
	var data struct {
		Addresses []struct {
			Name   string `json:"nomenclatura"`
			Street struct {
				ID   string `json:"id"`
				Name string `json:"nombre"`
			} `json:"calle"`
			Location struct {
				Lat *float64 `json:"lat"`
				Lon *float64 `json:"lon"`
			} `json:"ubicacion"`
		} `json:"direcciones"`
	}
	if err := placeJSON(ctx, "https://apis.datos.gob.ar/georef/api/v2.0/direcciones?"+params.Encode(), &data); err != nil {
		return nil, err
	}
	results := []searchPlace{}
	for _, a := range data.Addresses {
		if a.Street.ID == "" || a.Name == "" {
			continue
		}
		// Georef documents these coordinates as approximate, so confirm on map.
		lat, lon := -31.4167, -64.1833
		if a.Location.Lat != nil && a.Location.Lon != nil {
			lat, lon = *a.Location.Lat, *a.Location.Lon
			if !inCordoba(lat, lon) {
				continue
			}
		} else {
			for _, seed := range seeds {
				if normalizePlaceQuery(seed.Name) == normalizePlaceQuery(a.Street.Name) {
					lat, lon = seed.Lat, seed.Lon
					break
				}
			}
		}
		results = append(results, searchPlace{Street: a.Street.Name, Code: "georef_" + a.Street.ID + "_" + query, Name: a.Name, Address: "Dirección reconocida · ubicación por confirmar", Lat: lat, Lon: lon, NeedsMap: true, Source: "Georef"})
	}
	return results, nil
}
func handlePlaces(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		w.Header().Set("Allow", "GET")
		http.Error(w, "Método no permitido", 405)
		return
	}
	query := normalizePlaceQuery(r.URL.Query().Get("q"))
	if len([]rune(query)) < 3 || len([]rune(query)) > 160 {
		http.Error(w, "Ingresá entre 3 y 160 caracteres", 400)
		return
	}
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	placeCache.Lock()
	cached, ok := placeCache.entries[query]
	placeCache.Unlock()
	if ok && time.Now().Before(cached.expires) {
		w.Write(cached.body)
		return
	}
	select {
	case placeSlots <- struct{}{}:
		defer func() { <-placeSlots }()
	default:
		w.Header().Set("Retry-After", "2")
		http.Error(w, "Buscador ocupado", 503)
		return
	}
	ctx, cancel := context.WithTimeout(r.Context(), 12*time.Second)
	defer cancel()
	height, street := "", query
	if parts := addressHeight.FindStringSubmatch(query); parts != nil {
		street, height = strings.TrimSpace(parts[1]), parts[2]
	}
	// Fetch both independent providers concurrently; POI-only searches stay on Photon.
	type result struct {
		places []searchPlace
		err    error
	}
	photon := make(chan result, 1)
	georef := make(chan result, 1)
	go func() { p, e := photonPlaces(ctx, query, height); photon <- result{p, e} }()
	if height != "" {
		go func() { p, e := georefPlaces(ctx, query, nil); georef <- result{p, e} }()
	} else {
		georef <- result{[]searchPlace{}, nil}
	}
	p, g := <-photon, <-georef
	if p.err != nil && (height == "" || g.err != nil) {
		http.Error(w, "Buscador no disponible", 502)
		return
	}
	if height != "" && len(p.places) == 0 {
		fallback, err := photonPlaces(ctx, street, height)
		if err == nil {
			for _, s := range fallback {
				if normalizePlaceQuery(s.Name) == normalizePlaceQuery(street) {
					s.NeedsMap = true
					s.Name = street + " " + height
					p.places = append(p.places, s)
				}
			}
		}
	}
	// Use street candidates only to center the confirmation map, never as height coordinates.
	for i := range g.places {
		if g.places[i].Lat == -31.4167 && g.places[i].Lon == -64.1833 && len(p.places) > 0 {
			for _, seed := range p.places {
				name := seed.Name
				if parts := addressHeight.FindStringSubmatch(name); parts != nil {
					name = parts[1]
				}
				if normalizePlaceQuery(name) == normalizePlaceQuery(g.places[i].Street) {
					g.places[i].Lat = seed.Lat
					g.places[i].Lon = seed.Lon
					break
				}
			}
		}
	}
	places := append(g.places, p.places...)
	// Do not store a temporary provider outage as a valid empty search.
	if len(places) == 0 && (p.err != nil || g.err != nil) {
		http.Error(w, "Buscador no disponible", 502)
		return
	}
	body, _ := json.Marshal(map[string]interface{}{"places": places, "source": "Georef + Photon / OpenStreetMap"})
	placeCache.Lock()
	if len(placeCache.entries) >= 256 {
		var oldest string
		var expiry time.Time
		for key, entry := range placeCache.entries {
			if expiry.IsZero() || entry.expires.Before(expiry) {
				oldest, expiry = key, entry.expires
			}
		}
		delete(placeCache.entries, oldest)
	}
	placeCache.entries[query] = placeCacheEntry{body, time.Now().Add(15 * time.Minute)}
	placeCache.Unlock()
	w.Write(body)
}
