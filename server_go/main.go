package main

import (
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"net/url"
	"strings"
	"sync"
	"time"
)

const (
	baseURL   = "https://micronauta4.dnsalias.net"
	userAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36"
	port      = ":3001"
)

type BondiServer struct {
	mu           sync.RWMutex
	client       *http.Client
	cookie       string
	cookieExpiry time.Time
	lineasCache  []byte
	lineasTime   time.Time
	trazaCache   map[string][]byte
}

func NewBondiServer() *BondiServer {
	return &BondiServer{
		client: &http.Client{
			Timeout: 10 * time.Second,
		},
		trazaCache: make(map[string][]byte),
	}
}

// Ensure active session with micronauta backend
func (s *BondiServer) ensureSession() (string, error) {
	s.mu.Lock()
	defer s.mu.Unlock()

	now := time.Now()
	if s.cookie != "" && now.Before(s.cookieExpiry) {
		return s.cookie, nil
	}

	log.Println("🔄 [Go Server] Inicializando nueva sesión con el servidor municipal...")
	req, err := http.NewRequest("GET", baseURL+"/usuario/urbano.php?conf=cbaciudad", nil)
	if err != nil {
		return "", err
	}
	req.Header.Set("User-Agent", userAgent)

	resp, err := s.client.Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()

	for _, c := range resp.Cookies() {
		if c.Name == "PHPSESSID" {
			s.cookie = fmt.Sprintf("PHPSESSID=%s", c.Value)
			s.cookieExpiry = now.Add(20 * time.Minute)
			log.Printf("✅ [Go Server] Sesión establecida: %s...", c.Value[:8])
			return s.cookie, nil
		}
	}

	return s.cookie, nil
}

// Request to TuBondi backend with auto-retry on 408
func (s *BondiServer) makeRequest(endpoint string, bodyParams url.Values, isGet bool) ([]byte, error) {
	cookie, err := s.ensureSession()
	if err != nil {
		return nil, err
	}

	reqURL := baseURL + "/usuario/urbano2_cmd.php?" + endpoint
	var req *http.Request

	if isGet || bodyParams == nil {
		req, err = http.NewRequest("GET", reqURL, nil)
	} else {

		req, err = http.NewRequest("POST", reqURL, strings.NewReader(bodyParams.Encode()))
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
		log.Println("⚠️ [Go Server] Sesión expirada (408). Renovando sesión...")
		s.mu.Lock()
		s.cookie = ""
		s.mu.Unlock()
		s.ensureSession()
		return s.makeRequest(endpoint, bodyParams, isGet)
	}

	return io.ReadAll(resp.Body)
}

// Middleware CORS
func enableCORS(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Access-Control-Allow-Origin", "*")
		w.Header().Set("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
		w.Header().Set("Access-Control-Allow-Headers", "Content-Type, Authorization")
		if r.Method == "OPTIONS" {
			w.WriteHeader(http.StatusOK)
			return
		}
		next(w, r)
	}
}

// Handler: /api/lineas
func (s *BondiServer) handleLineas(w http.ResponseWriter, r *http.Request) {
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
	raw, err := s.makeRequest("cmd=lineasyrutas", params, false)
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

	if err := json.Unmarshal(raw, &original); err == nil {
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
			rutas := make([]CleanRuta, 0, len(l.Rutas))
			for _, r := range l.Rutas {
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

	w.Header().Set("Content-Type", "application/json")
	w.Write(raw)
}

// Handler: /api/coches
func (s *BondiServer) handleCoches(w http.ResponseWriter, r *http.Request) {
	q := r.URL.Query()
	ruta := q.Get("ruta")
	cliente := q.Get("cliente")
	linea := q.Get("linea")

	if ruta == "" {
		http.Error(w, "Parametro ruta requerido", http.StatusBadRequest)
		return
	}

	params := url.Values{}
	params.Set("ruta", ruta)
	params.Set("coche", "0")
	params.Set("cliente", cliente)
	params.Set("parada_seleccionada", "0")
	params.Set("conf", "cbaciudad")

	raw, err := s.makeRequest("cmd=consultacocheporruta", params, false)
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

	if err := json.Unmarshal(raw, &parsed); err == nil {
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

	w.Header().Set("Content-Type", "application/json")
	w.Write(raw)
}

// Handler: /api/traza
func (s *BondiServer) handleTraza(w http.ResponseWriter, r *http.Request) {
	q := r.URL.Query()
	linea := q.Get("linea")
	ruta := q.Get("ruta")
	cliente := q.Get("cliente")

	cacheKey := fmt.Sprintf("%s_%s_%s", linea, ruta, cliente)
	s.mu.RLock()
	if cached, ok := s.trazaCache[cacheKey]; ok {
		s.mu.RUnlock()
		w.Header().Set("Content-Type", "application/json")
		w.Write(cached)
		return
	}
	s.mu.RUnlock()

	raw, err := s.makeRequest("cmd=seleccionatraza", url.Values{
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

	if err := json.Unmarshal(raw, &parsed); err == nil {
		type Parada struct {
			Codigo string  `json:"codigo"`
			Nombre string  `json:"nombre"`
			Lat    float64 `json:"lat"`
			Lon    float64 `json:"lon"`
		}

		puntos := make([][]float64, 0, len(parsed.Traza))
		for _, pt := range parsed.Traza {
			if len(pt) >= 2 {
				// Convert to [lat, lon]
				puntos = append(puntos, []float64{pt[1], pt[0]})
			}
		}

		paradas := make([]Parada, 0, len(parsed.Indicaciones))
		for _, ind := range parsed.Indicaciones {
			paradas = append(paradas, Parada{
				Codigo: ind.Codigo,
				Nombre: ind.Nombre,
				Lat:    float64(ind.Lat),
				Lon:    float64(ind.Lon),
			})
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
		s.trazaCache[cacheKey] = out
		s.mu.Unlock()

		w.Header().Set("Content-Type", "application/json")
		w.Write(out)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	w.Write(raw)
}

func main() {
	server := NewBondiServer()
	http.HandleFunc("/api/places", enableCORS(handlePlaces))

	http.HandleFunc("/api/lineas", enableCORS(server.handleLineas))
	http.HandleFunc("/api/coches", enableCORS(server.handleCoches))
	http.HandleFunc("/api/traza", enableCORS(server.handleTraza))
	http.HandleFunc("/api/arrivals", enableCORS(server.handleArrivals))
	http.HandleFunc("/api/health", enableCORS(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.Write([]byte(`{"status":"ok","engine":"golang"}`))
	}))

	// Serve built client if present
	fs := http.FileServer(http.Dir("./client/dist"))
	http.Handle("/", fs)

	log.Printf("🚀 [Go Server] Servidor de alto rendimiento corriendo en http://localhost%s\n", port)
	if err := http.ListenAndServe(port, nil); err != nil {
		log.Fatalf("Error arrancando servidor: %v", err)
	}
}
