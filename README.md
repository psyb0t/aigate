# aigate

A self-hosted AI platform. 27 services, 99 models, 20 tools, one `docker-compose up`.

Everything an AI-powered workflow needs — inference, tool use, browser automation, image generation, speech synthesis, transcription, object storage, agentic code execution, an async job queue, and a web UI — behind a single OpenAI-compatible endpoint at `http://localhost:4000`. Point any existing client at it and it works.

### Models and routing

99 models across 15 providers. Six providers are completely free (Groq, Cerebras, OpenRouter, HuggingFace, Mistral, Cohere). Five run locally on your own hardware — CPU or NVIDIA GPU — with no network calls, no rate limits, and no usage costs (Ollama, Speaches, Qwen3 TTS, stable-diffusion.cpp CPU, stable-diffusion.cpp CUDA). The gateway burns through providers in priority order and falls back automatically when one rate-limits or fails, so you're never paying for tokens you could have gotten free.

### Tools and capabilities

20 MCP tools across 5 servers. Any model with function calling can invoke them autonomously — the model orchestrates, you just prompt.

- **Stealth browser cluster** — 5 Camoufox replicas behind HAProxy, real OS-level mouse and keyboard input, zero CDP exposure. Passes Cloudflare, CreepJS, BrowserScan, and every other bot detector we've thrown at it.
- **Agentic Claude Code ×2** — full shell access, persistent workspaces, file I/O, tool use. One instance on your Claude subscription or API key, one running GLM models through z.ai.
- **Object storage** — S3-compatible, public-read uploads, presigned URLs, auto-expiry. Plain HTTP and boto3.
- **Image generation** — FLUX, DALL-E, Stable Diffusion (cloud + local CPU/CUDA via stable-diffusion.cpp) via MCP tools that return persistent URLs, not base64 blobs. Local models: sd-turbo, sdxl-turbo, sdxl-lightning, flux-schnell, juggernaut-xi.
- **Text-to-speech** — Kokoro (CPU), Qwen3-TTS with voice cloning (CUDA), OpenAI TTS.
- **Transcription** — Whisper (cloud + local CPU/CUDA), Parakeet (~3400× real-time on CPU).

Ask a Groq model to research something and it opens a browser, reads pages, screenshots them, uploads to storage, and comes back with a summary and links. The model decides what tools to use and in what order.

### Web UI

LibreChat at `/librechat/` — pre-configured with all models and MCP tools, conversation history, file uploads, WebSocket streaming. Email/password auth, first user becomes admin.

### Infrastructure

27 containers. Nginx reverse proxy with per-endpoint rate limiting. PostgreSQL + MongoDB for persistence. Two Redis instances (cache + browser session sync). Async job queue for long-running inference. Cloudflare Tunnel for public exposure with zero open ports.

### Security

Network-isolated by default — internal services have no host ports. Every endpoint requires auth. All containers run with `no-new-privileges`. File path pre-flight validation on startup.

### Everything is opt-in

Enable what you want in `.env`, ignore what you don't. The core stack (nginx, LiteLLM, PostgreSQL, Redis, proxq) is always on. Every provider, local model, MCP server, and extra service is a flag flip away.

`make run-bg`. That's the whole install.

## Architecture

```
client
  ▼
cloudflared (CLOUDFLARED=1)
  ▼
nginx :4000                                          ┌──────────── always on ────────────┐
  ├─► /claudebox/            → claudebox             │ nginx, LiteLLM, PostgreSQL, Redis │
  ├─► /claudebox-zai/        → claudebox-zai         │ proxq — everything else is opt-in │
  ├─► /stealthy-auto-browse/ → HAProxy → [browser ×5]└─────────────────────────────────────┘
  ├─► /storage/              → hybrids3
  ├─► /q/                    → proxq → LiteLLM (async, returns job ID)
  ├─► /librechat/            → LibreChat (web UI, LIBRECHAT=1)
  └─► /                      → LiteLLM (sync)
                                  ├─ Groq              (free, GROQ=1)
                                  ├─ Cerebras           (free, CEREBRAS=1)
                                  ├─ OpenRouter         (free tier, OPENROUTER=1)
                                  ├─ HuggingFace        (free, HUGGINGFACE=1)
                                  ├─ Mistral            (free: 1B tokens/month, MISTRAL=1)
                                  ├─ Cohere             (free: 1K req/day, COHERE=1)
                                  ├─ Ollama CPU         (local, OLLAMA=1)
                                  ├─ Ollama CUDA        (local, NVIDIA, OLLAMA_CUDA=1)
                                  ├─ Speaches CPU       (local, transcription + TTS, SPEACHES=1)
                                  ├─ Speaches CUDA      (local, CUDA STT, SPEACHES_CUDA=1)
                                  ├─ Qwen3 CUDA TTS     (local, CUDA voice-cloning, QWEN_TTS_CUDA=1)
                                  ├─ sd.cpp CPU         (local, image gen, SDCPP=1)
                                  ├─ sd.cpp CUDA        (local, image gen, SDCPP_CUDA=1)
                                  ├─ claudebox          (flat-rate, CLAUDEBOX=1)
                                  ├─ claudebox-zai      (flat-rate, CLAUDEBOX_ZAI=1)
                                  ├─ Anthropic          (pay-per-token, ANTHROPIC=1)
                                  └─ OpenAI             (pay-per-token, OPENAI=1)

MCP servers (up to 20 tools, all optional):
  ├─ stealthy_auto_browse  (1 tool)   — run_script: multi-step browser automation (BROWSER=1)
  ├─ hybrids3              (7 tools)  — file upload, download, list, delete, presign (HYBRIDS3=1)
  ├─ claudebox             (5 tools)  — agentic Claude Code via OAuth or API key (CLAUDEBOX=1)
  ├─ claudebox_zai         (5 tools)  — agentic Claude Code via z.ai/GLM (CLAUDEBOX_ZAI=1)
  └─ mcp_tools             (2 tools)  — generate_image + generate_tts (auto-enabled with image/TTS providers)
```

