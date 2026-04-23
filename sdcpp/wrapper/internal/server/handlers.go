package server

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"net/http/httputil"
	"net/url"
	"strings"
	"time"

	"github.com/psyb0t/aichteeteapee"
	"github.com/psyb0t/common-go/slogging"
	"github.com/psyb0t/ctxerrors"
)

// HealthHandler returns 200 if the wrapper is alive.
type HealthHandler struct{}

func (h *HealthHandler) ServeHTTP(w http.ResponseWriter, _ *http.Request) {
	aichteeteapee.WriteJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}

// StatusHandler returns the server state.
type StatusHandler struct {
	srv *Server
}

func NewStatusHandler(srv *Server) *StatusHandler {
	return &StatusHandler{srv: srv}
}

func (h *StatusHandler) ServeHTTP(w http.ResponseWriter, _ *http.Request) {
	aichteeteapee.WriteJSON(w, http.StatusOK, h.srv.Status())
}

// ModelsHandler returns all registered models in OpenAI format.
type ModelsHandler struct {
	srv *Server
}

func NewModelsHandler(srv *Server) *ModelsHandler {
	return &ModelsHandler{srv: srv}
}

func (h *ModelsHandler) ServeHTTP(w http.ResponseWriter, _ *http.Request) {
	names := h.srv.Registry().ModelNames()
	models := make([]map[string]any, 0, len(names))
	for _, name := range names {
		models = append(models, map[string]any{
			"id":       h.srv.ModelPrefix() + name,
			"object":   "model",
			"created":  time.Now().Unix(),
			"owned_by": "local",
		})
	}

	aichteeteapee.WriteJSON(w, http.StatusOK, map[string]any{
		"object": "list",
		"data":   models,
	})
}

// LoadHandler starts sd-server with a model.
type LoadHandler struct {
	srv *Server
}

func NewLoadHandler(srv *Server) *LoadHandler {
	return &LoadHandler{srv: srv}
}

func (h *LoadHandler) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	logger := slogging.GetLogger(r.Context())

	modelKey := r.URL.Query().Get("model")
	if modelKey == "" {
		modelKey = h.srv.Registry().DefaultModel
	}

	if !h.srv.Registry().Has(modelKey) {
		aichteeteapee.WriteJSON(w, http.StatusBadRequest, map[string]any{
			"error": fmt.Sprintf("unknown model %q; available: %s",
				modelKey, strings.Join(h.srv.Registry().ModelNames(), ", ")),
		})
		return
	}

	if h.srv.IsLoadedWith(modelKey) {
		aichteeteapee.WriteJSON(w, http.StatusOK, map[string]any{
			"already_loaded": true,
			"model":          modelKey,
		})
		return
	}

	logger.Info("loading model", "model", modelKey)

	if err := h.srv.EnsureModel(modelKey); err != nil {
		logger.Error("load failed", "error", err, "model", modelKey)
		aichteeteapee.WriteJSON(w, http.StatusServiceUnavailable, map[string]any{
			"error": fmt.Sprintf("load failed: %v", err),
		})
		return
	}

	aichteeteapee.WriteJSON(w, http.StatusOK, map[string]any{
		"loaded": true,
		"model":  modelKey,
	})
}

// UnloadHandler stops sd-server.
type UnloadHandler struct {
	srv *Server
}

func NewUnloadHandler(srv *Server) *UnloadHandler {
	return &UnloadHandler{srv: srv}
}

func (h *UnloadHandler) ServeHTTP(w http.ResponseWriter, _ *http.Request) {
	model, wasLoaded := h.srv.Unload()
	if !wasLoaded {
		aichteeteapee.WriteJSON(w, http.StatusOK, map[string]any{
			"already_unloaded": true,
		})
		return
	}

	aichteeteapee.WriteJSON(w, http.StatusOK, map[string]any{
		"unloaded": true,
		"model":    model,
	})
}

// CancelHandler aborts an in-progress image generation by killing sd-server.
type CancelHandler struct {
	srv *Server
}

func NewCancelHandler(srv *Server) *CancelHandler {
	return &CancelHandler{srv: srv}
}

func (h *CancelHandler) ServeHTTP(w http.ResponseWriter, _ *http.Request) {
	if !h.srv.CancelGenerate() {
		aichteeteapee.WriteJSON(w, http.StatusOK, map[string]any{
			"cancelled": false,
			"reason":    "not generating",
		})
		return
	}

	aichteeteapee.WriteJSON(w, http.StatusOK, map[string]any{
		"cancelled": true,
	})
}

