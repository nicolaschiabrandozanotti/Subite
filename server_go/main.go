package main

import (
	"context"
	"encoding/json"
	"fmt"
	"hash/fnv"
	"io"
	"log"
	"math"
	"net/http"
	"net/url"
	"strings"
	"sync"
	"time"
)

const (
	baseURL   = "https://micronauta4.dnsalias.net"
	userAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36"
)

type BondiServer struct {
	mu              sync.RWMutex
	client          *http.Client
	cookie          string
	cookieExpiry    time.Time
	lineasCache     []byte
	lineasTime      time.Time
	trazaCache      map[string]arrivalCacheEntry
	lineasLoad      sync.Mutex
	trazaLoad       [16]sync.Mutex
	sessionLoad     sync.Mutex
	upstreamSlots   chan struct{}
	arrivalsMu      sync.Mutex
	arrivalsCache   map[string]arrivalCacheEntry
	arrivalsFlights map[string]*arrivalFlight
	arrivalsSlots   chan struct{}
}

func NewBondiServer() *BondiServer {
	return &BondiServer{
		client: &http.Client{
			Timeout: 10 * time.Second,
		},
		trazaCache:      make(map[string]arrivalCacheEntry),
		upstreamSlots:   make(chan struct{}, 16),
		arrivalsCache:   make(map[string]arrivalCacheEntry),
		arrivalsFlights: make(map[string]*arrivalFlight),
		arrivalsSlots:   make(chan struct{}, 8),
	}
}

// Ensure active session with micronauta backend
func (s *BondiServer) ensureSession(ctx context.Context) (string, error) {
	s.sessionLoad.Lock()
	defer s.sessionLoad.Unlock()

	if err := ctx.Err(); err != nil {
		return "", err
	}
	now := time.Now()
	s.mu.RLock()
	if s.cookie != "" && now.Before(s.cookieExpiry) {
		cookie := s.cookie
		s.mu.RUnlock()
		return cookie, nil
	}
	s.mu.RUnlock()

	log.Println("🔄 [Go Server] Inicializando nueva sesión con el servidor municipal...")
	req, err := http.NewRequestWithContext(ctx, "GET", baseURL+"/usuario/urbano.php?conf=cbaciudad", nil)
	if err != nil {
		return "", err
	}
	req.Header.Set("User-Agent", userAgent)

	resp, err := s.client.Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return "", fmt.Errorf("session status %d", resp.StatusCode)
	}

	for _, c := range resp.Cookies() {
		if c.Name == "PHPSESSID" {
			s.mu.Lock()
			s.cookie = fmt.Sprintf("PHPSESSID=%s", c.Value)
			s.cookieExpiry = now.Add(20 * time.Minute)
			cookie := s.cookie
			s.mu.Unlock()
			log.Print("Sesión del servicio de transporte establecida")
			return cookie, nil
		}
	}

	return "", fmt.Errorf("session cookie missing")
}

// Request to TuBondi backend with auto-retry on 408
func (s *BondiServer) makeRequest(ctx context.Context, endpoint string, bodyParams url.Values, isGet bool) ([]byte, error) {
	if err := ctx.Err(); err != nil {
		return nil, err
	}
	select {
	case s.upstreamSlots <- struct{}{}:
	default:
		return nil, errArrivalsBusy
	}
	defer func() { <-s.upstreamSlots }()
	return s.makeRequestAttempt(ctx, endpoint, bodyParams, isGet, true)
}

