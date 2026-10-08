package main

import "time"

// The caller holds the cache's mutex. Bound bytes as well as entry count.
func storeResponse(cache map[string]arrivalCacheEntry, key string, data []byte, ttl time.Duration, maxBytes int) {
	now := time.Now()
	delete(cache, key)
	size := 0
	for k, entry := range cache {
		if !now.Before(entry.expires) {
			delete(cache, k)
		} else {
			size += len(entry.data)
		}
	}
	if len(data) > maxBytes {
		return
	}
	for len(cache) >= 256 || size+len(data) > maxBytes {
		var oldest string
		var expiry time.Time
		for k, entry := range cache {
			if expiry.IsZero() || entry.expires.Before(expiry) {
				oldest, expiry = k, entry.expires
			}
		}
		size -= len(cache[oldest].data)
		delete(cache, oldest)
	}
	cache[key] = arrivalCacheEntry{data, now.Add(ttl)}
}