// ProxyHandler handles /v1/images/generations — resolves model, swaps if needed, proxies.
type ProxyHandler struct {
	srv   *Server
	proxy *httputil.ReverseProxy
}

func NewProxyHandler(srv *Server) *ProxyHandler {
	target := &url.URL{
		Scheme: "http",
		Host:   srv.ProcessAddr(),
	}

	rp := httputil.NewSingleHostReverseProxy(target)
	rp.ErrorHandler = func(w http.ResponseWriter, _ *http.Request, err error) {
		slog.Warn("proxy backend error", "error", err)
		aichteeteapee.WriteJSON(w, http.StatusBadGateway, aichteeteapee.ErrorResponseBadGateway)
	}

	return &ProxyHandler{
		srv:   srv,
		proxy: rp,
	}
}

func (h *ProxyHandler) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	logger := slogging.GetLogger(r.Context())

	const maxBodySize = 10 << 20 // 10 MB
	body, err := io.ReadAll(io.LimitReader(r.Body, maxBodySize))
	if err != nil {
		logger.Error("read body", "error", err)
		aichteeteapee.WriteJSON(w, http.StatusBadRequest, aichteeteapee.ErrorResponseBadRequest)
		return
	}
	_ = r.Body.Close()

	var req struct {
		Model string `json:"model"`
	}
	if err := json.Unmarshal(body, &req); err != nil {
		logger.Error("parse body", "error", err)
		aichteeteapee.WriteJSON(w, http.StatusBadRequest, aichteeteapee.ErrorResponseBadRequest)
		return
	}

	modelKey, err := h.resolveModelKey(req.Model)
	if err != nil {
		logger.Warn("unknown model", "model", req.Model)
		aichteeteapee.WriteJSON(w, http.StatusBadRequest, map[string]any{
			"error": map[string]any{
				"message": fmt.Sprintf("unknown model %q; available: %s",
					req.Model, strings.Join(h.srv.Registry().ModelNames(), ", ")),
			},
		})
		return
	}

	logger.Info("image generation request", "model_key", modelKey, "raw_model", req.Model)

	if !h.srv.TryLockModel() {
		logger.Warn("rejected, model load/generation in progress", "model", modelKey)
		aichteeteapee.WriteJSON(w, http.StatusServiceUnavailable, map[string]any{
			"error": map[string]any{
				"message": "another load or generation is in progress, try again later",
			},
		})
		return
	}
	defer h.srv.UnlockModel()

	if err := h.srv.EnsureModelLocked(modelKey); err != nil {
		logger.Error("ensure model failed", "error", err, "model", modelKey)
		aichteeteapee.WriteJSON(w, http.StatusServiceUnavailable, map[string]any{
			"error": map[string]any{
				"message": fmt.Sprintf("failed to load model %q: %v", modelKey, err),
			},
		})
		return
	}

	if !h.srv.BeginGenerate() {
		logger.Warn("rejected, generation already in progress", "model", modelKey)
		aichteeteapee.WriteJSON(w, http.StatusServiceUnavailable, map[string]any{
			"error": map[string]any{
				"message": "another generation is already in progress, try again later or POST /sdcpp/v1/cancel",
			},
		})
		return
	}
	defer h.srv.EndGenerate()

	rewritten := rewriteModelField(body)
	r.Body = io.NopCloser(bytes.NewReader(rewritten))
	r.ContentLength = int64(len(rewritten))

	h.proxy.ServeHTTP(w, r)
}

func (h *ProxyHandler) resolveModelKey(model string) (string, error) {
	// LiteLLM sends "openai/local-sdcpp-cuda-flux-schnell"
	model = strings.TrimPrefix(model, "openai/")

	prefix := h.srv.ModelPrefix()
	if prefix != "" && strings.HasPrefix(model, prefix) {
		key := strings.TrimPrefix(model, prefix)
		if h.srv.Registry().Has(key) {
			return key, nil
		}
	}

	if h.srv.Registry().Has(model) {
		return model, nil
	}

	return "", ctxerrors.Wrap(ErrUnknownModel, model)
}

func rewriteModelField(body []byte) []byte {
	var parsed map[string]any
	if err := json.Unmarshal(body, &parsed); err != nil {
		return body
	}
	parsed["model"] = "sd-cpp-local"
	out, err := json.Marshal(parsed)
	if err != nil {
		return body
	}
	return out
}
