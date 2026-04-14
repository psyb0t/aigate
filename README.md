# aigate

Your own AI infrastructure. One compose file. One endpoint. Everything.

69 models across 10 providers behind a single OpenAI-compatible API — point any existing client at `http://localhost:4000` and it just works. Six of those providers are completely free. The gateway burns through them in priority order and falls back automatically when one rate-limits or fails, so you're never paying for tokens you could have gotten free.

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
                                  ├─ Groq          (free)
                                  ├─ Cerebras      (free)
                                  ├─ OpenRouter     (free)
                                  ├─ HuggingFace    (free)
                                  ├─ Mistral        (free: 1B tokens/month)
                                  ├─ Cohere         (free: 1K req/day)
                                  ├─ claudebox      (paid, sub or API key)
                                  ├─ claudebox-zai  (paid, z.ai)
                                  ├─ Anthropic      (optional, paid)
                                  └─ OpenAI         (optional, paid)

MCP servers (34 tools, available to all models):
  ├─ stealthy_auto_browse  (17 tools) — browser navigation, clicks, typing, screenshots
  ├─ hybrids3              (7 tools)  — file upload, download, list, delete, presign
  ├─ claudebox             (5 tools)  — agentic Claude Code via OAuth or API key
  └─ claudebox_zai         (5 tools)  — agentic Claude Code via z.ai/GLM
