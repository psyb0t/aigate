package server

import (
	"context"
	"log/slog"
	"sync"
	"syscall"
	"time"

	"github.com/psyb0t/ctxerrors"

	"github.com/psyb0t/aigate/sdcpp/wrapper/internal/config"
	"github.com/psyb0t/aigate/sdcpp/wrapper/internal/process"
)

// Server manages the sd-server process and serves HTTP.
type Server struct {
	registry    *config.Registry
	process     *process.Manager
	modelPrefix string
	idleTimeout time.Duration
	loadTimeout time.Duration

	mu           sync.RWMutex
	currentModel string
	loaded       bool
	loading      bool
	generating   bool
	loadCancel   context.CancelFunc

	loadMu sync.Mutex // serializes EnsureModel calls
	genMu  sync.Mutex // serializes image generation (one at a time)
	timerMu   sync.Mutex
	idleTimer *time.Timer
}

func New(reg *config.Registry, proc *process.Manager, modelPrefix string, idleTimeout, loadTimeout time.Duration) *Server {
	return &Server{
		registry:    reg,
		process:     proc,
		modelPrefix: modelPrefix,
		idleTimeout: idleTimeout,
		loadTimeout: loadTimeout,
	}
}

// EnsureModel starts sd-server with the given model, swapping if needed.
// Returns ErrBusy if another load or generation is in progress.
func (s *Server) EnsureModel(modelKey string) error {
	if !s.loadMu.TryLock() {
		return ErrBusy
	}
	defer s.loadMu.Unlock()
	return s.EnsureModelLocked(modelKey)
}

// TryLockModel attempts to acquire the model lock without blocking.
// Returns false if already held (another load or generation in progress).
func (s *Server) TryLockModel() bool { return s.loadMu.TryLock() }
func (s *Server) UnlockModel()       { s.loadMu.Unlock() }

// EnsureModelLocked is like EnsureModel but assumes loadMu is already held.
func (s *Server) EnsureModelLocked(modelKey string) error {
	// Fast path: already loaded with requested model
	s.mu.RLock()
	if s.loaded && s.currentModel == modelKey {
		s.mu.RUnlock()
		return nil
	}
	s.mu.RUnlock()

	m, err := s.registry.Get(modelKey)
	if err != nil {
		return ctxerrors.Wrap(ErrUnknownModel, modelKey)
	}

	// Stop current process if loaded, mark loading
	s.mu.Lock()
	if s.loaded && s.currentModel == modelKey {
		s.mu.Unlock()
		return nil
	}
	if s.loaded {
		slog.Info("swapping model", "from", s.currentModel, "to", modelKey)
		s.process.Stop()
		s.loaded = false
		s.stopIdleTimer()
	}
	s.loading = true
	s.currentModel = modelKey
	s.mu.Unlock()

	if err := s.process.Start(m.Args); err != nil {
		s.mu.Lock()
		s.loading = false
		s.mu.Unlock()
		return ctxerrors.Wrap(err, "start sd-server")
	}

	ctx, cancel := context.WithTimeout(context.Background(), s.loadTimeout)
	defer cancel()

	s.mu.Lock()
	s.loadCancel = cancel
	s.mu.Unlock()

	err = s.process.WaitReady(ctx)

	s.mu.Lock()
	s.loadCancel = nil
	s.loading = false

	if err != nil {
		s.mu.Unlock()
		s.process.Stop()
		return ctxerrors.Wrapf(ErrLoadFailed, "%s: %v", modelKey, err)
	}

	s.loaded = true
	s.resetIdleTimerLocked()
	s.mu.Unlock()

	return nil
}

// BeginGenerate marks the server as busy. Returns false if already generating.
// Uses genMu.TryLock for race-free serialization independent of the RWMutex.
func (s *Server) BeginGenerate() bool {
	if !s.genMu.TryLock() {
		return false
	}
	s.mu.Lock()
	s.generating = true
	s.mu.Unlock()
	return true
}

// IsGenerating returns true if an image generation is in progress.
func (s *Server) IsGenerating() bool {
	s.mu.RLock()
	defer s.mu.RUnlock()
	return s.generating
}

// EndGenerate marks the server as idle and resets the idle timer.
func (s *Server) EndGenerate() {
	s.mu.Lock()
	s.generating = false
	if s.loaded {
		s.resetIdleTimerLocked()
	}
	s.mu.Unlock()
	s.genMu.Unlock()
}

