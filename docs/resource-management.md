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

### Hardware locks

A LiteLLM callback (`resource_manager.py`) allows one job at a time per hardware class:

- **CUDA lock:** one CUDA job at a time across every CUDA group (Ollama, sd.cpp, talkies, vLLM, llama.cpp, and the predictalot and decidealot MCP tools).
- **CPU lock:** the same for the CPU groups.

The locks live in Redis (`hardware_lock.py`), so they hold across all of LiteLLM's worker processes (`LITELLM_WORKERS`, 4 by default). Before v6.0.0 each worker had its own in-memory lock, so up to four jobs could run on the GPU at once.

When a request arrives for a local model:

1. The resource manager identifies which group it belongs to (e.g. `local-sdcpp-cuda-flux-schnell` → `cuda-img`)
2. It takes the hardware lock and waits while another job holds it
3. It unloads all competing groups on the same hardware (e.g. unloads `cuda-llm`, `cuda-stt-talkies`, `cuda-vllm`)
4. **For sd.cpp (`cuda-img` / `cpu-img`) only:** it explicitly POSTs `/sdcpp/v1/load?model=<key>` and blocks until the backend has the requested model loaded. See "sd.cpp pre-load" below for why.
5. The request proceeds
6. On completion (success or failure), the lock is released

The holder refreshes the lock while the job runs. A worker that crashes stops refreshing, and its lock expires after `RESOURCE_LOCK_TTL_SECONDS` (60 by default), so other requests go ahead. A lock whose release was missed stops being refreshed after `RESOURCE_LOCK_MAX_HOLD_SECONDS` (86400 by default, the same as the inference timeout). If Redis is down, requests for local models fail instead of running unlocked.

LiteLLM connects to Redis as the `litellm` ACL user, which can only touch the lock keys (`aigate:hwlock:*`) and its response cache keys (`aigate:cache:*`). Its password is `LITELLM_REDIS_PASSWORD`, falling back to `REDIS_PASSWORD`. proxq connects as the `proxq` user with `REDIS_PASSWORD`, limited to its queue and cache keys. The `default` user is disabled.

### sd.cpp pre-load (image generation only)

sd.cpp's image handler uses `TryLockModel` — if the requested model isn't already loaded, the FIRST call triggers a ~5-20 s load (depending on model size) while holding the lock. Any concurrent call inside that window returns 503 `another load or generation in progress`. LiteLLM's image-gen path reacts to a 503 by retrying (`num_retries: 3`) and walking the fallback chain. Every retry hits the same lock, every retry 503s, and the entire fallback chain ends with LiteLLM returning HTTP 200 with an EMPTY `data` array (a router-side bug where image-gen fallback exhaustion masquerades as success).

The resource manager fixes this by issuing the explicit `POST /sdcpp/v1/load?model=<key>` blocking call inside the pre-call hook, while the hardware lock is still held. By the time LiteLLM dispatches the actual `POST /v1/images/generations`, the backend is fully warm and the call succeeds on attempt 1. No 503 storm, no fallback amplification, no empty-data response.

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

predictalot and decidealot tool calls made through LiteLLM's aggregated MCP server (`/mcp`) also run under the hardware lock. An inference tool (anything except `list_*`, `get_*`, and `unload_models`) takes the lock and evicts the competing groups first, the same as a LiteLLM-routed model. The CUDA variants (`predictalot_cuda`, `decidealot_cuda`) take the CUDA lock and the CPU variants take the CPU lock.

Requests sent straight to audiolla, flickies, predictalot, or decidealot through their own nginx routes (`/decidealot-cuda/`, `/predictalot-cuda/`, and so on) still bypass LiteLLM. They do not evict LiteLLM-routed models or take the hardware lock. On a small GPU, a cold start on one of them can still run out of memory next to a loaded Ollama or talkies model.

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

The sd.cpp wrapper uses `TryLock`. If a generation or model swap is in progress, new requests get 503 immediately instead of queuing. Scheduling happens at the LiteLLM layer via the hardware lock, not inside individual services.