```

All persistent data lives under `.data/` (bind mounts). The directory structure is tracked in git via `.gitkeep` files so the right directories exist on a fresh clone — contents are gitignored. Everything is defined in a single `docker-compose.yml` with all service configs embedded inline — no external config files.

Notable writable locations:

| Path                                         | Used by         | Notes                                                                                 |
| -------------------------------------------- | --------------- | ------------------------------------------------------------------------------------- |
| `.data/claudebox/config/.always-skills/`     | claudebox       | Drop `<name>/SKILL.md` files here — injected into every Claude session automatically |
| `.data/claudebox-zai/config/.always-skills/` | claudebox-zai   | Same, for the z.ai instance                                                           |
| `.data/claudebox/workspaces/`                | claudebox       | Persistent task workspaces                                                            |
| `.data/claudebox-zai/workspaces/`            | claudebox-zai   | Persistent task workspaces                                                            |
| `.data/hybrids3/`                            | hybrids3        | Object storage data                                                                   |
| `.data/nginx/`                               | nginx-auth-init | Generated htpasswd (from `LITELLM_UI_BASIC_AUTH`)                                     |

## Services

| Service                                                                           | Description                                                                                                                                                                                                                                                          |
| --------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Nginx**                                                                         | Single entry point on port 4000. Routes by URL path, enforces rate limits on the admin UI, and optionally adds HTTP basic auth. All config is embedded inline.                                                                                                       |
| **LiteLLM**                                                                       | OpenAI-compatible API proxy. Latency-based routing, Redis response caching (10-minute TTL), automatic retries, and per-model fallback chains. Manages API keys and usage via PostgreSQL.                                                                             |
| **PostgreSQL**                                                                    | Key management, budget tracking, usage analytics for LiteLLM.                                                                                                                                                                                                       |
| **Redis**                                                                         | LiteLLM response cache and rate limiting.                                                                                                                                                                                                                            |
| **[claudebox](https://github.com/psyb0t/docker-claudebox)** ×2                    | Claude Code CLI in API mode. Full agentic loop — shell access, file I/O, tool use, persistent workspaces. One instance uses your OAuth token or Anthropic API key; the other points at z.ai for GLM models. Both expose REST API, OpenAI-compatible endpoint, and MCP server. |
| **[hybrids3](https://github.com/psyb0t/docker-hybrids3)**                         | S3-compatible object storage. Plain HTTP upload/download, boto3-compatible, bearer token auth, auto-expiry, MCP server. The `uploads` bucket is public-read — files are accessible by direct URL without signing.                                                   |
| **[stealthy-auto-browse](https://github.com/psyb0t/docker-stealthy-auto-browse)** | 5 Camoufox (hardened Firefox) replicas behind HAProxy. Real OS-level mouse and keyboard input via PyAutoGUI — no CDP exposure. Passes Cloudflare, CreepJS, BrowserScan, Pixelscan. Redis cookie sync across replicas. REST API and MCP server.                       |
| **cloudflared** _(optional)_                                                      | Cloudflare Tunnel. Disabled by default — enable with `COMPOSE_PROFILES=cloudflared`. Quick tunnel (random `*.trycloudflare.com` URL, no account) or named tunnel (fixed domain).                                                                                     |

## Security and Exposure

**Network isolation** — internal services (PostgreSQL, Redis, hybrids3, HAProxy) are on a private Docker network with no host port bindings. They're unreachable from outside the stack. Only nginx is exposed.

**Auth on everything** — every service requires a bearer token. LiteLLM needs `LITELLM_MASTER_KEY`. Claudebox instances each have their own token. Hybrids3 uses per-bucket keys. The stealthy browser cluster has an optional `AUTH_TOKEN`. The admin UI supports HTTP basic auth with rate limiting (5 req/min).

**No new privileges** — all containers run with `no-new-privileges:true`.

**Public exposure** — if you want to reach the gateway from outside, use Cloudflare Tunnel instead of opening ports. Set `COMPOSE_PROFILES=cloudflared` for a quick `*.trycloudflare.com` URL (no account needed), or configure a named tunnel for a fixed custom domain. Traffic goes through Cloudflare's network before it reaches nginx — DDoS protection and TLS termination included.

→ [Cloudflare Tunnel setup](docs/services-reference.md#cloudflared-optional)

## MCP Tools

34 tools across 4 servers. Any model that supports function calling can invoke them — the model decides when and how to use them based on the prompt.

→ [Full MCP tool reference with parameters](docs/mcp-tools.md)

## Providers and Models

69 models across 10 providers. Six are free tier with no credit card required. Model groups (`fast`, `smart`, `vision`, `image-gen`, `transcription`) route automatically with per-provider fallback chains — free first, paid last.

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
COMPOSE_PROFILES=          # set to "cloudflared" to enable
CLOUDFLARED_CONFIG=        # absolute path to tunnel config.yml
CLOUDFLARED_CREDS=         # absolute path to credentials.json

# Optional — LiteLLM admin UI basic auth
LITELLM_UI_BASIC_AUTH=     # user:password format

# Optional — paid providers
# ANTHROPIC_API_KEY=sk-ant-...
# OPENAI_API_KEY=sk-...

# Infrastructure
POSTGRES_PASSWORD=...
REDIS_PASSWORD=...
WORKERS=8
```

### 3. Start

```bash
make run-bg   # detached (background)
make run      # foreground with logs
```

Profiles are auto-detected from `.env` — services that don't have credentials are skipped automatically.

Gateway is now at `http://localhost:4000`. Admin UI at `http://localhost:4000/litellm-admin/`.

## Usage

```bash
# best available free model
curl http://localhost:4000/chat/completions \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{"model": "smart", "messages": [{"role": "user", "content": "hello"}]}'

# specific provider
curl http://localhost:4000/chat/completions \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{"model": "cerebras-qwen3-235b", "messages": [{"role": "user", "content": "hello"}]}'

# image generation
curl http://localhost:4000/images/generations \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{"model": "image-gen", "prompt": "a cat riding a skateboard"}'

# transcription
curl http://localhost:4000/audio/transcriptions \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -F "model=transcription" -F "file=@audio.mp3"
```

→ [Full usage guide](docs/usage.md) — browser automation, object storage, agentic claudebox tasks, vision, streaming, Python SDK examples

## Services Reference

All endpoints, auth requirements, request/response formats, and config options.

→ [Services reference](docs/services-reference.md)

## Makefile

```bash
make run      # start stack in foreground
make run-bg   # start stack in background
make down     # stop everything
make restart  # full restart
make logs     # follow logs
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
