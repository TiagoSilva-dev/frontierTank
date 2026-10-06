package main

import (
	"errors"
	"fmt"
	"net"
	"os"
	"strconv"
	"strings"
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
	// Steam Web API (publisher key, partner.steam-api.com): login by ticket and the Steam
	// Wallet purchases. Without STEAM_APP_ID and STEAM_WEB_API_KEY, Steam is off.
	Steam SteamClient
	// Stripe (sk_... key): real-money purchases on the web and mobile builds, card and Pix.
	// Without STRIPE_API_KEY, Stripe is off; without STRIPE_WEBHOOK_SECRET the webhook
	// refuses everything and only the polling (store/status, reconcile) delivers.
	Stripe StripeClient
	// The admin panel (/admin/): off unless ADMIN_ENABLED=1.
	Admin AdminConfig
}

// AdminConfig: the staff panel served by this API (admin.go).
type AdminConfig struct {
	Enabled bool
	// The first owner, created when no staff account exists yet (the password must be
	// changed at the first login).
	BootstrapUser     string
	BootstrapPassword string
	// Every account needs a TOTP second factor (the first login enrols it).
	Require2FA bool
	// A session ends after SessionHours, or after IdleMinutes without a request.
	SessionHours int
	IdleMinutes  int
	// Only these addresses reach the panel (empty = any). Behind a proxy the address is
	// whatever X-Forwarded-For says (TRUST_PROXY), so it is only as good as the proxy.
	AllowIPs []*net.IPNet
	// "1" or "0" forces the Secure flag of the session cookie; "" follows the request.
	SecureCookie string
	// How long the record of what the staff did is kept (days; 0 keeps it forever).
	AuditDays int
	// Name shown by the authenticator app.
	Issuer string
}

// parseAllowList reads "10.0.0.0/8, 203.0.113.7": a bare address is a /32 or /128.
func parseAllowList(text string) ([]*net.IPNet, error) {
	var list []*net.IPNet
	for _, part := range strings.Split(text, ",") {
		part = strings.TrimSpace(part)
		if part == "" {
			continue
		}
		if !strings.Contains(part, "/") {
			if ip := net.ParseIP(part); ip != nil && ip.To4() != nil {
				part += "/32"
			} else {
				part += "/128"
			}
		}
		_, network, err := net.ParseCIDR(part)
		if err != nil {
			return nil, fmt.Errorf("ADMIN_ALLOW_IPS: %q is not an address or a network", part)
		}
		list = append(list, network)
	}
	return list, nil
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
		Retention:        Retention{AuditDays: envInt("AUDIT_RETENTION_DAYS", 365), ChatDays: envInt("CHAT_RETENTION_DAYS", 90), AccessDays: envInt("ACCESS_LOG_DAYS", 183), ReportDays: envInt("REPORT_RETENTION_DAYS", 180), OrderDays: envInt("ORDER_RETENTION_DAYS", 1826), ChallengeDays: envInt("CHALLENGE_RETENTION_DAYS", 30)},
	}
	appID, _ := strconv.ParseUint(env("STEAM_APP_ID", "0"), 10, 32)
	cfg.Steam = SteamClient{
		Base:     env("STEAM_WEB_API", "https://partner.steam-api.com"),
		Key:      env("STEAM_WEB_API_KEY", ""),
		AppID:    uint32(appID),
		Identity: env("STEAM_IDENTITY", "frontiertank"),
		Sandbox:  env("STEAM_MICROTXN_SANDBOX", "") == "1",
	}
	cfg.Stripe = StripeClient{
		Base:          env("STRIPE_API_BASE", ""),
		Key:           env("STRIPE_API_KEY", ""),
		WebhookSecret: env("STRIPE_WEBHOOK_SECRET", ""),
		ReturnURL:     env("STORE_RETURN_URL", ""),
	}
	allow, err := parseAllowList(env("ADMIN_ALLOW_IPS", ""))
	if err != nil {
		return cfg, err
	}
	cfg.Admin = AdminConfig{
		Enabled:           env("ADMIN_ENABLED", "") == "1",
		BootstrapUser:     env("ADMIN_BOOTSTRAP_USER", ""),
		BootstrapPassword: env("ADMIN_BOOTSTRAP_PASSWORD", ""),
		Require2FA:        env("ADMIN_REQUIRE_2FA", "1") != "0",
		SessionHours:      envInt("ADMIN_SESSION_HOURS", 12),
		IdleMinutes:       envInt("ADMIN_IDLE_MINUTES", 120),
		AllowIPs:          allow,
		SecureCookie:      env("ADMIN_SECURE_COOKIE", ""),
		AuditDays:         envInt("ADMIN_AUDIT_DAYS", 1826),
		Issuer:            env("ADMIN_ISSUER", "Gustfire"),
	}
	if cfg.Admin.SessionHours <= 0 || cfg.Admin.IdleMinutes <= 0 {
		return cfg, errors.New("ADMIN_SESSION_HOURS and ADMIN_IDLE_MINUTES must be positive")
	}
	if len(cfg.InternalKey) < 16 {
		return cfg, errors.New("INTERNAL_KEY must have at least 16 characters")
	}
	if cfg.PBKDF2Iterations < 1000 {
		return cfg, errors.New("PBKDF2_ITERATIONS is too low")
	}
	return cfg, nil
}
