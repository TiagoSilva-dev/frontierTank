package main

import (
	"errors"
	"os"
	"strconv"
	"time"
)

// Config comes from environment variables (docker-compose.yml sets them).
type Config struct {
	DatabaseURL string
	// Public API (login, server list) and the internal API used only by game servers.
	PublicAddr   string
	InternalAddr string
	InternalKey  string
	SessionTTL   time.Duration
	// PBKDF2-SHA256 rounds for passwords (OWASP 2023: 600 000). Tests lower it.
	PBKDF2Iterations int
	// Origin allowed by CORS for the web build ("*" in development).
	AllowOrigin string
	// Behind a reverse proxy the client IP comes from X-Forwarded-For.
	TrustProxy bool
	// Login/register attempts per IP per minute.
	AuthPerMinute int
	// Version of the Terms of Use and Privacy Policy (legal/*.md in the game). Changing
	// it makes every player accept the new texts before playing again.
	LegalVersion string
	// How long the audit log is kept (privacy policy); chat lines are kept less.
	Retention Retention
}

func env(key, fallback string) string {
	if value, ok := os.LookupEnv(key); ok && value != "" {
		return value
	}
	return fallback
}

func envInt(key string, fallback int) int {
	value, err := strconv.Atoi(env(key, ""))
	if err != nil {
		return fallback
	}
	return value
}

func loadConfig() (Config, error) {
	cfg := Config{
		DatabaseURL:      env("DATABASE_URL", "postgres://frontier:frontier@localhost:5432/frontier?sslmode=disable"),
		PublicAddr:       env("PUBLIC_ADDR", ":8080"),
		InternalAddr:     env("INTERNAL_ADDR", ":8081"),
		InternalKey:      env("INTERNAL_KEY", ""),
		SessionTTL:       time.Duration(envInt("SESSION_DAYS", 30)) * 24 * time.Hour,
		PBKDF2Iterations: envInt("PBKDF2_ITERATIONS", 600000),
		AllowOrigin:      env("ALLOW_ORIGIN", "*"),
		TrustProxy:       env("TRUST_PROXY", "") == "1",
		AuthPerMinute:    envInt("AUTH_PER_MINUTE", 20),
		LegalVersion:     env("LEGAL_VERSION", "2026-09-25"),
		Retention:        Retention{AuditDays: envInt("AUDIT_RETENTION_DAYS", 365), ChatDays: envInt("CHAT_RETENTION_DAYS", 90), AccessDays: envInt("ACCESS_LOG_DAYS", 183)},
	}
	if len(cfg.InternalKey) < 16 {
		return cfg, errors.New("INTERNAL_KEY must have at least 16 characters")
	}
	if cfg.PBKDF2Iterations < 1000 {
		return cfg, errors.New("PBKDF2_ITERATIONS is too low")
	}
	return cfg, nil
}
