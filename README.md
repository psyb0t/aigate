# aigate

Your own AI infrastructure. One compose file. One endpoint. Everything.

82 models across 12 providers behind a single OpenAI-compatible API — point any existing client at `http://localhost:4000` and it just works. Six of those providers are completely free. Two more run entirely on your own hardware with no network calls, no rate limits, and no usage costs. The gateway burns through providers in priority order and falls back automatically when one rate-limits or fails, so you're never paying for tokens you could have gotten free.

That's the routing. The real part is what the models can *do*. Four MCP servers are wired directly into the gateway — 34 tools any model with function calling can invoke autonomously. A stealth browser cluster (5 Camoufox replicas, real OS-level mouse and keyboard, zero CDP exposure) that passes Cloudflare, CreepJS, and every other bot detector we've thrown at it. S3-compatible object storage with public-read URLs, presigned links, and auto-expiry. Two agentic Claude Code instances — one on your Claude subscription or API key, one running GLM models through z.ai — each with a full shell, persistent workspaces, and file I/O. Ask a Groq model to research something and it opens a browser, reads pages, saves files, and comes back with an answer. The model orchestrates. You just prompt.

Security is not an afterthought. Internal services are network-isolated — PostgreSQL, Redis, hybrids3, and the browser cluster have no host ports, period. Every endpoint requires auth. When you want to expose the gateway publicly, Cloudflare Tunnel handles it: one env var, no open ports, Cloudflare's DDoS protection and TLS in front of everything.

`make run-bg`. That's the whole install.

## Architecture

```
client
  ▼
cloudflared (optional)
  ▼
nginx :4000
  ├─► /claudebox/            → claudebox (Claude Code, OAuth or API key)
  ├─► /claudebox-zai/        → claudebox-zai (Claude Code, GLM via z.ai)
  ├─► /stealthy-auto-browse/ → HAProxy → [browser ×5]
  ├─► /storage/              → hybrids3
  └─► /                      → LiteLLM
                                  ├─ Groq              (free)
                                  ├─ Cerebras           (free)
                                  ├─ OpenRouter         (free tier)
                                  ├─ HuggingFace        (free)
                                  ├─ Mistral            (free: 1B tokens/month)
                                  ├─ Cohere             (free: 1K req/day)
                                  ├─ Ollama             (local, CPU, no limits)
                                  ├─ Speaches           (local, CPU, transcription)
                                  ├─ claudebox          (flat-rate, Max sub or API key)
                                  ├─ claudebox-zai      (flat-rate, z.ai)
                                  ├─ Anthropic          (optional, pay-per-token)
                                  └─ OpenAI             (optional, pay-per-token)

MCP servers (34 tools, available to all models):
  ├─ stealthy_auto_browse  (17 tools) — browser navigation, clicks, typing, screenshots
  ├─ hybrids3              (7 tools)  — file upload, download, list, delete, presign
  ├─ claudebox             (5 tools)  — agentic Claude Code via OAuth or API key
  └─ claudebox_zai         (5 tools)  — agentic Claude Code via z.ai/GLM
```

All persistent data lives under `.data/` (bind mounts). The directory structure is tracked in git via `.gitkeep` files so the right directories exist on a fresh clone — contents are gitignored.

Notable writable locations:

| Path | Used by | Notes |
| ---- | ------- | ----- |
| `.data/claudebox/config/.always-skills/` | claudebox | Drop `<name>/SKILL.md` files here — injected into every Claude session automatically |
| `.data/claudebox-zai/config/.always-skills/` | claudebox-zai | Same, for the z.ai instance |
| `.data/claudebox/workspaces/` | claudebox | Persistent task workspaces |
| `.data/claudebox-zai/workspaces/` | claudebox-zai | Persistent task workspaces |
| `.data/hybrids3/` | hybrids3 | Object storage data |
| `.data/nginx/` | nginx-auth-init | Generated htpasswd (from `LITELLM_UI_BASIC_AUTH`) |
| `.data/ollama/` | ollama | Downloaded model weights |
| `.data/speaches/` | speaches | Downloaded Whisper and Parakeet model weights (HuggingFace cache) |
| `.data/cloudflared/` | cloudflared | Tunnel config and credentials (if using named tunnel) |

## Services