All persistent data lives under `.data/` by default (bind mounts). Override the base with `DATA_DIR` or per-service with `DATA_DIR_*` env vars (e.g. `DATA_DIR_OLLAMA=/mnt/nas/ollama`) — see [`.env.example`](.env.example) for the full list. The default directory structure is tracked in git via `.gitkeep` files so the right directories exist on a fresh clone — contents are gitignored.

Default writable locations:

| Path | Used by | Notes |
| ---- | ------- | ----- |
| `.data/claudebox/config/.always-skills/` | claudebox | Drop `<name>/SKILL.md` files here — injected into every Claude session automatically |
| `.data/claudebox-zai/config/.always-skills/` | claudebox-zai | Same, for the z.ai instance |
| `.data/claudebox/workspaces/` | claudebox | Persistent task workspaces |
| `.data/claudebox-zai/workspaces/` | claudebox-zai | Persistent task workspaces |
| `.data/hybrids3/` | hybrids3 | Object storage data |
| `.data/nginx/` | nginx-auth-init | Generated htpasswd (from `LITELLM_UI_BASIC_AUTH`) |
| `.data/ollama/` | ollama, ollama-cuda | Downloaded model weights (shared — CPU and CUDA instances read the same blobs) |
| `.data/speaches/` | speaches, speaches-cuda | Downloaded Whisper and Parakeet model weights (HuggingFace cache, shared between CPU/CUDA) |
| `.data/qwen3-tts/` | qwen3-cuda-tts | Downloaded Qwen3-TTS model weights (HuggingFace cache) |
| `.data/sdcpp/models/` | sdcpp, sdcpp-cuda | Downloaded stable-diffusion model weights (shared between CPU and CUDA) |
| `.data/librechat/` | librechat, librechat-mongodb | Conversation data (MongoDB), file uploads |
| `.data/cloudflared/` | cloudflared | Tunnel config and credentials (if using named tunnel) |

## Services

