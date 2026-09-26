# Resource Management (cross-cutting)


Local services (Ollama, sd.cpp, talkies, vllm, llamacpp, audiolla, flickies, predictalot, decidealot) share limited hardware. The platform coordinates them automatically — no manual model management needed.

### Idle auto-unload

Every local service unloads models after a period of inactivity:

| Service | Default idle timeout | Configurable via |
| ------- | -------------------- | ---------------- |
| Ollama (CPU/CUDA) | 5 minutes | Ollama's built-in `keep_alive` |
| sd.cpp CPU | 5 minutes | `SDCPP_IDLE_TIMEOUT` |
| sd.cpp CUDA | 5 minutes | `SDCPP_CUDA_IDLE_TIMEOUT` |
| talkies CPU (ASR + Kokoro TTS) | 10 minutes | `TALKIES_MODEL_TTL` (wrapper idle sweeper); resource manager also triggers `DELETE /api/ps/{model}` |
| talkies CUDA (ASR + Kokoro TTS + Qwen3-TTS) | 10 minutes | `TALKIES_CUDA_MODEL_TTL` (wrapper idle sweeper); resource manager also triggers `DELETE /api/ps/{model}` |
| vllm-cuda | 10 minutes | `VLLM_CUDA_MODEL_TTL` (wrapper idle sweeper); resource manager also triggers `DELETE /api/ps/{model}` |
| vllm (CPU) | 10 minutes | `VLLM_MODEL_TTL` (wrapper idle sweeper); resource manager also triggers `DELETE /api/ps/{model}` |
| llamacpp CUDA | 600 seconds | `LLAMACPP_CUDA_MODEL_TTL` (wrapper idle sweeper); resource manager also triggers `DELETE /api/ps/{model}` |
| llamacpp (CPU) | 600 seconds | `LLAMACPP_MODEL_TTL` (wrapper idle sweeper); resource manager also triggers `DELETE /api/ps/{model}` |
| predictalot (CPU/CUDA) | 30 minutes | `PREDICTALOT_MODEL_IDLE_TIMEOUT`; resource manager also triggers `POST /v1/models/unload` |
| decidealot (CPU/CUDA) | 600 seconds | `DECIDEALOT_PROVIDER_IDLE_UNLOAD_SECONDS`; resource manager also triggers `POST /v1/models/unload` |

### Auto-load on demand

Models load automatically when a request arrives. Send a chat completion to `local-ollama-cuda-qwen3-8b` and Ollama pulls/loads it. Send an image generation to `local-sdcpp-cuda-flux-schnell` and the sd.cpp wrapper spawns sd-server with that model. No pre-loading required.

### Hardware semaphores

A LiteLLM callback (`resource_manager.py`) enforces mutual exclusion per hardware class:

- **CUDA semaphore** — one CUDA job at a time across all groups: LLM (`cuda-llm`), image gen (`cuda-img`), TTS (`cuda-tts`), STT (`cuda-stt`)
- **CPU semaphore** — one CPU job at a time across: LLM (`cpu-llm`), image gen (`cpu-img`), TTS (`cpu-tts`), STT (`cpu-stt`)

When a request arrives for a local model:

1. The resource manager identifies which group it belongs to (e.g. `local-sdcpp-cuda-flux-schnell` → `cuda-img`)
2. It acquires the hardware semaphore (waits if another job is running)
3. It unloads all competing groups on the same hardware (e.g. unloads `cuda-llm`, `cuda-tts`, `cuda-stt`)
4. **For sd.cpp (`cuda-img` / `cpu-img`) only:** it explicitly POSTs `/sdcpp/v1/load?model=<key>` and blocks until the backend has the requested model loaded — see "sd.cpp pre-load" below for why.
5. The request proceeds
6. On completion (success or failure), the semaphore is released

### sd.cpp pre-load (image generation only)

sd.cpp's image handler uses `TryLockModel` — if the requested model isn't already loaded, the FIRST call triggers a ~5-20 s load (depending on model size) while holding the lock. Any concurrent call inside that window returns 503 `another load or generation in progress`. LiteLLM's image-gen path reacts to a 503 by retrying (`num_retries: 3`) and walking the fallback chain. Every retry hits the same lock, every retry 503s, and the entire fallback chain ends with LiteLLM returning HTTP 200 with an EMPTY `data` array (a router-side bug where image-gen fallback exhaustion masquerades as success).