func (s *BondiServer) makeRequestAttempt(ctx context.Context, endpoint string, bodyParams url.Values, isGet, retry bool) ([]byte, error) {
	cookie, err := s.ensureSession(ctx)
	if err != nil {
		return nil, err
	}

	reqURL := baseURL + "/usuario/urbano2_cmd.php?" + endpoint
	var req *http.Request

	if isGet || bodyParams == nil {
		req, err = http.NewRequestWithContext(ctx, "GET", reqURL, nil)
	} else {

		req, err = http.NewRequestWithContext(ctx, "POST", reqURL, strings.NewReader(bodyParams.Encode()))
		req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	}
	if err != nil {
		return nil, err
	}

	req.Header.Set("User-Agent", userAgent)
	req.Header.Set("Referer", baseURL+"/usuario/urbano.php?conf=cbaciudad")
	req.Header.Set("Origin", baseURL)
	req.Header.Set("Cookie", cookie)

	resp, err := s.client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	if resp.StatusCode == 408 {
		if !retry {
			return nil, fmt.Errorf("upstream session unavailable")
		}
		log.Println("⚠️ [Go Server] Sesión expirada (408). Renovando sesión...")
		s.mu.Lock()
		if s.cookie == cookie {
			s.cookie = ""
		}
		s.mu.Unlock()
		resp.Body.Close()
		return s.makeRequestAttempt(ctx, endpoint, bodyParams, isGet, false)
	}
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return nil, fmt.Errorf("upstream status %d", resp.StatusCode)
	}

	raw, err := io.ReadAll(io.LimitReader(resp.Body, 8*1024*1024+1))
	if len(raw) > 8*1024*1024 {
		return nil, fmt.Errorf("upstream response too large")
	}
	return raw, err
}

// Middleware CORS
func enableCORS(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Access-Control-Allow-Origin", "*")
		w.Header().Set("Access-Control-Allow-Methods", "GET, OPTIONS")
		w.Header().Set("Access-Control-Allow-Headers", "Content-Type, Authorization")
		if r.Method == "OPTIONS" {
			w.WriteHeader(http.StatusOK)
			return
		}
		if r.Method != http.MethodGet {
			w.Header().Set("Allow", "GET, OPTIONS")
			http.Error(w, "GET required", 405)
			return
		}
		next(w, r)
	}
}

// Handler: /api/lineas
func (s *BondiServer) handleLineas(w http.ResponseWriter, r *http.Request) {
	s.lineasLoad.Lock()
	defer s.lineasLoad.Unlock()
	s.mu.RLock()
	if len(s.lineasCache) > 0 && time.Since(s.lineasTime) < 30*time.Minute {
		cached := s.lineasCache
		s.mu.RUnlock()
		w.Header().Set("Content-Type", "application/json")
		w.Write(cached)
		return
	}
	s.mu.RUnlock()

	params := url.Values{}
	params.Set("conf", "cbaciudad")
	raw, err := s.makeRequest(r.Context(), "cmd=lineasyrutas", params, false)
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}

	// Parse and reformat clean lines
	var original struct {
		Lineas []struct {
			LineaID     string `json:"linea_id"`
			LineaNombre string `json:"linea_nombre"`
			Grupo       string `json:"grupo"`
			Color       string `json:"color"`
			Cliente     int    `json:"cliente"`
			Rutas       []struct {
				RutaID     string `json:"ruta_id"`
				Sentido    string `json:"sentido"`
				RutaNombre string `json:"ruta_nombre"`
				Longitud   string `json:"longitud"`
			} `json:"rutas"`
		} `json:"lineas"`
		Clientes []struct {
			ID     int    `json:"id"`
			Nombre string `json:"nombre"`
			Color  string `json:"color"`
		} `json:"clientes"`
	}

	if err := json.Unmarshal(raw, &original); err == nil && len(original.Lineas) > 0 {
		clientMap := make(map[int]string)
		for _, c := range original.Clientes {
			clientMap[c.ID] = c.Nombre
		}

		type CleanRuta struct {
			ID       string `json:"id"`
			Sentido  string `json:"sentido"`
			Nombre   string `json:"nombre"`
			Longitud string `json:"longitud"`
		}
		type CleanLinea struct {
			ID            string      `json:"id"`
			Nombre        string      `json:"nombre"`
			Grupo         string      `json:"grupo"`
			Color         string      `json:"color"`
			ClienteID     int         `json:"clienteId"`
			ClienteNombre string      `json:"clienteNombre"`
			Rutas         []CleanRuta `json:"rutas"`
		}

		cleanLines := make([]CleanLinea, 0, len(original.Lineas))
		for _, l := range original.Lineas {
			if l.LineaID == "" || l.LineaNombre == "" {
				continue
			}
			rutas := make([]CleanRuta, 0, len(l.Rutas))
			for _, r := range l.Rutas {
				if r.RutaID == "" {
					continue
				}
				rutas = append(rutas, CleanRuta{
					ID:       r.RutaID,
					Sentido:  r.Sentido,
					Nombre:   r.RutaNombre,
					Longitud: r.Longitud,
				})
			}
			cleanLines = append(cleanLines, CleanLinea{
				ID:            l.LineaID,
				Nombre:        l.LineaNombre,
				Grupo:         l.Grupo,
				Color:         l.Color,
				ClienteID:     l.Cliente,
				ClienteNombre: clientMap[l.Cliente],
				Rutas:         rutas,
			})
		}

		if len(cleanLines) == 0 {
			http.Error(w, "Lines unavailable", http.StatusBadGateway)
			return
		}
		result := map[string]interface{}{
			"lineas":    cleanLines,
			"empresas":  original.Clientes,
			"timestamp": time.Now().UnixMilli(),
		}

		formatted, _ := json.Marshal(result)

		s.mu.Lock()
		s.lineasCache = formatted
		s.lineasTime = time.Now()
		s.mu.Unlock()

		w.Header().Set("Content-Type", "application/json")
		w.Write(formatted)
		return
	}

	http.Error(w, "Lines unavailable", http.StatusBadGateway)
}