| Service | Description |
| ------- | ----------- |
| **Nginx** | Single entry point on port 4000. Routes by URL path, enforces per-endpoint rate limits (configurable via `RATELIMIT_*` env vars), configurable proxy timeouts (`TIMEOUT_*`), restores real client IP behind Cloudflare, and optionally adds HTTP basic auth on the admin UI. All config is embedded inline. |
| **LiteLLM** | OpenAI-compatible API proxy. Latency-based routing, Redis response caching (10-minute TTL), automatic retries, per-model fallback chains, and client-side JSON schema validation. Manages API keys and usage via PostgreSQL. |
| **[proxq](https://github.com/psyb0t/docker-proxq)** | Async HTTP job queue proxy. Sits in front of LiteLLM at `/q/` — queues inference requests in Redis, returns a job ID instantly, forwards to upstream in the background. Poll `/__jobs/{id}` for status, `/__jobs/{id}/content` for the raw response. Only OpenAI API paths are queued (chat/completions, embeddings, audio, images); everything else passes through directly. |
| **PostgreSQL** | Key management, budget tracking, usage analytics for LiteLLM. |
| **Redis** | LiteLLM response cache and rate limiting. Also used by proxq (DB 1) for job queue storage. |
| **[claudebox](https://github.com/psyb0t/docker-claudebox) ×2** _(optional, `CLAUDEBOX=1` / `CLAUDEBOX_ZAI=1`)_ | Claude Code CLI in API mode. Full agentic loop — shell access, file I/O, tool use, persistent workspaces. One instance uses your OAuth token or Anthropic API key; the other points at z.ai for GLM models. Both expose REST API, OpenAI-compatible endpoint, and MCP server. |
| **[hybrids3](https://github.com/psyb0t/docker-hybrids3)** _(optional, `HYBRIDS3=1`)_ | S3-compatible object storage. Plain HTTP upload/download, boto3-compatible, bearer token auth, auto-expiry, MCP server. The `uploads` bucket is public-read — files are accessible by direct URL without signing. |
| **[stealthy-auto-browse](https://github.com/psyb0t/docker-stealthy-auto-browse)** _(optional, `BROWSER=1`)_ | 5 Camoufox (hardened Firefox) replicas behind HAProxy. Real OS-level mouse and keyboard input via PyAutoGUI — no CDP exposure. Passes Cloudflare, CreepJS, BrowserScan, Pixelscan. Redis cookie sync across replicas. REST API and MCP server. |
| **Ollama** _(optional, `OLLAMA=1`)_ | Local CPU inference. Runs llama3.2:3b, qwen3:4b, smollm2:1.7b, qwen2.5-coder:1.5b, qwen2.5-coder:3b, phi4-mini, gemma4:e2b, gemma3:4b (vision), nuextract-v1.5 (structured extraction), bge-m3, qwen3-embedding:0.6b (embeddings), dolphin-phi. Models are downloaded automatically on first start and cached in `.data/ollama/`. No GPU required. |
| **Ollama CUDA** _(optional, `OLLAMA_CUDA=1`)_ | Local NVIDIA GPU inference. Runs all CPU models on GPU plus: qwen3:8b, gemma4:e4b, qwen2.5-coder:7b, deepseek-coder-v2:16b, llama3.1:8b, qwen3-abliterated:16b, gemma4-abliterated:e4b (uncensored vision), deepseek-r1:8b. Flash attention and KV cache enabled. Shares model storage with CPU ollama — no duplicate downloads. Requires `nvidia-container-toolkit`. |
| **Speaches** _(optional, `SPEACHES=1`)_ | Local CPU audio via [speaches-ai/speaches](https://github.com/speaches-ai/speaches). Transcription: `faster-distil-whisper-large-v3` (multilingual) and `parakeet-tdt-0.6b-v2` (English, ~3400× real-time on CPU). Text-to-speech: `Kokoro-82M` int8 (high-quality, multiple voices). Models cached in `.data/speaches/`. |
| **Speaches CUDA** _(optional, `SPEACHES_CUDA=1`)_ | CUDA-accelerated Whisper STT via speaches. Uses the same model cache as CPU speaches. Shares `.data/speaches/` — no separate download. Requires `nvidia-container-toolkit`. |
| **Qwen3 CUDA TTS** _(optional, `QWEN_TTS_CUDA=1`)_ | CUDA-accelerated TTS via [faster-qwen3-tts](https://github.com/andimarafioti/faster-qwen3-tts). Runs `Qwen3-TTS-12Hz-0.6B-Base` with CUDA graphs. Voice cloning via reference audio. Models cached in `.data/qwen3-tts/`. Requires `nvidia-container-toolkit`. |
| **sd.cpp CPU** _(optional, `SDCPP=1`)_ | Local CPU image generation via [stable-diffusion.cpp](https://github.com/leejet/stable-diffusion.cpp). Go wrapper with OpenAI-compatible `/v1/images/generations` endpoint, model hot-swap, idle timeout auto-unload. Models: sd-turbo, sdxl-turbo. Models cached in `.data/sdcpp/models/`. |
| **sd.cpp CUDA** _(optional, `SDCPP_CUDA=1`)_ | CUDA-accelerated image generation via stable-diffusion.cpp. Same wrapper as CPU with CUDA backend. Models: sd-turbo, sdxl-turbo, sdxl-lightning, flux-schnell, juggernaut-xi. Non-blocking — rejects concurrent requests with 503 instead of queuing (resource manager handles scheduling). Requires `nvidia-container-toolkit`. |
| **MCP tools** _(auto-enabled)_ | Media generation MCP server. Exposes `generate_image` and `generate_tts` tools to any model with function calling. Discovers available models dynamically from LiteLLM. Returns structured JSON with persistent URLs (uploaded to HybridS3) — no base64 blobs. Auto-enabled when any image or TTS provider is active (HuggingFace, OpenAI, Speaches, SDCPP). |
| **[LibreChat](https://github.com/danny-avila/LibreChat)** _(optional, `LIBRECHAT=1`)_ | Web UI for LLM interaction at `/librechat/`. Pre-configured with all LiteLLM models and MCP tools. MongoDB-backed conversation storage. Email/password auth — first registered user becomes admin, then set `LIBRECHAT_ALLOW_REGISTRATION=false` and restart. WebSocket streaming. Configurable via `.env` (registration, rate limits, debug logging, JWT secrets). |
| **cloudflared** _(optional, `CLOUDFLARED=1`)_ | Cloudflare Tunnel. Disabled by default — enable with `CLOUDFLARED=1` in `.env`. Runs a quick tunnel (random `*.trycloudflare.com` URL, no account) or a named tunnel (fixed domain, requires config file and credentials). |

## Security and Exposure

**Network isolation** — all internal services are on a private Docker network with no host port bindings. PostgreSQL, Redis, and LiteLLM are always internal. Optional services (hybrids3, HAProxy, Ollama, Speaches, etc.) join the same private network when enabled. Only nginx is exposed.

**Auth on everything** — every service requires a bearer token. LiteLLM needs `LITELLM_MASTER_KEY`. Claudebox instances each have their own token. Hybrids3 uses per-bucket keys. The stealthy browser cluster has an `AUTH_TOKEN` (defaults to `lulz-4-security` if unset). The MCP tools server validates `MCP_TOOLS_AUTH_TOKEN`. LibreChat has its own email/password auth — first registered user becomes admin; set `LIBRECHAT_ALLOW_REGISTRATION=false` in `.env` and restart after creating your account. The admin UI supports HTTP basic auth with rate limiting.

**No new privileges** — all containers run with `no-new-privileges:true`.

**Pre-flight validation** — `make run` and `make run-bg` validate that any file paths set in `.env` (e.g. `CLOUDFLARED_CONFIG`, `CLOUDFLARED_CREDS`) actually exist before starting Docker. If a path is set but missing, the stack refuses to start with a clear error rather than silently creating a broken directory mount.

**Public exposure** — if you want to reach the gateway from outside, use Cloudflare Tunnel instead of opening ports. Set `CLOUDFLARED=1` in `.env` for a quick `*.trycloudflare.com` URL (no account needed), or configure a named tunnel for a fixed custom domain. Traffic goes through Cloudflare's network before it reaches nginx — DDoS protection and TLS termination included.

→ [Cloudflare Tunnel setup](docs/services-reference.md#cloudflared-optional)

## MCP Tools

Up to 20 tools across 5 optional servers. Any model that supports function calling can invoke them — the model decides when and how to use them based on the prompt.

→ [Full MCP tool reference with parameters](docs/mcp-tools.md)

## Providers and Models

99 models across 15 providers. Six are free tier with no credit card required. Five run locally on your own hardware — CPU or NVIDIA GPU — with no rate limits. Per-model fallback chains route automatically through alternative providers when one fails or rate-limits.

### Routing philosophy

| Priority | Tier | Providers |
| -------- | ---- | --------- |
| 1st | Free cloud | Groq, Cerebras, OpenRouter, HuggingFace, Mistral, Cohere |
| 2nd | Flat-rate | claudebox (Max sub), claudebox-zai (z.ai) |
| 3rd | Pay-per-token | Anthropic, OpenAI |
| Last resort | Local (CPU/CUDA) | Ollama, Speaches, Qwen3 CUDA TTS, sd.cpp |

### Fallback chains

Every model has a fallback chain defined in `litellm/config/fallbacks.json`. When a provider fails or rate-limits, LiteLLM tries the next one automatically. You request one model — the gateway figures out who can actually serve it.

Example: you request `groq-llama-3.3-70b`. Groq returns 429 (rate limited). LiteLLM silently retries with `cerebras-qwen3-235b`. Cerebras is down. It tries `mistral-small`. Mistral responds. You get the response — same format, same schema, no error. The `model` field in the response tells you which provider actually served it.

```
groq-llama-3.3-70b → 429 rate limited
  ↓ fallback
cerebras-qwen3-235b → 503 unavailable
  ↓ fallback
mistral-small → 200 ✓
```

For LLM chat models, chains follow the priority tiers: free cloud first, then flat-rate, then pay-per-token, then local. For image, TTS, and STT models, local models are preferred over paid cloud (they're free and have no rate limits). Small models fall back to other small models. Code models fall back to other code models. Local CUDA models fall back to local CPU models.

Chains are filtered at startup — `make run` regenerates the LiteLLM config and strips out any provider you haven't enabled. If you only have `GROQ=1` and `OLLAMA=1`, the chain skips everything in between.

### Local models (Ollama, CPU)

All local CPU models are last in fallback chains — used when cloud providers are rate-limited or unavailable. Ollama unloads models after 5 minutes of inactivity.

| Model name | Description | RAM |
| ---------- | ----------- | --- |
| `local-ollama-cpu-llama3.2-3b` | General chat — smallest/fastest | ~2GB |
| `local-ollama-cpu-qwen3-4b` | General chat — better quality, thinking mode | ~2.6GB |
| `local-ollama-cpu-smollm2-1.7b` | General chat — absolute tiniest | ~1GB |
| `local-ollama-cpu-qwen2.5-coder-1.5b` | Code — smallest | ~1GB |
| `local-ollama-cpu-qwen2.5-coder-3b` | Code — better quality | ~2GB |
| `local-ollama-cpu-phi4-mini` | General chat (Microsoft Phi 4, 128K ctx) | ~2.5GB |
| `local-ollama-cpu-gemma4-e2b` | General chat + vision (Google Gemma 4, 2.3B effective) | ~7.2GB |
| `local-ollama-cpu-gemma3-4b` | General chat + vision — lightweight (Google Gemma 3) | ~2.6GB |
| `local-ollama-cpu-dolphin-phi` | Uncensored assistant (Microsoft Phi) | ~1.6GB |
| `local-ollama-cpu-nuextract-v1.5` | Structured data extraction — unstructured text → JSON | ~2.3GB |
| `local-ollama-cpu-bge-m3` | Text embeddings — long docs, multilingual (8192 token context) | ~570MB |
| `local-ollama-cpu-qwen3-embed-0.6b` | Text embeddings — modern, efficient | ~500MB |

### Local models (Ollama CUDA — `OLLAMA_CUDA=1`)

CUDA models run with flash attention and quantized KV cache. See [Resource management](#resource-management) below for how VRAM is shared across services.

| Model name | Description | VRAM |
| ---------- | ----------- | ---- |
| `local-ollama-cuda-qwen3-8b` | General chat — thinking mode | ~5GB |
| `local-ollama-cuda-llama3.1-8b` | General chat | ~5GB |
| `local-ollama-cuda-gemma4-e2b` | General chat + vision (Gemma 4, 2.3B effective) | ~7.2GB |
| `local-ollama-cuda-gemma4-e4b` | General chat + vision — higher quality (Gemma 4, 4.5B effective) | ~9.6GB |
| `local-ollama-cuda-qwen2.5-coder-7b` | Code | ~5GB |
| `local-ollama-cuda-deepseek-coder-v2-16b` | Code — MoE, 2.4B active, 160K ctx | ~8.9GB |
| `local-ollama-cuda-deepseek-r1-8b` | Reasoning / thinking model | ~5.2GB |
| `local-ollama-cuda-qwen3-abliterated-16b` | Uncensored — abliterated Qwen3 | ~9.8GB |
| `local-ollama-cuda-gemma4-abliterated-e4b` | Uncensored + vision — abliterated Gemma 4 | ~9.6GB |
| `local-ollama-cuda-dolphin-phi` | Uncensored assistant (tiny) | ~1.6GB |
| `local-ollama-cuda-llama3.2-3b` | General chat (Meta Llama 3.2) | ~2.0GB |
| `local-ollama-cuda-qwen3-4b` | General chat (Qwen3, thinking mode) | ~2.6GB |
| `local-ollama-cuda-smollm2-1.7b` | Tiny general chat (HuggingFace SmolLM2) | ~1.0GB |
| `local-ollama-cuda-qwen2.5-coder-1.5b` | Code completion (tiny) | ~1.0GB |
| `local-ollama-cuda-qwen2.5-coder-3b` | Code completion (small) | ~2.0GB |
| `local-ollama-cuda-phi4-mini` | General chat / reasoning (Microsoft Phi 4) | ~2.5GB |
| `local-ollama-cuda-gemma3-4b` | General chat + vision — lightweight (Google Gemma 3) | ~2.6GB |
| `local-ollama-cuda-nuextract-v1.5` | Structured data extraction — unstructured text → JSON | ~2.3GB |
| `local-ollama-cuda-bge-m3` | Text embeddings — long docs, multilingual (8192 ctx) | ~570MB |
| `local-ollama-cuda-qwen3-embed-0.6b` | Text embeddings — modern, efficient | ~500MB |

### Local transcription (Speaches, CPU — `SPEACHES=1`)

| Model name | Description |
| ---------- | ----------- |
| `local-speaches-whisper-distil-large-v3` | Multilingual, high accuracy |
| `local-speaches-parakeet-tdt-0.6b` | English-only, ~3400× real-time on CPU |

### Local text-to-speech (Speaches, CPU — `SPEACHES=1`)

| Model name | Description |
| ---------- | ----------- |
| `local-speaches-kokoro-tts` | Kokoro 82M int8 — high-quality, multiple voices (af_heart, af_alloy, af_bella, etc.) |

### Local transcription (CUDA — `SPEACHES_CUDA=1`)

| Model name | Description |
| ---------- | ----------- |
| `local-speaches-cuda-whisper-distil-large-v3` | CUDA-accelerated Whisper — same model as CPU, faster inference |
| `local-speaches-cuda-parakeet-tdt-0.6b` | CUDA-accelerated Parakeet TDT |

### Local text-to-speech (CUDA — `QWEN_TTS_CUDA=1`)

| Model name | Description |
| ---------- | ----------- |
| `local-qwen3-cuda-tts` | Qwen3-TTS 0.6B via faster-qwen3-tts — CUDA graphs, voice cloning (voices: alloy, echo, fable) |

### Local image generation (sd.cpp, CPU — `SDCPP=1`)

| Model name | Description |
| ---------- | ----------- |
| `local-sdcpp-cpu-sd-turbo` | SD Turbo — fastest, smallest (~1.7GB) |
| `local-sdcpp-cpu-sdxl-turbo` | SDXL Turbo — better quality, larger (~2.5GB) |

### Local image generation (sd.cpp, CUDA — `SDCPP_CUDA=1`)

| Model name | Description |
| ---------- | ----------- |
| `local-sdcpp-cuda-sd-turbo` | SD Turbo — fastest on GPU (~1.7GB VRAM) |
| `local-sdcpp-cuda-sdxl-turbo` | SDXL Turbo — better quality (~2.5GB VRAM) |
| `local-sdcpp-cuda-sdxl-lightning` | SDXL Lightning — fast, high quality (~2.5GB VRAM) |
| `local-sdcpp-cuda-flux-schnell` | FLUX Schnell — best quality, largest (~7GB VRAM) |
| `local-sdcpp-cuda-juggernaut-xi` | Juggernaut XI — photorealistic SDXL fine-tune (~2.5GB VRAM) |

Models auto-download on first use and cache in `.data/sdcpp/models/`.

→ [Full provider and model list](docs/providers.md)

### Resource management

Local services share limited hardware — a single GPU can't run an LLM, an image generator, and a TTS model simultaneously. The platform handles this automatically so you never have to think about it.

**Automatic unloading** — every local service unloads idle models after a configurable timeout. Ollama unloads after 5 minutes by default. sd.cpp unloads after 5 minutes (`SDCPP_IDLE_TIMEOUT` / `SDCPP_CUDA_IDLE_TIMEOUT`). Speaches and Qwen3-TTS unload on demand. This means VRAM and RAM are only held while a model is actively serving or within its idle window.

**Hardware semaphores** — a LiteLLM callback (`resource_manager.py`) enforces mutual exclusion per hardware. An `asyncio.Semaphore(1)` ensures only one CUDA job runs at a time across all groups (LLM, image gen, TTS, STT). The same applies on CPU. If a CUDA image generation request arrives while a CUDA LLM model is loaded, the request waits for the semaphore, then the resource manager unloads the LLM before the image generation proceeds. This prevents GPU OOM without any manual intervention.

**Competing-group unload** — before each local request, all other groups on the same hardware are told to free resources. For example, a `local-sdcpp-cuda-flux-schnell` request will unload ollama-cuda models, speaches-cuda STT models, and qwen3-cuda-tts before starting. Each service has its own unload mechanism: Ollama uses `keep_alive: 0`, sd.cpp uses `/sdcpp/v1/unload`, Speaches uses `DELETE /api/ps/{model}`, and Qwen3-TTS uses `/unload`.

**Auto-load on demand** — models load automatically when needed. Send a request to any model and its service loads it on the fly. No pre-loading, no manual model management. The sd.cpp wrapper accepts `/v1/images/generations` requests even when no model is loaded — it starts the sd-server subprocess with the right model automatically.

**Non-blocking rejection** — the sd.cpp wrapper uses `TryLock` instead of blocking. If a generation or model swap is already in progress, new requests get an immediate 503 instead of queuing indefinitely. The resource manager semaphore handles scheduling at a higher level — requests wait at the LiteLLM layer, not inside individual services.

The net effect: you can freely mix LLM chat, image generation, TTS, and STT requests across local services. The platform queues, unloads, loads, and routes automatically. The only constraint is throughput — one local job per hardware at a time.

## Setup

### 1. Clone

```bash
git clone https://github.com/psyb0t/aigate
cd aigate
```

### 2. Configure

```bash
cp .env.example .env
```

Fill in the values — every variable is documented with comments in [`.env.example`](.env.example).

Everything is opt-in via flags in `.env`. API keys are stored separately and never activate anything on their own — set the flag to `1` to enable:

| Flag | What it enables |
| ---- | --------------- |
| `OPENAI=1` | OpenAI models (gpt-4o, o3, DALL-E, Whisper, TTS) |
| `ANTHROPIC=1` | Direct Anthropic API models |
| `CLAUDEBOX=1` | claudebox service + models + MCP server (Claude Code via OAuth or API key) |
| `CLAUDEBOX_ZAI=1` | claudebox-zai service + GLM models + MCP server (via z.ai) |
| `CEREBRAS=1` | Cerebras models (free tier) |
| `OPENROUTER=1` | OpenRouter models (free tier) |
| `HUGGINGFACE=1` | HuggingFace models (free tier) |
| `MISTRAL=1` | Mistral AI models (free: 1B tokens/month) |
| `COHERE=1` | Cohere models (free: 1K req/day) |
| `GROQ=1` | Groq models (free tier) |
| `OLLAMA=1` | Local Ollama CPU inference (~6GB+ RAM) |
| `OLLAMA_CUDA=1` | Local Ollama NVIDIA GPU inference (requires `nvidia-container-toolkit`) |
| `SPEACHES=1` | Local Speaches CPU transcription/TTS (~4GB RAM) |
| `SPEACHES_CUDA=1` | Local CUDA-accelerated STT (requires `nvidia-container-toolkit`) |
| `QWEN_TTS_CUDA=1` | Local CUDA-accelerated TTS via Qwen3 (voice cloning, requires `nvidia-container-toolkit`) |
| `SDCPP=1` | Local stable-diffusion.cpp CPU image generation |
| `SDCPP_CUDA=1` | Local stable-diffusion.cpp CUDA image generation (requires `nvidia-container-toolkit`) |
| `HYBRIDS3=1` | Object storage service + MCP server (S3-compatible, plain HTTP, auto-expiry) |
| `BROWSER=1` | Stealth browser cluster + MCP server (5 replicas, ~1.3GB RAM) |
| `LIBRECHAT=1` | LibreChat web UI at `/librechat/` with all models and MCP tools |
| `CLOUDFLARED=1` | Cloudflare Tunnel |

`make run` regenerates `litellm/config.yaml` before starting — only enabled providers are included, fallback chains are filtered to match.

If `CLOUDFLARED_CONFIG` or `CLOUDFLARED_CREDS` are set, `make run`/`make run-bg` will verify those files exist before starting. A missing file causes an immediate error — better than Docker silently mounting a directory instead.

### 3. Set resource limits

```bash
make limits
```

Reads your system's RAM, swap, and CPU core count and writes a `.env.limits` file with recommended `mem_limit`, `memswap_limit`, and `cpus` for every service. The Makefile picks this up automatically — no other steps needed.

Allocations are **proportional to your enabled services** — enabling more services means each gets a smaller slice. The script reads your `.env` flags (`CUDA`, `SPEACHES`, `OLLAMA`, `BROWSER`, etc.) and only counts active services toward the RAM budget. Re-run it any time you enable or disable a service, move to a different server, or change your hardware.

CUDA services (`ollama-cuda`, `speaches-cuda`, `qwen3-cuda-tts`, `sdcpp-cuda`) are [resource-manager-aware](#resource-management) — only one has models loaded at a time, so the budget counts the largest plus small idle overhead for the others.

Set `MAXUSE` to cap the entire stack to a percentage of your machine's resources — useful when you're sharing the server with other workloads:

```bash
make limits            # use 100% of system resources (default)
MAXUSE=80 make limits  # cap the whole stack at 80% of RAM, swap, and CPU
```

Swap allocation is proportional: each service gets a swap budget matching its share of total RAM. If your server has abundant swap (e.g. 1TB on 16GB RAM), services can use up to 10× their RAM limit in swap — they'll crawl, but they won't get OOM-killed. Minimum is always 2×.

The `.env.limits` file is gitignored. Each server maintains its own.

### 4. Start

```bash
make run-bg   # detached (background)
make run      # foreground with logs
```

Gateway is at `http://localhost:4000`. Admin UI at `http://localhost:4000/ui/`. LibreChat web UI at `http://localhost:4000/librechat/` (if `LIBRECHAT=1`).

On first start, Ollama will pull all local models in the background. Speaches models (whisper, parakeet, kokoro) are pre-downloaded automatically. Both cache to `.data/` and won't re-download on restart.

## Usage

```bash
# cloud provider (free tier, auto-fallback on rate limit)
curl http://localhost:4000/chat/completions \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{"model": "cerebras-qwen3-235b", "messages": [{"role": "user", "content": "hello"}]}'

# local model (no network, no rate limits)
curl http://localhost:4000/chat/completions \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{"model": "local-ollama-cpu-llama3.2-3b", "messages": [{"role": "user", "content": "hello"}]}'

# image generation
curl http://localhost:4000/images/generations \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{"model": "hf-flux-schnell", "prompt": "a cat riding a skateboard"}'

# local image generation (CUDA — sd-turbo, fast)
curl http://localhost:4000/images/generations \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{"model": "local-sdcpp-cuda-sd-turbo", "prompt": "a red panda in a forest", "size": "512x512"}'

# transcription (cloud — Groq Whisper, fast)
curl http://localhost:4000/audio/transcriptions \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -F "model=groq-whisper-large-v3" -F "file=@audio.mp3"

# local transcription (Parakeet — English, insanely fast)
curl http://localhost:4000/audio/transcriptions \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -F "model=local-speaches-parakeet-tdt-0.6b" -F "file=@audio.mp3"

# text-to-speech (local CPU — Kokoro, many voices)
curl http://localhost:4000/audio/speech \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{"model": "local-speaches-kokoro-tts", "input": "Hello world", "voice": "af_heart"}' \
  -o speech.mp3

# text-to-speech (local CUDA — Qwen3-TTS, voice cloning)
curl http://localhost:4000/audio/speech \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{"model": "local-qwen3-cuda-tts", "input": "Hello world", "voice": "alloy"}' \
  -o speech.mp3

# text embeddings (local)
curl http://localhost:4000/embeddings \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{"model": "local-ollama-cpu-bge-m3", "input": "your text here"}'
```

### Async (via proxq)

Any request sent through `/q/` is queued and processed in the background — useful for long-running inference that would otherwise time out.

```bash
# submit — returns instantly with a job ID
curl http://localhost:4000/q/v1/chat/completions \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{"model": "cerebras-qwen3-235b", "messages": [{"role": "user", "content": "write a novel"}]}'
# → 202 {"jobId": "550e8400-e29b-41d4-a716-446655440000"}

# check status
curl http://localhost:4000/q/__jobs/550e8400-e29b-41d4-a716-446655440000 \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY"
# → {"id": "...", "status": "running"}

# get the response (replays upstream response exactly)
curl http://localhost:4000/q/__jobs/550e8400-e29b-41d4-a716-446655440000/content \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY"
# → {"choices": [...], "usage": {...}}

# cancel
curl -X DELETE http://localhost:4000/q/__jobs/550e8400-e29b-41d4-a716-446655440000 \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY"
```

Only OpenAI API paths (`/v1/chat/completions`, `/v1/embeddings`, `/v1/audio/*`, `/v1/images/*`, `/v1/responses`) are queued. Health checks, model lists, key management, and admin UI requests pass through to LiteLLM directly.

Configurable via `.env`:

| Variable | Default | What it does |
| -------- | ------- | ------------ |
| `PROXQ_CONCURRENCY` | `10` | How many workers process jobs simultaneously |
| `PROXQ_TASK_RETENTION` | `1h` | How long completed jobs stay in Redis |
| `PROXQ_UPSTREAM_TIMEOUT` | `10m` | Max time to wait for LiteLLM to respond |
| `PROXQ_MAX_RETRIES` | `0` | Retry failed upstream calls (0 = no retries) |
| `PROXQ_RETRY_DELAY` | `30s` | Delay between retries (0 = exponential backoff) |
| `PROXQ_MAX_BODY_SIZE` | `10MB` | Max request body size for queued requests |
| `PROXQ_DIRECT_PROXY_THRESHOLD` | `10MB` | Bodies larger than this bypass the queue |
| `PROXQ_CACHE_MODE` | `none` | `none`, `memory` (LRU), or `redis` — cache upstream responses |
| `PROXQ_CACHE_TTL` | `5m` | How long cached responses stay fresh |
| `PROXQ_CACHE_MAX_ENTRIES` | `10000` | Max entries for in-memory LRU cache |

→ [Full usage guide](docs/usage.md) — browser automation, object storage, agentic claudebox tasks, vision, streaming, Python SDK examples

## Services Reference

All endpoints, auth requirements, request/response formats, and config options.

→ [Services reference](docs/services-reference.md)

## Makefile

```bash
make run           # start stack in foreground (validates file paths, rebuilds litellm config)
make run-bg        # start stack in background (validates file paths, rebuilds litellm config)
make down          # stop everything
make restart       # full restart
make logs          # follow logs
make build-config  # regenerate litellm/config.yaml from fragments (runs automatically on make run)
make limits              # generate .env.limits with recommended resource limits for this machine
MAXUSE=80 make limits    # same but cap the stack at 80% of total RAM/swap/CPU
make test          # run test suite (stack must be running)
```

## Testing

```bash
make test
```

121 tests covering health, routing, auth, MCP, MCP media tools, storage CRUD, browser automation, claudebox, proxq async job lifecycle, local TTS/STT round-trips, CUDA audio, resource manager unload verification, local image generation (CPU/CUDA), MCP-to-sdcpp integration, LLM-to-MCP e2e tool calling, and security. Designed for zero/minimal token usage.

→ [Testing guide](docs/testing.md)

## Logs and Debugging

```bash
make logs                           # follow all logs
docker compose logs litellm -f      # follow one service
docker compose logs --since 5m      # last 5 minutes
```

LiteLLM logs every request with the model name, provider, latency, and token usage. When a fallback triggers, you'll see the failed provider and which one took over. The resource manager logs every semaphore acquire/release and every competing-group unload — search for `[resource_manager]` in the logs.

Per-service debug options:

| Variable | Default | What it does |
| -------- | ------- | ------------ |
| `SDCPP_VERBOSE` / `SDCPP_CUDA_VERBOSE` | `false` | sd.cpp wrapper debug logging |
| `SDCPP_LOG_LEVEL` / `SDCPP_CUDA_LOG_LEVEL` | `info` | sd.cpp wrapper log level |
| `LIBRECHAT_DEBUG_LOGGING` | `true` | LibreChat verbose logging |

Ollama and Speaches log to stdout by default — visible in `docker compose logs`.

## Troubleshooting

**GPU out of memory** — the resource manager should prevent this, but if it happens: check `docker compose logs litellm | grep resource_manager` to verify the semaphore is working. Make sure you're not bypassing LiteLLM by hitting services directly. Run `make limits` to regenerate memory limits.

**Model download stuck** — Ollama pulls models in the background on first start. Large models (8B+) can take a while. Check progress with `docker compose logs ollama -f`. sd.cpp models download via `sdcpp-pull` — check `docker compose logs sdcpp-pull -f`. If a download fails, delete the partial file from `.data/` and restart.

**"Connection refused" or "Bad Gateway"** — the service isn't ready yet. Check `docker compose ps` for unhealthy containers. Check logs for the specific service. Common cause: a dependent service (PostgreSQL, Redis) hasn't started yet — Docker healthchecks handle this, but on slow machines the start period may not be enough.

**Slow local inference** — expected if the resource manager just swapped models. The first request after a swap includes model load time (seconds for Ollama, up to minutes for sd.cpp FLUX on CPU). Subsequent requests are fast until the idle timeout unloads the model. Increase idle timeouts to keep models warm longer.

**Rate limited on every provider** — all free tiers have limits. Groq: ~30 req/min. Cerebras: ~30 req/min. HuggingFace: varies. If you're hitting all of them, the fallback chain will eventually land on a paid provider or local model. Check `docker compose logs litellm | grep fallback` to see the chain in action. Consider enabling more free providers to spread the load.

**Tests failing** — make sure the stack is running (`make run-bg`) and healthy (`docker compose ps`). Tests require the services they're testing to be enabled — `OLLAMA_CUDA=1` for Ollama CUDA tests, `SDCPP_CUDA=1` for sd.cpp CUDA tests, etc. Run `bash test.sh --help` to see which tests are available and their requirements.

## License

WTFPL
