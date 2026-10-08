package main

import (
	"compress/gzip"
	"net/http"
	"strings"
)

type gzipResponse struct {
	http.ResponseWriter
	writer *gzip.Writer
}

func (w gzipResponse) Write(body []byte) (int, error) { return w.writer.Write(body) }

// Compress large, static catalogs; live arrivals keep their no-store response.
func compressCatalogs(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/api/lineas" && r.URL.Path != "/api/traza" {
			next.ServeHTTP(w, r)
			return
		}
		w.Header().Add("Vary", "Accept-Encoding")
		accepts := false
		for _, encoding := range strings.Split(r.Header.Get("Accept-Encoding"), ",") {
			if strings.TrimSpace(encoding) == "gzip" {
				accepts = true
			}
		}
		if !accepts {
			next.ServeHTTP(w, r)
			return
		}
		writer, _ := gzip.NewWriterLevel(w, gzip.BestSpeed)
		defer writer.Close()
		w.Header().Set("Content-Encoding", "gzip")
		next.ServeHTTP(gzipResponse{w, writer}, r)
	})
}
