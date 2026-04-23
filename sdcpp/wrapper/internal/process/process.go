package process

import (
	"context"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"os/exec"
	"syscall"
	"time"

	"github.com/psyb0t/ctxerrors"
)

// Manager handles the sd-server subprocess lifecycle.
type Manager struct {
	sdServerPath string
	listenAddr   string
	extraArgs    []string
	verbose      bool
	onExit       func()

	cmd      *exec.Cmd
	stopping bool
	waitDone chan struct{}
}

func NewManager(sdServerPath, listenAddr string, extraArgs []string, verbose bool) *Manager {
	return &Manager{
		sdServerPath: sdServerPath,
		listenAddr:   listenAddr,
		extraArgs:    extraArgs,
		verbose:      verbose,
	}
}

// SetOnExit sets a callback invoked when sd-server exits unexpectedly.
func (m *Manager) SetOnExit(fn func()) {
	m.onExit = fn
}

func (m *Manager) Start(modelArgs []string) error {
	args := make([]string, 0, len(modelArgs)+len(m.extraArgs)+4)
	args = append(args, modelArgs...)
	args = append(args, "--listen-ip", listenIP(m.listenAddr))
	args = append(args, "--listen-port", listenPort(m.listenAddr))
	args = append(args, m.extraArgs...)
	if m.verbose {
		args = append(args, "-v")
	}

	m.cmd = exec.Command(m.sdServerPath, args...)
	m.cmd.Stdout = os.Stdout
	m.cmd.Stderr = os.Stderr
	m.cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}

	slog.Info("starting sd-server", "path", m.sdServerPath, "args", args)

	if err := m.cmd.Start(); err != nil {
		return ctxerrors.Wrap(err, "start sd-server")
	}

	m.stopping = false
	m.waitDone = make(chan struct{})
	go func() {
		defer close(m.waitDone)
		if err := m.cmd.Wait(); err != nil {
			slog.Warn("sd-server exited", "error", err)
		} else {
			slog.Info("sd-server exited cleanly")
		}
		if m.onExit != nil && !m.stopping {
			m.onExit()
		}
	}()

	return nil
}

func (m *Manager) Stop() {
	if m.cmd == nil || m.cmd.Process == nil {
		return
	}

	m.stopping = true
	pid := m.cmd.Process.Pid
	slog.Info("stopping sd-server", "pid", pid)

	_ = m.cmd.Process.Signal(syscall.SIGTERM)

	deadline := time.After(10 * time.Second)
	select {
	case <-m.waitDone:
		slog.Info("sd-server stopped gracefully")
	case <-deadline:
		slog.Warn("sd-server kill timeout, sending SIGKILL", "pid", pid)
		_ = syscall.Kill(-pid, syscall.SIGKILL)
		<-m.waitDone
	}

	m.cmd = nil
}

// Running checks if the sd-server process is alive.
func (m *Manager) Running() bool {
	if m.cmd == nil || m.cmd.Process == nil {
		return false
	}
	return syscall.Kill(m.cmd.Process.Pid, 0) == nil
}

// WaitReady polls sd-server's /v1/models until it responds 200,
// the process exits, or ctx expires.
func (m *Manager) WaitReady(ctx context.Context) error {
	url := fmt.Sprintf("http://%s/v1/models", m.listenAddr)
	client := &http.Client{Timeout: 2 * time.Second}
	ticker := time.NewTicker(500 * time.Millisecond)
	defer ticker.Stop()

	for {
		select {
		case <-ctx.Done():
			return ctxerrors.Wrap(ErrNotReady, ctx.Err().Error())
		case <-m.waitDone:
			return ctxerrors.New("sd-server exited during startup")
		case <-ticker.C:
			resp, err := client.Get(url)
			if err == nil {
				_ = resp.Body.Close()
				if resp.StatusCode == http.StatusOK {
					slog.Info("sd-server ready")
					return nil
				}
			}
		}
	}
}

// PID returns the sd-server process ID, or 0 if not running.
func (m *Manager) PID() int {
	if m.cmd == nil || m.cmd.Process == nil {
		return 0
	}
	return m.cmd.Process.Pid
}

// ListenAddr returns the address sd-server listens on.
func (m *Manager) ListenAddr() string {
	return m.listenAddr
}

func listenIP(addr string) string {
	for i := len(addr) - 1; i >= 0; i-- {
		if addr[i] == ':' {
			return addr[:i]
		}
	}
	return addr
}

func listenPort(addr string) string {
	for i := len(addr) - 1; i >= 0; i-- {
		if addr[i] == ':' {
			return addr[i+1:]
		}
	}
	return addr
}