| Service | Description |
| ------- | ----------- |
| **Nginx** | Single entry point on port 4000. Routes by URL path, enforces rate limits on the admin UI, and optionally adds HTTP basic auth. All config is embedded inline. |
| **LiteLLM** | OpenAI-compatible API proxy. Latency-based routing, Redis response caching (10-minute TTL), automatic retries, and per-model fallback chains. Manages API keys and usage via PostgreSQL. |
| **PostgreSQL** | Key management, budget tracking, usage analytics for LiteLLM. |
| **Redis** | LiteLLM response cache and rate limiting. |
| **[claudebox](https://github.com/psyb0t/docker-claudebox) ×2** | Claude Code CLI in API mode. Full agentic loop — shell access, file I/O, tool use, persistent workspaces. One instance uses your OAuth token or Anthropic API key; the other points at z.ai for GLM models. Both expose REST API, OpenAI-compatible endpoint, and MCP server. |
| **[hybrids3](https://github.com/psyb0t/docker-hybrids3)** | S3-compatible object storage. Plain HTTP upload/download, boto3-compatible, bearer token auth, auto-expiry, MCP server. The `uploads` bucket is public-read — files are accessible by direct URL without signing. |
| **[stealthy-auto-browse](https://github.com/psyb0t/docker-stealthy-auto-browse)** | 5 Camoufox (hardened Firefox) replicas behind HAProxy. Real OS-level mouse and keyboard input via PyAutoGUI — no CDP exposure. Passes Cloudflare, CreepJS, BrowserScan, Pixelscan. Redis cookie sync across replicas. REST API and MCP server. |
| **Ollama** | Local CPU inference. Runs llama3.2:3b, qwen3:4b, smollm2:1.7b, qwen2.5-coder:1.5b, qwen2.5-coder:3b, phi3.5, moondream (vision), nomic-embed-text, bge-m3, and qwen3-embedding:0.6b (embeddings). Models are downloaded automatically on first start and cached in `.data/ollama/`. No GPU required — sized for CPU with reasonable RAM. |
| **Speaches** | Local CPU audio via [speaches-ai/speaches](https://github.com/speaches-ai/speaches). Transcription: `faster-distil-whisper-large-v3` (multilingual) and `parakeet-tdt-0.6b-v2` (English, ~3400× real-time on CPU). Text-to-speech: `Kokoro-82M` int8 (high-quality, multiple voices). All models are pre-downloaded on first start and cached in `.data/speaches/`. |
| **cloudflared** _(optional)_ | Cloudflare Tunnel. Disabled by default — enable with `CLOUDFLARED=1` in `.env`. Runs a quick tunnel (random `*.trycloudflare.com` URL, no account) or a named tunnel (fixed domain, requires config file and credentials). |

## Security and Exposure

**Network isolation** — internal services (PostgreSQL, Redis, hybrids3, HAProxy, Ollama, Speaches) are on a private Docker network with no host port bindings. They're unreachable from outside the stack. Only nginx is exposed.

**Auth on everything** — every service requires a bearer token. LiteLLM needs `LITELLM_MASTER_KEY`. Claudebox instances each have their own token. Hybrids3 uses per-bucket keys. The stealthy browser cluster has an optional `AUTH_TOKEN`. The admin UI supports HTTP basic auth with rate limiting (5 req/min).

**No new privileges** — all containers run with `no-new-privileges:true`.

**Pre-flight validation** — `make run` and `make run-bg` validate that any file paths set in `.env` (e.g. `CLOUDFLARED_CONFIG`, `CLOUDFLARED_CREDS`) actually exist before starting Docker. If a path is set but missing, the stack refuses to start with a clear error rather than silently creating a broken directory mount.

**Public exposure** — if you want to reach the gateway from outside, use Cloudflare Tunnel instead of opening ports. Set `CLOUDFLARED=1` in `.env` for a quick `*.trycloudflare.com` URL (no account needed), or configure a named tunnel for a fixed custom domain. Traffic goes through Cloudflare's network before it reaches nginx — DDoS protection and TLS termination included.

→ [Cloudflare Tunnel setup](docs/services-reference.md#cloudflared-optional)

## MCP Tools

34 tools across 4 servers. Any model that supports function calling can invoke them — the model decides when and how to use them based on the prompt.

→ [Full MCP tool reference with parameters](docs/mcp-tools.md)

## Providers and Models

82 models across 12 providers. Six are free tier with no credit card required. Two run locally on CPU with no rate limits. Model groups (`fast`, `smart`, `vision`, `image-gen`, `transcription`) route automatically through per-provider fallback chains.

### Routing philosophy

| Priority | Tier | Providers |
| -------- | ---- | --------- |
| 1st | Free cloud | Groq, Cerebras, OpenRouter, HuggingFace, Mistral, Cohere |
| 2nd | Flat-rate | claudebox (Max sub), claudebox-zai (z.ai) |
| 3rd | Pay-per-token | Anthropic, OpenAI |
| Last resort | Local CPU | Ollama, Speaches |

### Model groups

| Group | Description | Models |
| ----- | ----------- | ------ |
| `fast` | Small, low-latency chat | groq-llama-3.1-8b, cerebras-llama-3.1-8b, ministral-8b, cohere-command-r7b, and more |
| `smart` | Large, high-capability chat | cerebras-qwen3-235b, mistral-large, or-hermes-3-405b, claudebox-sonnet, and more |
| `vision` | Multimodal / image understanding | groq-llama-4-scout, hf-llava, hf-qwen-vl-72b, claudebox-sonnet, openai-gpt-4o, local-ollama-moondream |
| `image-gen` | Image generation | hf-flux-schnell, hf-flux-dev, hf-sd-3.5-turbo, openai-dall-e-3, openai-gpt-image-1 |
| `transcription` | Speech-to-text | groq-whisper-large-v3, voxtral-small, openai-whisper, local-speaches-whisper-distil-large-v3, local-speaches-parakeet-tdt-0.6b |

### Local models (Ollama, CPU)

All local models are last in fallback chains — used when cloud providers are rate-limited or unavailable. Ollama unloads models after 5 minutes of inactivity, so RAM is only consumed when a model is in use.

| Model name | Description | RAM |
| ---------- | ----------- | --- |
| `local-ollama-llama3.2-3b` | General chat — smallest/fastest | ~2GB |
| `local-ollama-qwen3-4b` | General chat — better quality, thinking mode | ~2.6GB |
| `local-ollama-smollm2-1.7b` | General chat — absolute tiniest | ~1GB |
| `local-ollama-qwen2.5-coder-1.5b` | Code — smallest | ~1GB |
| `local-ollama-qwen2.5-coder-3b` | Code — better quality | ~2GB |
| `local-ollama-phi3.5` | General chat (Microsoft) | ~2.2GB |
| `local-ollama-moondream` | Vision / image captioning | ~1.7GB |
| `local-ollama-nomic-embed` | Text embeddings — fastest, smallest (270MB, 512 token context) | ~270MB |
| `local-ollama-bge-m3` | Text embeddings — long docs, multilingual (8192 token context) | ~570MB |
| `local-ollama-qwen3-embed-0.6b` | Text embeddings — modern, efficient | ~500MB |

### Local transcription (Speaches, CPU)

| Model name | Description |
| ---------- | ----------- |
| `local-speaches-whisper-distil-large-v3` | Multilingual, high accuracy |
| `local-speaches-parakeet-tdt-0.6b` | English-only, ~3400× real-time on CPU |

### Local text-to-speech (Speaches, CPU)

| Model name | Description |
| ---------- | ----------- |
| `local-speaches-kokoro-tts` | Kokoro 82M int8 — high-quality, multiple voices (af_heart, af_alloy, af_bella, etc.) |

→ [Full provider and model list](docs/providers.md)

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

Edit `.env`:

```env
# Required — gateway master key
LITELLM_MASTER_KEY=sk-your-secret-here

# Required — claudebox auth tokens
CLAUDEBOX_API_TOKEN=       # openssl rand -hex 32
CLAUDEBOX_ZAI_API_TOKEN=   # openssl rand -hex 32

# Required — claudebox auth (OAuth token OR Anthropic API key, one is enough)
CLAUDE_CODE_OAUTH_TOKEN=sk-ant-oat01-...    # claude setup-token
# CLAUDEBOX_ANTHROPIC_API_KEY=sk-ant-...   # or use a pay-per-use API key

# Required — z.ai auth (powers claudebox-glm-* models)
ZAI_AUTH_TOKEN=...    # https://z.ai

# Required — free tier providers
GROQ_API_KEY=gsk_...            # https://console.groq.com
HF_TOKEN=hf_...                 # https://huggingface.co/settings/tokens
CEREBRAS_API_KEY=csk-...        # https://cloud.cerebras.ai
OPENROUTER_API_KEY=sk-or-v1-... # https://openrouter.ai
MISTRAL_API_KEY=...             # https://console.mistral.ai
COHERE_API_KEY=...              # https://dashboard.cohere.com

# Optional — object storage keys
HYBRIDS3_MASTER_KEY=    # openssl rand -hex 32
HYBRIDS3_UPLOADS_KEY=   # openssl rand -hex 32

# Optional — browser cluster
STEALTHY_AUTO_BROWSE_AUTH_TOKEN=     # leave empty to disable auth
STEALTHY_AUTO_BROWSE_NUM_REPLICAS=5

# Optional — Cloudflare Tunnel
CLOUDFLARED=           # set to 1 to enable
CLOUDFLARED_CONFIG=    # path to tunnel config.yml (relative or absolute)
CLOUDFLARED_CREDS=     # path to credentials.json (relative or absolute)

# Optional — LiteLLM admin UI basic auth
LITELLM_UI_BASIC_AUTH=     # user:password format

# Optional — paid providers
# ANTHROPIC_API_KEY=sk-ant-...
# OPENAI_API_KEY=sk-...

# Infrastructure
POSTGRES_PASSWORD=...
REDIS_PASSWORD=...
LITELLM_WORKERS=4
```

Profiles are auto-detected from `.env`:
- `claudebox` profile activates when `CLAUDE_CODE_OAUTH_TOKEN` or `CLAUDEBOX_ANTHROPIC_API_KEY` is set
- `claudebox-zai` profile activates when `ZAI_AUTH_TOKEN` is set
- `cloudflared` profile activates when `CLOUDFLARED=1` is set

If `CLOUDFLARED_CONFIG` or `CLOUDFLARED_CREDS` are set, `make run`/`make run-bg` will verify those files exist before starting. A missing file causes an immediate error — better than Docker silently mounting a directory instead.

### 3. Set resource limits

```bash
make limits
```

Reads your system's RAM, swap, and CPU core count and writes a `.env.limits` file with recommended `mem_limit`, `memswap_limit`, and `cpus` for every service. The Makefile picks this up automatically — no other steps needed. Re-run it any time you move to a different server or change your hardware.

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

Gateway is at `http://localhost:4000`. Admin UI at `http://localhost:4000/ui/`.

On first start, Ollama will pull all local models in the background. Speaches models (whisper, parakeet, kokoro) are pre-downloaded automatically. Both cache to `.data/` and won't re-download on restart.

## Usage

```bash
# best available free smart model
curl http://localhost:4000/chat/completions \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{"model": "smart", "messages": [{"role": "user", "content": "hello"}]}'

# specific provider
curl http://localhost:4000/chat/completions \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{"model": "cerebras-qwen3-235b", "messages": [{"role": "user", "content": "hello"}]}'

# local model (no network, no rate limits)
curl http://localhost:4000/chat/completions \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{"model": "local-ollama-llama3.2-3b", "messages": [{"role": "user", "content": "hello"}]}'

# image generation
curl http://localhost:4000/images/generations \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{"model": "image-gen", "prompt": "a cat riding a skateboard"}'

# transcription (routes through groq → speaches → openai)
curl http://localhost:4000/audio/transcriptions \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -F "model=transcription" -F "file=@audio.mp3"

# local transcription directly (Parakeet — English, insanely fast)
curl http://localhost:4000/audio/transcriptions \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -F "model=local-speaches-parakeet-tdt-0.6b" -F "file=@audio.mp3"

# text-to-speech (local — Kokoro, multiple voices)
curl http://localhost:4000/audio/speech \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{"model": "local-speaches-kokoro-tts", "input": "Hello world", "voice": "af_heart"}' \
  -o speech.mp3

# text embeddings (local)
curl http://localhost:4000/embeddings \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{"model": "local-ollama-nomic-embed", "input": "your text here"}'
```

→ [Full usage guide](docs/usage.md) — browser automation, object storage, agentic claudebox tasks, vision, streaming, Python SDK examples

## Services Reference

All endpoints, auth requirements, request/response formats, and config options.

→ [Services reference](docs/services-reference.md)

## Makefile

```bash
make run      # start stack in foreground (validates file paths first)
make run-bg   # start stack in background (validates file paths first)
make down     # stop everything
make restart  # full restart
make logs     # follow logs
make limits          # generate .env.limits with recommended resource limits for this machine
MAXUSE=80 make limits  # same but cap the stack at 80% of total RAM/swap/CPU
make test     # run test suite (stack must be running)
```

## Testing

```bash
make test
```

Covers health, routing, auth, MCP, storage CRUD, browser automation, claudebox, and security. Designed for zero/minimal token usage.

→ [Testing guide](docs/testing.md)

## License

WTFPL
