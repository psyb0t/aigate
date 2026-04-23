package main

import (
	"context"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"

	"github.com/psyb0t/aichteeteapee/serbewr"
	"github.com/psyb0t/aichteeteapee/serbewr/middleware"
	_ "github.com/psyb0t/slog-configurator"

	"github.com/psyb0t/aigate/sdcpp/wrapper/internal/config"
	"github.com/psyb0t/aigate/sdcpp/wrapper/internal/process"
	"github.com/psyb0t/aigate/sdcpp/wrapper/internal/server"
)

func main() {
	cfg, err := config.Parse()
	if err != nil {
		slog.Error("config parse failed", "error", err)
		os.Exit(1)
	}

	reg, err := config.LoadRegistry(cfg.ModelsFile)
	if err != nil {
		slog.Error("registry load failed", "error", err)
		os.Exit(1)
	}

	slog.Info("loaded model registry",
		"models", reg.ModelNames(),
		"default", reg.DefaultModel,
		"prefix", cfg.ModelPrefix,
	)

	proc := process.NewManager(
		cfg.SDServerPath,
		cfg.SDServerAddress,
		cfg.ExtraArgs,
		cfg.Verbose,
	)

	srv := server.New(reg, proc, cfg.ModelPrefix, cfg.IdleTimeout, cfg.LoadTimeout)
	proc.SetOnExit(srv.MarkUnloaded)

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	go func() {
		<-ctx.Done()
		slog.Info("shutting down")
		srv.Shutdown()
	}()

	if err := os.Setenv("HTTP_SERVER_LISTENADDRESS", "0.0.0.0:7234"); err != nil {
		slog.Error("setenv failed", "error", err)
		os.Exit(1)
	}

	httpSrv, err := serbewr.New()
	if err != nil {
		slog.Error("server create failed", "error", err)
		os.Exit(1)
	}

	router := &serbewr.Router{
		GlobalMiddlewares: []middleware.Middleware{
			middleware.RequestID(),
			middleware.Logger(
				middleware.WithSkipPaths("/health"),
			),
			middleware.Recovery(),
		},
		Groups: []serbewr.GroupConfig{
			{
				Path: "/",
				Routes: []serbewr.RouteConfig{
					{Method: http.MethodGet, Path: "/health", Handler: (&server.HealthHandler{}).ServeHTTP},
					{Method: http.MethodGet, Path: "/v1/models", Handler: server.NewModelsHandler(srv).ServeHTTP},
					{Method: http.MethodGet, Path: "/sdcpp/v1/status", Handler: server.NewStatusHandler(srv).ServeHTTP},
					{Method: http.MethodPost, Path: "/sdcpp/v1/load", Handler: server.NewLoadHandler(srv).ServeHTTP},
					{Method: http.MethodPost, Path: "/sdcpp/v1/unload", Handler: server.NewUnloadHandler(srv).ServeHTTP},
					{Method: http.MethodPost, Path: "/sdcpp/v1/cancel", Handler: server.NewCancelHandler(srv).ServeHTTP},
					{Method: http.MethodPost, Path: "/v1/images/generations", Handler: server.NewProxyHandler(srv).ServeHTTP},
				},
			},
		},
	}

	if err := httpSrv.Start(ctx, router); err != nil {
		slog.Error("server error", "error", err)
		os.Exit(1)
	}
}
