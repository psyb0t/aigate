# aigate

A self-hosted AI gateway that unifies every major LLM provider behind a single OpenAI-compatible API. Automatic fallback chains burn through free tiers before touching anything paid. Beyond routing, the gateway integrates a full tool ecosystem through the [Model Context Protocol (MCP)](https://modelcontextprotocol.io/) — stealth browser automation, object storage, and agentic Claude Code instances — all exposed as tools that any model on the gateway can call autonomously.

One `docker compose up` and you have a production-ready AI stack with 69 models across 10 providers, 34 MCP tools, and automatic failover.

Built on [LiteLLM](https://github.com/BerriAI/litellm).

## Architecture

```
client
  ▼
cloudflared (optional)
  ▼
nginx :4000
  ├─► /claudebox/            → claudebox (Claude Code, OAuth/API key)
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

All persistent data lives under `.data/` (bind mounts). The directory structure is tracked in git via `.gitkeep` files so the right directories exist on a fresh clone — contents are gitignored. Everything is defined in a single `docker-compose.yml` — no external config files.

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

| Service                                                                           | Description                                                                                                                                                                                                        |
| --------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| **Nginx**                                                                         | Single entry point on port 4000. Routes traffic to the correct backend based on URL path. All service configs are embedded inline in `docker-compose.yml`.                                                         |
| **LiteLLM**                                                                       | OpenAI-compatible API proxy with latency-based routing, Redis response caching, automatic retries, and provider fallback chains. Manages API keys, budgets, and usage tracking via PostgreSQL.                     |
| **PostgreSQL**                                                                    | Stores LiteLLM key management, budget tracking, and usage analytics.                                                                                                                                               |
| **Redis**                                                                         | Powers LiteLLM's response cache (10-minute TTL) and rate limiting.                                                                                                                                                 |
| **[claudebox](https://github.com/psyb0t/docker-claudebox)** ×2                    | Claude Code CLI in API mode. Full agentic loop with shell access, file I/O, tool use, and persistent workspaces. One instance uses OAuth/API key, the other connects to z.ai for GLM models.                       |
| **[hybrids3](https://github.com/psyb0t/docker-hybrids3)**                         | S3-compatible object storage with bearer token auth, TTL-based expiry, and an MCP server. The `uploads` bucket is public-read.                                                                                     |
| **[stealthy-auto-browse](https://github.com/psyb0t/docker-stealthy-auto-browse)** | 5 stealth browser replicas behind HAProxy. Runs Camoufox (hardened Firefox fork) with real OS-level mouse/keyboard input. Passes all major bot detectors. Exposed as REST API and MCP server.                      |
| **cloudflared** _(optional)_                                                      | Exposes the gateway via [Cloudflare Tunnel](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/). Disabled by default — enable with `COMPOSE_PROFILES=cloudflared`. Supports quick tunnels (no account) and named tunnels (fixed domain). |

## MCP Tools

34 tools across 4 MCP servers, available to any model that supports function calling. A Groq model can browse a website, screenshot it, upload to storage, and return the public URL — all autonomously through MCP.

→ [Full MCP tool reference](docs/mcp-tools.md)

## Providers and Models

69 models across 10 providers. Groq, Cerebras, OpenRouter, HuggingFace, Mistral, and Cohere are all free tier. Model groups (`fast`, `smart`, `vision`, `image-gen`, `transcription`) route automatically with per-provider fallback chains.

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

Edit `.env` with your API keys:

```env
# Required — gateway master key
LITELLM_MASTER_KEY=sk-your-secret-here

# Required — claudebox auth tokens
CLAUDEBOX_API_TOKEN=       # openssl rand -hex 32
CLAUDEBOX_ZAI_API_TOKEN=   # openssl rand -hex 32

# Required — claudebox auth (OAuth token OR API key)
CLAUDE_CODE_OAUTH_TOKEN=sk-ant-oat01-...
# CLAUDEBOX_ANTHROPIC_API_KEY=sk-ant-...

# Required — z.ai auth (powers claudebox-glm-* models)
ZAI_AUTH_TOKEN=...

# Required — free tier providers
GROQ_API_KEY=gsk_...            # https://console.groq.com
HF_TOKEN=hf_...                 # https://huggingface.co/settings/tokens
CEREBRAS_API_KEY=csk-...        # https://cloud.cerebras.ai
OPENROUTER_API_KEY=sk-or-v1-... # https://openrouter.ai
MISTRAL_API_KEY=...             # https://console.mistral.ai
COHERE_API_KEY=...              # https://dashboard.cohere.com

# Optional — object storage
HYBRIDS3_MASTER_KEY=    # openssl rand -hex 32
HYBRIDS3_UPLOADS_KEY=   # openssl rand -hex 32

# Optional — browser cluster
STEALTHY_AUTO_BROWSE_AUTH_TOKEN=
STEALTHY_AUTO_BROWSE_NUM_REPLICAS=5

# Optional — Cloudflare Tunnel
COMPOSE_PROFILES=        # set to "cloudflared" to enable
CLOUDFLARED_CONFIG=      # absolute path to config.yml
CLOUDFLARED_CREDS=       # absolute path to credentials.json

# Optional — admin UI basic auth (user:password)
LITELLM_UI_BASIC_AUTH=

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
docker compose up -d
```

Gateway is now at `http://localhost:4000`. Admin UI at `http://localhost:4000/litellm-admin/`.

## Usage

Quick examples:

```bash
# Chat with the best available free model
curl http://localhost:4000/chat/completions \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{"model": "smart", "messages": [{"role": "user", "content": "hello"}]}'

# Image generation
curl http://localhost:4000/images/generations \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{"model": "image-gen", "prompt": "a cat riding a skateboard, photorealistic"}'

# Audio transcription
curl http://localhost:4000/audio/transcriptions \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -F "model=transcription" \
  -F "file=@audio.mp3"
```

→ [Full usage guide](docs/usage.md) — browser automation, object storage, claudebox agentic tasks, vision, streaming

## Services Reference

All endpoints, auth requirements, and configuration options for every service.

→ [Services reference](docs/services-reference.md)

## Testing

```bash
make test
# or: bash test.sh
```

Covers health, routing, auth, MCP, storage CRUD, browser automation, claudebox, and security. Designed for zero/minimal token usage.

→ [Testing guide](docs/testing.md)

## License

WTFPL