// Handler: /api/coches
func (s *BondiServer) handleCoches(w http.ResponseWriter, r *http.Request) {
	q := r.URL.Query()
	ruta := q.Get("ruta")
	cliente := q.Get("cliente")
	linea := q.Get("linea")

	if ruta == "" || len(ruta) > 100 || len(cliente) > 100 || len(linea) > 100 {
		http.Error(w, "Parametro ruta requerido", http.StatusBadRequest)
		return
	}

	params := url.Values{}
	params.Set("ruta", ruta)
	params.Set("coche", "0")
	params.Set("cliente", cliente)
	params.Set("parada_seleccionada", "0")
	params.Set("conf", "cbaciudad")

	raw, err := s.makeRequest(r.Context(), "cmd=consultacocheporruta", params, false)
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}

	var parsed struct {
		Coches []struct {
			Coche     int     `json:"coche"`
			Linea     string  `json:"linea"`
			Sentido   string  `json:"sentido"`
			Lat       float64 `json:"lat"`
			Lon       float64 `json:"lon"`
			Curso     float64 `json:"curso"`
			Demora    string  `json:"demora"`
			DemoraMin float64 `json:"demora_minutos"`
			Rampa     int     `json:"rampa"`
			UltimaAct string  `json:"itinerario_fechayhora"`
		} `json:"coches"`
	}

	if err := json.Unmarshal(raw, &parsed); err == nil && parsed.Coches != nil {
		type CleanCoche struct {
			Coche     int     `json:"coche"`
			Linea     string  `json:"linea"`
			Sentido   string  `json:"sentido"`
			Lat       float64 `json:"lat"`
			Lon       float64 `json:"lon"`
			Curso     float64 `json:"curso"`
			Demora    string  `json:"demora"`
			Rampa     bool    `json:"rampa"`
			UltimaAct string  `json:"ultimaActualizacion"`
		}

		resCoches := make([]CleanCoche, 0, len(parsed.Coches))
		for _, c := range parsed.Coches {
			if c.Coche <= 0 || !validCoordinate(c.Lat, c.Lon) {
				continue
			}
			l := c.Linea
			if l == "" {
				l = linea
			}
			resCoches = append(resCoches, CleanCoche{
				Coche:     c.Coche,
				Linea:     l,
				Sentido:   c.Sentido,
				Lat:       c.Lat,
				Lon:       c.Lon,
				Curso:     c.Curso,
				Demora:    c.Demora,
				Rampa:     c.Rampa == 1,
				UltimaAct: c.UltimaAct,
			})
		}

		out, _ := json.Marshal(map[string]interface{}{
			"ruta":      ruta,
			"total":     len(resCoches),
			"coches":    resCoches,
			"timestamp": time.Now().UnixMilli(),
		})
		w.Header().Set("Content-Type", "application/json")
		w.Write(out)
		return
	}

	http.Error(w, "Vehicles unavailable", http.StatusBadGateway)
}