// CancelGenerate kills the sd-server process to abort an in-progress generation.
// The proxy handler will receive a bad gateway error and clean up via EndGenerate.
func (s *Server) CancelGenerate() bool {
	s.mu.RLock()
	if !s.generating {
		s.mu.RUnlock()
		return false
	}
	s.mu.RUnlock()

	pid := s.process.PID()
	if pid > 0 {
		slog.Info("cancelling generation, killing sd-server", "pid", pid)
		_ = syscall.Kill(-pid, syscall.SIGKILL)
	}

	return true
}

// Unload stops sd-server without respawning.
// No-ops during in-progress loads or generations. Use POST /sdcpp/v1/cancel
// to abort a running generation.
func (s *Server) Unload() (model string, wasLoaded bool) {
	s.mu.Lock()

	if s.loading || s.generating || !s.loaded {
		s.mu.Unlock()
		return s.currentModel, false
	}

	s.process.Stop()
	s.loaded = false
	s.stopIdleTimer()
	s.mu.Unlock()

	return s.currentModel, true
}

// Status returns the current server state.
func (s *Server) Status() StatusResponse {
	s.mu.RLock()
	defer s.mu.RUnlock()

	resp := StatusResponse{
		Loaded:       s.loaded,
		Loading:      s.loading,
		CurrentModel: s.currentModel,
		Generating:   s.generating,
		IdleTimeout:  int(s.idleTimeout.Seconds()),
		SupportsImg:  true,
		Models:       s.registry.ModelNames(),
		ProcessRunning: s.process.Running(),
		ProcessPID:     s.process.PID(),
	}

	if s.currentModel != "" {
		if m, err := s.registry.Get(s.currentModel); err == nil {
			resp.CurrentModelArgs = m.Args
			resp.CurrentModelSize = [2]int{m.Width, m.Height}
		}
	}

	return resp
}

// IsLoadedWith checks atomically if the given model is currently loaded.
func (s *Server) IsLoadedWith(key string) bool {
	s.mu.RLock()
	defer s.mu.RUnlock()
	return s.loaded && s.currentModel == key
}

// MarkUnloaded sets the server state to unloaded. Called by the process
// exit callback when sd-server exits unexpectedly.
func (s *Server) MarkUnloaded() {
	s.mu.Lock()
	defer s.mu.Unlock()

	if !s.loaded {
		return
	}

	slog.Warn("sd-server exited unexpectedly, marking unloaded", "model", s.currentModel)
	s.loaded = false
	s.stopIdleTimer()
}

// resetIdleTimerLocked resets the idle timeout. Caller must hold s.mu.
func (s *Server) resetIdleTimerLocked() {
	if s.idleTimeout <= 0 {
		return
	}

	s.timerMu.Lock()
	defer s.timerMu.Unlock()

	if s.idleTimer != nil {
		s.idleTimer.Stop()
	}

	s.idleTimer = time.AfterFunc(s.idleTimeout, func() {
		s.mu.Lock()
		defer s.mu.Unlock()

		if !s.loaded || s.generating {
			return
		}

		slog.Info("idle timeout reached, unloading model", "model", s.currentModel)
		s.process.Stop()
		s.loaded = false
	})
}

func (s *Server) stopIdleTimer() {
	s.timerMu.Lock()
	defer s.timerMu.Unlock()

	if s.idleTimer != nil {
		s.idleTimer.Stop()
		s.idleTimer = nil
	}
}

// Shutdown stops the idle timer and sd-server.
func (s *Server) Shutdown() {
	s.stopIdleTimer()

	s.mu.Lock()
	defer s.mu.Unlock()

	if s.loaded {
		s.process.Stop()
		s.loaded = false
	}
}

// Registry returns the model registry.
func (s *Server) Registry() *config.Registry {
	return s.registry
}

// ModelPrefix returns the model prefix used for name resolution.
func (s *Server) ModelPrefix() string {
	return s.modelPrefix
}

// ProcessAddr returns the sd-server listen address.
func (s *Server) ProcessAddr() string {
	return s.process.ListenAddr()
}

type StatusResponse struct {
	Loaded           bool     `json:"loaded"`
	Loading          bool     `json:"loading"`
	CurrentModel     string   `json:"current_model"`
	CurrentModelArgs []string `json:"current_model_args,omitempty"`
	CurrentModelSize [2]int   `json:"current_model_size,omitempty"`
	Generating       bool     `json:"generating"`
	ProcessRunning   bool     `json:"process_running"`
	ProcessPID       int      `json:"process_pid"`
	IdleTimeout      int      `json:"idle_timeout"`
	SupportsImg      bool     `json:"supports_img"`
	Models           []string `json:"models"`
}
