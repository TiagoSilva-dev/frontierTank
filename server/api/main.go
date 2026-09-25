// Frontier Tank API: accounts, sessions, profile storage, audit log, game server list,
// presence and the Leilão (items in custody and the game mail). Game logic (battles,
// crafting, loot, what can be sold) runs in the headless Godot game server, which is the
// only client of the internal API.
package main

import (
	"context"
	"errors"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"
)

func main() {
	logger := slog.New(slog.NewJSONHandler(os.Stdout, nil))
	cfg, err := loadConfig()
	if err != nil {
		logger.Error("config", "err", err)
		os.Exit(1)
	}
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()
	store, err := openStore(ctx, cfg.DatabaseURL)
	if err != nil {
		logger.Error("database", "err", err)
		os.Exit(1)
	}
	defer store.Close()
	if err := store.migrate(ctx); err != nil {
		logger.Error("migrate", "err", err)
		os.Exit(1)
	}
	api, err := newAPI(store, cfg, logger)
	if err != nil {
		logger.Error("api", "err", err)
		os.Exit(1)
	}
	servers := []*http.Server{
		{Addr: cfg.PublicAddr, Handler: api.publicRoutes(), ReadHeaderTimeout: 5 * time.Second, ReadTimeout: 15 * time.Second, WriteTimeout: 15 * time.Second},
		{Addr: cfg.InternalAddr, Handler: api.internalRoutes(), ReadHeaderTimeout: 5 * time.Second, ReadTimeout: 30 * time.Second, WriteTimeout: 30 * time.Second},
	}
	for _, server := range servers {
		go func(server *http.Server) {
			logger.Info("listening", "addr", server.Addr)
			if err := server.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
				logger.Error("listen", "addr", server.Addr, "err", err)
				stop()
			}
		}(server)
	}
	go func() {
		purge := time.NewTicker(10 * time.Minute)
		defer purge.Stop()
		// Leilão: listings whose time is over go back to the seller's mail.
		expire := time.NewTicker(time.Minute)
		defer expire.Stop()
		for {
			select {
			case <-ctx.Done():
				return
			case <-purge.C:
				if err := store.PurgeExpired(ctx); err != nil {
					logger.Warn("purge", "err", err)
				}
			case <-expire.C:
				if count, err := store.ExpireListings(ctx); err != nil {
					logger.Warn("expire listings", "err", err)
				} else if count > 0 {
					logger.Info("listings expired", "count", count)
				}
			}
		}
	}()
	<-ctx.Done()
	shutdown, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	for _, server := range servers {
		_ = server.Shutdown(shutdown)
	}
	logger.Info("stopped")
}
