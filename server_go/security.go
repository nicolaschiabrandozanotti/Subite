package main

import (
	"context"
	"fmt"
	"net"
	"net/http"
	"net/netip"
	"strconv"
	"strings"
	"sync"
	"time"
)

// Only long-running loads use this lock. Short in-memory operations keep Mutex.
type loadMutex struct {
	once sync.Once
	gate chan struct{}
}

func (m *loadMutex) lock(ctx context.Context) error {
	m.once.Do(func() { m.gate = make(chan struct{}, 1) })
	if err := ctx.Err(); err != nil {
		return err
	}
	select {
	case m.gate <- struct{}{}:
		if err := ctx.Err(); err != nil {
			m.unlock()
			return err
		}
		return nil
	case <-ctx.Done():
		return ctx.Err()
	}
}

func (m *loadMutex) unlock() { <-m.gate }

func trustedProxyRanges(value string) ([]netip.Prefix, error) {
	var ranges []netip.Prefix
	if strings.TrimSpace(value) == "" {
		return ranges, nil
	}
	for _, raw := range strings.Split(value, ",") {
		prefix, err := netip.ParsePrefix(strings.TrimSpace(raw))
		if err != nil {
			return nil, fmt.Errorf("TRUSTED_PROXY_CIDRS must contain IP ranges")
		}
		if prefix.Bits() == 0 {
			return nil, fmt.Errorf("TRUSTED_PROXY_CIDRS cannot trust the entire Internet")
		}
		ranges = append(ranges, prefix)
	}
	return ranges, nil
}

func clientAddress(r *http.Request, trusted []netip.Prefix) string {
	host, _, err := net.SplitHostPort(r.RemoteAddr)
	if err != nil {
		host = r.RemoteAddr
	}
	ip, err := netip.ParseAddr(host)
	if err != nil {
		return "unknown"
	}
	ip = ip.Unmap()
	isTrusted := func(addr netip.Addr) bool {
		for _, prefix := range trusted {
			if prefix.Contains(addr) {
				return true
			}
		}
		return false
	}
	// Walk from the socket towards the client, stopping at the first untrusted hop.
	if isTrusted(ip) {
		hops := strings.Split(strings.Join(r.Header.Values("X-Forwarded-For"), ","), ",")
		for i := len(hops) - 1; i >= 0 && isTrusted(ip); i-- {
			next, err := netip.ParseAddr(strings.TrimSpace(hops[i]))
			if err != nil {
				break
			}
			ip = next.Unmap()
		}
	}
	// IPv6 privacy addresses in the same /64 share a quota.
	if ip.Is6() {
		return netip.PrefixFrom(ip, 64).Masked().String()
	}
	return ip.String()
}

type requestBudget struct {
	start                      time.Time
	requests, searches, active int
	loads                      [4]int
}

func protectAPI(next http.Handler, trusted []netip.Prefix) http.Handler {
	var mu sync.Mutex
	clients := make(map[string]*requestBudget)
	active := 0
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("X-Content-Type-Options", "nosniff")
		w.Header().Set("Cache-Control", "no-store")
		if r.URL.Path == "/api/health" || r.Method == http.MethodOptions {
			next.ServeHTTP(w, r)
			return
		}
		now := time.Now()
		key := clientAddress(r, trusted)
		mu.Lock()
		budget := clients[key]
		if budget == nil {
			// Never evict an active quota to admit an attacker with another address.
			if len(clients) >= 4096 {
				for k, b := range clients {
					if b.active == 0 && now.Sub(b.start) >= time.Minute {
						delete(clients, k)
					}
				}
			}
			if len(clients) >= 4096 {
				mu.Unlock()
				w.Header().Set("Retry-After", "60")
				http.Error(w, "Try again shortly", 503)
				return
			}
			budget = &requestBudget{start: now}
			clients[key] = budget
		}
		if now.Sub(budget.start) >= time.Minute {
			budget.start = now
			budget.requests = 0
			budget.searches = 0
		}
		search := r.URL.Path == "/api/places"
		group, maxLoads := -1, 0
		switch r.URL.Path {
		case "/api/traza":
			group, maxLoads = 0, 6
		case "/api/arrivals":
			group, maxLoads = 1, 3
		case "/api/coches":
			group, maxLoads = 2, 3
		case "/api/places":
			group, maxLoads = 3, 2
		}
		if budget.requests >= 600 || (search && budget.searches >= 30) || budget.active >= 12 || (group >= 0 && budget.loads[group] >= maxLoads) {
			mu.Unlock()
			w.Header().Set("Access-Control-Allow-Origin", "*")
			w.Header().Set("Retry-After", "60")
			http.Error(w, "Too many requests", 429)
			return
		}
		if active >= 64 {
			mu.Unlock()
			w.Header().Set("Retry-After", "2")
			http.Error(w, "Try again shortly", 503)
			return
		}
		budget.requests++
		w.Header().Set("X-RateLimit-Remaining", strconv.Itoa(600-budget.requests))
		w.Header().Set("X-RateLimit-Reset", strconv.FormatInt(budget.start.Add(time.Minute).Unix(), 10))
		if search {
			budget.searches++
		}
		budget.active++
		if group >= 0 {
			budget.loads[group]++
		}
		active++
		mu.Unlock()
		defer func() {
			mu.Lock()
			budget.active--
			active--
			if group >= 0 {
				budget.loads[group]--
			}
			mu.Unlock()
		}()
		ctx, cancel := context.WithTimeout(r.Context(), 30*time.Second)
		defer cancel()
		next.ServeHTTP(w, r.WithContext(ctx))
	})
}