// Handler: /api/traza
func (s *BondiServer) handleTraza(w http.ResponseWriter, r *http.Request) {
	q := r.URL.Query()
	linea := q.Get("linea")
	ruta := q.Get("ruta")
	cliente := q.Get("cliente")
	if linea == "" || ruta == "" || cliente == "" || len(linea) > 100 || len(ruta) > 100 || len(cliente) > 100 {
		http.Error(w, "Invalid route", http.StatusBadRequest)
		return
	}
	cacheKey := url.Values{"linea": {linea}, "ruta": {ruta}, "cliente": {cliente}}.Encode()
	hash := fnv.New32a()
	hash.Write([]byte(cacheKey))
	load := &s.trazaLoad[hash.Sum32()%uint32(len(s.trazaLoad))]
	load.Lock()
	defer load.Unlock()
	s.mu.RLock()
	if cached, ok := s.trazaCache[cacheKey]; ok && time.Now().Before(cached.expires) {
		s.mu.RUnlock()
		w.Header().Set("Content-Type", "application/json")
		w.Write(cached.data)
		return
	}
	s.mu.RUnlock()

	raw, err := s.makeRequest(r.Context(), "cmd=seleccionatraza", url.Values{
		"ruta": {ruta}, "cliente_id": {cliente}, "conf": {"cbaciudad"},
	}, false)
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}

	var parsed struct {
		Color        string      `json:"color"`
		Traza        [][]float64 `json:"traza"`
		Indicaciones []struct {
			Codigo string     `json:"codigo"`
			Nombre string     `json:"parada_nombre"`
			Lat    coordinate `json:"lat"`
			Lon    coordinate `json:"lon"`
		} `json:"paradas"`
	}

	if err := json.Unmarshal(raw, &parsed); err == nil && len(parsed.Traza) > 0 && len(parsed.Indicaciones) > 0 {
		type Parada struct {
			Codigo string  `json:"codigo"`
			Nombre string  `json:"nombre"`
			Lat    float64 `json:"lat"`
			Lon    float64 `json:"lon"`
		}

		puntos := make([][]float64, 0, len(parsed.Traza))
		for _, pt := range parsed.Traza {
			if len(pt) >= 2 && validCoordinate(pt[1], pt[0]) {
				// Convert to [lat, lon]
				puntos = append(puntos, []float64{pt[1], pt[0]})
			}
		}

		paradas := make([]Parada, 0, len(parsed.Indicaciones))
		for _, ind := range parsed.Indicaciones {
			if ind.Codigo == "" || !validCoordinate(float64(ind.Lat), float64(ind.Lon)) {
				continue
			}
			paradas = append(paradas, Parada{
				Codigo: ind.Codigo,
				Nombre: ind.Nombre,
				Lat:    float64(ind.Lat),
				Lon:    float64(ind.Lon),
			})
		}

		if len(puntos) == 0 || len(paradas) == 0 {
			http.Error(w, "Route unavailable", http.StatusBadGateway)
			return
		}
		res := map[string]interface{}{
			"lineaId": linea,
			"rutaId":  ruta,
			"color":   parsed.Color,
			"puntos":  puntos,
			"paradas": paradas,
		}

		out, _ := json.Marshal(res)
		s.mu.Lock()
		storeResponse(s.trazaCache, cacheKey, out, 24*time.Hour, 16*1024*1024)
		s.mu.Unlock()

		w.Header().Set("Content-Type", "application/json")
		w.Write(out)
		return
	}

	http.Error(w, "Route unavailable", http.StatusBadGateway)
}

func validCoordinate(lat, lon float64) bool {
	return !math.IsNaN(lat) && !math.IsNaN(lon) && !math.IsInf(lat, 0) && !math.IsInf(lon, 0) && lat != 0 && lon != 0 && math.Abs(lat) <= 90 && math.Abs(lon) <= 180
}

func newHandler(server *BondiServer) http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("/api/places", enableCORS(handlePlaces))

	mux.HandleFunc("/api/lineas", enableCORS(server.handleLineas))
	mux.HandleFunc("/api/coches", enableCORS(server.handleCoches))
	mux.HandleFunc("/api/traza", enableCORS(server.handleTraza))
	mux.HandleFunc("/api/arrivals", enableCORS(server.handleArrivals))
	mux.HandleFunc("/api/health", enableCORS(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.Write([]byte(`{"status":"ok","engine":"golang","version":"1.0.4"}`))
	}))

	return compressCatalogs(mux)
}