The resource manager fixes this by issuing the explicit `POST /sdcpp/v1/load?model=<key>` blocking call inside the pre-call hook — while the cuda-img / cpu-img semaphore is still held. By the time LiteLLM dispatches the actual `POST /v1/images/generations`, the backend is fully warm and the call succeeds on attempt 1. No 503 storm, no fallback amplification, no empty-data response.

The pre-load is a no-op (~ms) when the model is already loaded. A failed pre-load (model missing, weights corrupt, GPU OOM) is LOGGED rather than raised — LiteLLM then dispatches the call normally and the caller sees the real backend error rather than an indefinitely-blocked request.

### Unload mechanisms

Each service has its own unload API:

| Service | Unload method |
| ------- | ------------- |
| Ollama | `POST /api/generate {"model": "...", "keep_alive": 0}` |
| sd.cpp | `POST /sdcpp/v1/unload` |
| talkies / vllm-cuda / llamacpp-cuda | `DELETE /api/ps/{model_id}` (per model) or `POST /unload` (kill any loaded) |
| audiolla | `POST /v1/unload` (bulk evict every loaded engine) |
| flickies | `GET /v1/engines` + `DELETE /v1/engines/{slug}` (per loaded engine) |
| predictalot | `POST /v1/models/unload` (every resident foundation model, plus Torch and CUDA caches). `409` while a forecast runs |
| decidealot | `POST /v1/models/unload` (the resident Laya or Von model, plus Torch memory). `409` while a decision runs |

### Direct-HTTP services in the competing-group unload

Audiolla, flickies, predictalot, and decidealot expose their own HTTP APIs through nginx rather than routing through LiteLLM completions. No `local-audiolla-*` / `local-flickies-*` / `local-predictalot-*` / `local-decidealot-*` model aliases exist, so the resource manager never resolves a request to them as own-group. They participate ONLY as COMPETING groups. Every LiteLLM-routed call (ollama / sdcpp / talkies / vllm / llamacpp) evicts them before allocating VRAM. Without this coupling a LatentSync or Wav2Lip session hoarding 7+ GiB of VRAM would OOM-kill talkies-cuda or ollama-cuda the moment they tried to load a model.

predictalot and decidealot answer `409` to an unload while they are serving a request. The resource manager logs that as a skipped unload and continues, and the busy service frees its model on its own idle timer. Each unload call carries that service's own token (`PREDICTALOT_AUTH_TOKEN`, `DECIDEALOT_AUTH_TOKEN`), which LiteLLM gets with the same `AIGATE_TOKEN` fallback the services use.

The coupling runs one way. A request sent straight to one of these four services does not pass through LiteLLM, so it does not evict LiteLLM-routed models or take the hardware semaphore. On a small GPU, a cold start on one of them can still run out of memory next to a loaded Ollama or talkies model.

### Operator-facing unload endpoints

For manual VRAM cleanup — after a bad run, before running a benchmark, or from an oncall runbook — three HTTP endpoints fan out the eviction across every service:

| Method + path | Effect |
| ------------- | ------ |
| `POST /v1/unload/cuda` | Concurrent fan-out to `ollama-cuda`, `sdcpp-cuda`, `talkies-cuda`, `vllm-cuda`, `llamacpp-cuda`, `audiolla-cuda`, `flickies-cuda`, `predictalot-cuda`, `decidealot-cuda`. |
| `POST /v1/unload/cpu` | CPU counterpart, same 9 services. |
| `POST /v1/unload` | Convenience — runs both in sequence. |

Response shape:
```json
{
  "class": "cuda",
  "results": {
    "ollama-cuda":   {"status": "empty", "unloaded": []},
    "audiolla-cuda": {"status": "ok",    "unloaded": ["htdemucs"]},
    "flickies-cuda": {"status": "ok",    "unloaded": ["latentsync-1.5"]},
    "decidealot-cuda": {"status": "busy", "http": 409}
  }
}
```

Per-service errors do not fail the whole call (`status: "error"` on the offending entry, others still evict). A service that is serving a request reports `status: "busy"` and keeps its model. Auth: same bearer as the rest of aigate. Implemented in `mcp/server.py` via `@mcp.custom_route`; nginx proxies `/v1/unload/{cuda,cpu,''}` to `mcp:8000` with a 120s timeout since some unloads take a few seconds to actually release VRAM.

### Non-blocking rejection

The sd.cpp wrapper uses `TryLock` — if a generation or model swap is in progress, new requests get 503 immediately instead of queuing. Scheduling happens at the LiteLLM layer via the semaphore, not inside individual services.
