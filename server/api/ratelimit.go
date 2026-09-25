package main

import (
	"sync"
	"time"
)

// RateLimiter allows `limit` events per key in a fixed window (per IP for login and
// register). In memory: enough for one API instance.
type RateLimiter struct {
	mu     sync.Mutex
	limit  int
	window time.Duration
	hits   map[string]*bucket
	now    func() time.Time
}

type bucket struct {
	start time.Time
	count int
}

func NewRateLimiter(limit int, window time.Duration) *RateLimiter {
	return &RateLimiter{limit: limit, window: window, hits: map[string]*bucket{}, now: time.Now}
}

func (l *RateLimiter) Allow(key string) bool {
	l.mu.Lock()
	defer l.mu.Unlock()
	now := l.now()
	b, ok := l.hits[key]
	if !ok || now.Sub(b.start) >= l.window {
		if len(l.hits) > 50000 {
			l.sweep(now)
		}
		l.hits[key] = &bucket{start: now, count: 1}
		return true
	}
	if b.count >= l.limit {
		return false
	}
	b.count++
	return true
}

func (l *RateLimiter) sweep(now time.Time) {
	for key, b := range l.hits {
		if now.Sub(b.start) >= l.window {
			delete(l.hits, key)
		}
	}
}
