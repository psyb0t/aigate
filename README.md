# aigate

A self-hosted AI gateway that gives you one OpenAI-compatible endpoint for every major provider, with automatic fallbacks that burn through free tiers before touching anything paid. One `docker compose up` and you have a full AI stack: multi-provider LLM routing, object storage, stealth browser automation, Claude Code in API mode — all behind a single nginx reverse proxy.

Built on [LiteLLM](https://github.com/BerriAI/litellm). Everything is wired together and production-ready out of the box.

## What's inside

| Service                                                                           | Description                                                                                                                                                                                                                                                                               |
| --------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Nginx**                                                                         | Single entry point on port 4000 — routes all traffic to the right backend                                                                                                                                                                                                                 |
| **LiteLLM**                                                                       | OpenAI-compatible proxy — latency-based routing, caching, retries, automatic provider fallbacks                                                                                                                                                                                           |
| **PostgreSQL**                                                                    | Key management, budgets, and usage tracking                                                                                                                                                                                                                                               |
| **Redis**                                                                         | Response caching and rate limiting                                                                                                                                                                                                                                                        |
| **[claudebox](https://github.com/psyb0t/docker-claudebox)** ×2                    | Claude Code CLI running in API mode. Full tool use — reads/writes files, runs shell commands, browses the web. One instance via Claude OAuth, one via z.ai GLM.                                                                                                                           |
| **[hybrids3](https://github.com/psyb0t/docker-hybrids3)**                         | S3-compatible object storage with plain HTTP upload, bearer token auth, TTL expiry, and an MCP server. Use it to host images and files for vision model calls.                                                                                                                            |
| **[stealthy-auto-browse](https://github.com/psyb0t/docker-stealthy-auto-browse)** | Cluster of 5 stealth browser replicas behind HAProxy. Runs Camoufox (hardened Firefox) with real OS-level mouse/keyboard input. Passes Cloudflare, CreepJS, BrowserScan, Pixelscan, and every major bot detector. Exposed as an MCP server — any model on the gateway can browse the web. |

## Architecture

```
client
  └─► nginx :4000
        ├─► /claudebox/          → claudebox (Claude OAuth)
        ├─► /claudebox-zai/      → claudebox-zai (GLM via z.ai)
        ├─► /stealthy-auto-browse/ → HAProxy → [browser ×5]
        ├─► /storage/              → hybrids3
        └─► /                      → LiteLLM
                                        ├─ Groq
                                        ├─ Cerebras
                                        ├─ OpenRouter
                                        ├─ HuggingFace
                                        ├─ claudebox (OAuth)
                                        ├─ claudebox-zai (GLM)
                                        ├─ Anthropic (optional)
                                        └─ OpenAI (optional)
```

All persistent data lives under `.data/` (bind mounts). Back it up or move it as needed.

## Providers & Models

### Groq (free tier)

| Model                          | Alias                               |
| ------------------------------ | ----------------------------------- |
| llama-3.1-8b-instant           | `groq-llama-3.1-8b`                 |
| llama-3.3-70b-versatile        | `groq-llama-3.3-70b`                |
| llama-4-scout-17b-16e-instruct | `groq-llama-4-scout` _(multimodal)_ |
| moonshotai/kimi-k2-instruct    | `groq-kimi-k2`                      |
| openai/gpt-oss-20b             | `groq-gpt-oss-20b`                  |
| openai/gpt-oss-120b            | `groq-gpt-oss-120b`                 |
| qwen/qwen3-32b                 | `groq-qwen3-32b`                    |
| compound-beta                  | `groq-compound`                     |
| compound-beta-mini             | `groq-compound-mini`                |
| whisper-large-v3               | `groq-whisper-large-v3`             |
| whisper-large-v3-turbo         | `groq-whisper-large-v3-turbo`       |

### Cerebras (free tier)

1M tokens/day free, no credit card required. Among the fastest inference available (Llama 3.1 8B ~1,800 t/s, Qwen3 235B ~1,400 t/s).

| Model                          | Alias                                                 |
| ------------------------------ | ----------------------------------------------------- |
| qwen-3-235b-a22b-instruct-2507 | `cerebras-qwen3-235b`                                 |
| gpt-oss-120b                   | `cerebras-gpt-oss-120b` _(rate-limited on free tier)_ |
| zai-glm-4.7                    | `cerebras-glm-4.7` _(rate-limited on free tier)_      |
| llama3.1-8b                    | `cerebras-llama-3.1-8b`                               |

### OpenRouter (free tier)

50 req/day free (no credits), 1000 req/day with $10+ loaded.

| Model                                | Alias              |
| ------------------------------------ | ------------------ |
| nousresearch/hermes-3-llama-3.1-405b | `or-hermes-3-405b` |
| qwen/qwen3-coder                     | `or-qwen3-coder`   |
| qwen/qwen3-next-80b-a3b-instruct     | `or-qwen3-80b`     |
| nvidia/nemotron-3-super-120b-a12b    | `or-nemotron-120b` |
| minimax/minimax-m2.5                 | `or-minimax-m2.5`  |
| meta-llama/llama-3.3-70b-instruct    | `or-llama-3.3-70b` |
| openai/gpt-oss-120b                  | `or-gpt-oss-120b`  |
| openai/gpt-oss-20b                   | `or-gpt-oss-20b`   |

### HuggingFace Inference Providers (free tier)

| Model                                        | Alias                             |
| -------------------------------------------- | --------------------------------- |
| meta-llama/Llama-3.1-8B-Instruct             | `hf-llama-3.1-8b`                 |
| meta-llama/Llama-3.3-70B-Instruct            | `hf-llama-3.3-70b`                |
| meta-llama/Llama-4-Scout-17B-16E-Instruct    | `hf-llama-4-scout` _(multimodal)_ |
| Qwen/Qwen3-8B                                | `hf-qwen3-8b`                     |
| Qwen/QwQ-32B                                 | `hf-qwq-32b`                      |
| deepseek-ai/DeepSeek-R1                      | `hf-deepseek-r1`                  |
| Qwen/Qwen2.5-VL-72B-Instruct                 | `hf-qwen-vl-72b` _(multimodal)_   |
| Qwen/Qwen2.5-VL-7B-Instruct                  | `hf-qwen3-vl-8b` _(multimodal)_   |
| google/gemma-3-12b-it                        | `hf-gemma-3-12b` _(multimodal)_   |
| black-forest-labs/FLUX.1-schnell             | `hf-flux-schnell` _(image gen)_   |
| black-forest-labs/FLUX.1-dev                 | `hf-flux-dev` _(image gen)_       |
| stabilityai/stable-diffusion-3.5-large-turbo | `hf-sd-3.5-turbo` _(image gen)_   |

### Claude Code — via OAuth

Full Claude Code CLI in API mode, backed by your Claude Max subscription. Not just chat — it can use tools, read/write files, run shell commands, and browse the web from within a persistent workspace.

| Model  | Alias              |
| ------ | ------------------ |
| opus   | `claudebox-opus`   |
| sonnet | `claudebox-sonnet` |
| haiku  | `claudebox-haiku`  |

### Claude Code GLM — via z.ai

[z.ai](https://z.ai) provides an Anthropic-compatible API backed by GLM models. Routed through a second claudebox instance pointed at z.ai — same tool-use and workspace capabilities.

| Model       | Alias                   |
| ----------- | ----------------------- |
| glm-5.1     | `claudebox-glm-5.1`     |
| glm-4.7     | `claudebox-glm-4.7`     |
| glm-4.5-air | `claudebox-glm-4.5-air` |

### Anthropic (optional, API key)

| Model             | Alias                                      |
| ----------------- | ------------------------------------------ |
| claude-opus-4-6   | `anthropic-claude-opus-4` _(multimodal)_   |
| claude-sonnet-4-6 | `anthropic-claude-sonnet-4` _(multimodal)_ |
| claude-haiku-4-5  | `anthropic-claude-haiku-4` _(multimodal)_  |

### OpenAI (optional, API key)

| Model       | Alias                               |
| ----------- | ----------------------------------- |
| gpt-4o      | `openai-gpt-4o` _(multimodal)_      |
| gpt-4o-mini | `openai-gpt-4o-mini` _(multimodal)_ |
| o3          | `openai-o3`                         |
| o3-mini     | `openai-o3-mini`                    |
| dall-e-3    | `openai-dall-e-3` _(image gen)_     |
| gpt-image-1 | `openai-gpt-image-1` _(image gen)_  |
| whisper-1   | `openai-whisper`                    |
| tts-1       | `openai-tts-1`                      |
| tts-1-hd    | `openai-tts-1-hd`                   |

## Model Groups

Use these as the model name. LiteLLM tries them in priority order and falls back automatically when one fails or is rate-limited.

| Group           | Members (priority order)                                                                                                                                                                                                                                                           |
| --------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `fast`          | groq-llama-3.1-8b → cerebras-llama-3.1-8b → claudebox-haiku → claudebox-glm-4.5-air → or-gpt-oss-20b → hf-llama-3.1-8b → openai-gpt-4o-mini                                                                                                                                        |
| `smart`         | cerebras-qwen3-235b → claudebox-sonnet → or-hermes-3-405b → or-qwen3-80b → cerebras-gpt-oss-120b → or-nemotron-120b → or-minimax-m2.5 → claudebox-glm-4.7 → cerebras-glm-4.7 → openai-gpt-4o → anthropic-claude-sonnet-4 → claudebox-opus → claudebox-glm-5.1 → groq-llama-3.3-70b |
| `vision`        | openai-gpt-4o → anthropic-claude-sonnet-4 → claudebox-sonnet → claudebox-glm-4.7 → groq-llama-4-scout → hf-llama-4-scout → hf-qwen-vl-72b                                                                                                                                          |
| `image-gen`     | openai-dall-e-3 → hf-flux-schnell → hf-flux-dev                                                                                                                                                                                                                                    |
| `transcription` | groq-whisper-large-v3-turbo → groq-whisper-large-v3 → openai-whisper                                                                                                                                                                                                               |

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
# Required — your API key for the gateway itself
LITELLM_MASTER_KEY=sk-your-secret-here

# Required — internal tokens for claudebox containers
CLAUDEBOX_API_TOKEN=       # openssl rand -hex 32
CLAUDEBOX_ZAI_API_TOKEN=   # openssl rand -hex 32

# Required — Claude OAuth token (claudebox-* models, uses Max subscription)
# Run: claude setup-token
CLAUDE_CODE_OAUTH_TOKEN=sk-ant-oat01-...

# Required — z.ai (claudebox-glm-* models)
# Get it: https://z.ai
ZAI_AUTH_TOKEN=...

# Required — free tier providers
GROQ_API_KEY=gsk_...          # https://console.groq.com
HF_TOKEN=hf_...               # https://huggingface.co/settings/tokens
CEREBRAS_API_KEY=csk-...      # https://cloud.cerebras.ai
OPENROUTER_API_KEY=sk-or-v1-... # https://openrouter.ai

# Optional — object storage keys
HYBRIDS3_MASTER_KEY=    # openssl rand -hex 32
HYBRIDS3_UPLOADS_KEY=   # openssl rand -hex 32

# Optional — stealthy browser cluster
STEALTHY_AUTO_BROWSE_AUTH_TOKEN=    # leave empty to disable auth
STEALTHY_AUTO_BROWSE_NUM_REPLICAS=5

# Optional — paid providers
# ANTHROPIC_API_KEY=sk-ant-...
# OPENAI_API_KEY=sk-...
```

### 3. Start

```bash
docker compose up -d
```

LiteLLM UI and gateway at `http://localhost:4000`.

---

## Usage examples

### Basic chat

```bash
curl http://localhost:4000/chat/completions \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "fast",
    "messages": [{"role": "user", "content": "hello"}]
  }'
```

### Use a specific provider

```bash
# Groq
curl http://localhost:4000/chat/completions \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{"model": "groq-llama-3.3-70b", "messages": [{"role": "user", "content": "explain LPUs"}]}'

# Cerebras (ultra-fast)
curl http://localhost:4000/chat/completions \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{"model": "cerebras-qwen3-235b", "messages": [{"role": "user", "content": "write a haiku"}]}'
```

### Image generation

```bash
curl http://localhost:4000/images/generations \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{"model": "image-gen", "prompt": "a cat riding a skateboard, photorealistic"}'
```

### Transcription

```bash
curl http://localhost:4000/audio/transcriptions \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -F "model=transcription" \
  -F "file=@audio.mp3"
```

### Vision — image in the prompt

```bash
# Upload an image first
curl -X PUT http://localhost:4000/storage/uploads/photo.jpg \
  -H "Authorization: Bearer $HYBRIDS3_UPLOADS_KEY" \
  --data-binary @photo.jpg

# Pass the URL to a vision model
curl http://localhost:4000/chat/completions \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "vision",
    "messages": [{
      "role": "user",
      "content": [
        {"type": "text", "text": "what is in this image?"},
        {"type": "image_url", "image_url": {"url": "http://YOUR_HOST:4000/storage/uploads/photo.jpg"}}
      ]
    }]
  }'
```

### Claude Code — agentic tasks with tool use

```bash
# Analyze a file in a workspace
curl -X PUT http://localhost:4000/claudebox/files/myproject/data.csv \
  -H "Authorization: Bearer $CLAUDEBOX_API_TOKEN" \
  --data-binary @data.csv

curl http://localhost:4000/chat/completions \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "claudebox-sonnet",
    "messages": [{"role": "user", "content": "analyze data.csv and give me summary stats"}],
    "extra_headers": {"x-claude-workspace": "myproject"}
  }'

# Check workspace status
curl http://localhost:4000/claudebox/status \
  -H "Authorization: Bearer $CLAUDEBOX_API_TOKEN"
```

### Browser automation — agent browses the web

Any model on the gateway can use the browser MCP tools to navigate, scrape, click, type, and take screenshots.

```bash
curl http://localhost:4000/chat/completions \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "groq-llama-3.3-70b",
    "messages": [{
      "role": "user",
      "content": "Go to duckduckgo.com, search for '\''what is groq?'\'', take a screenshot, upload it to the uploads bucket as search-result.png, and tell me the public URL and what you found."
    }]
  }'
```

The model will autonomously navigate, type, wait for results, screenshot, upload to storage, and return the URL and a summary.

Direct browser API (without an LLM):

```bash
# Navigate to a page
curl -X POST http://localhost:4000/stealthy-auto-browse/ \
  -H "Content-Type: application/json" \
  -d '{"action": "goto", "url": "https://example.com"}'

# Take a screenshot (returns PNG)
curl http://localhost:4000/stealthy-auto-browse/screenshot/browser -o screenshot.png

# Get all visible text
curl -X POST http://localhost:4000/stealthy-auto-browse/ \
  -H "Content-Type: application/json" \
  -d '{"action": "get_text"}'

# Click at coordinates
curl -X POST http://localhost:4000/stealthy-auto-browse/ \
  -H "Content-Type: application/json" \
  -d '{"action": "system_click", "x": 640, "y": 400}'

# Type text
curl -X POST http://localhost:4000/stealthy-auto-browse/ \
  -H "Content-Type: application/json" \
  -d '{"action": "system_type", "text": "hello world"}'

# Run a multi-step script atomically
curl -X POST http://localhost:4000/stealthy-auto-browse/ \
  -H "Content-Type: application/json" \
  -d '{
    "action": "run_script",
    "script": [
      {"action": "goto", "url": "https://duckduckgo.com"},
      {"action": "system_click", "x": 950, "y": 513},
      {"action": "system_type", "text": "what is groq?"},
      {"action": "send_key", "key": "enter"},
      {"action": "wait_for_element", "selector": "[data-testid='\''result'\'']", "timeout": 10000},
      {"action": "get_text"}
    ]
  }'
```

Browser sessions are sticky per `INSTANCEID` cookie. Use a persistent HTTP client (e.g. `requests.Session()`) to keep your session on the same replica.

### Object storage

```bash
# Upload
curl -X PUT http://localhost:4000/storage/uploads/image.png \
  -H "Authorization: Bearer $HYBRIDS3_UPLOADS_KEY" \
  --data-binary @image.png

# Download (public, no auth)
curl http://localhost:4000/storage/uploads/image.png -o image.png

# List files in a bucket
curl http://localhost:4000/storage/uploads \
  -H "Authorization: Bearer $HYBRIDS3_UPLOADS_KEY"
```

S3/boto3:

```python
import boto3

s3 = boto3.client(
    "s3",
    endpoint_url="http://localhost:4000/storage",
    aws_access_key_id="uploads",
    aws_secret_access_key=HYBRIDS3_UPLOADS_KEY,
)
s3.upload_file("image.png", "uploads", "image.png")
url = "http://localhost:4000/storage/uploads/image.png"  # public, no signing needed
```

---

## Services reference

### Object storage (hybrids3)

| Endpoint        | URL                                    |
| --------------- | -------------------------------------- |
| S3 / plain HTTP | `http://localhost:4000/storage`        |
| Health          | `http://localhost:4000/storage/health` |
| MCP server      | `http://localhost:4000/storage/mcp/`   |

The `uploads` bucket is public-read. Configure TTL and size limits in `.env`:

```env
HYBRIDS3_UPLOADS_TTL=168h        # auto-delete after (default 7 days)
HYBRIDS3_UPLOADS_MAX_SIZE=100MB  # per-file size limit
```

### Browser cluster (stealthy-auto-browse)

| Endpoint             | URL                                                             |
| -------------------- | --------------------------------------------------------------- |
| Browser API          | `http://localhost:4000/stealthy-auto-browse/`                   |
| Screenshot (browser) | `http://localhost:4000/stealthy-auto-browse/screenshot/browser` |
| Screenshot (desktop) | `http://localhost:4000/stealthy-auto-browse/screenshot/desktop` |
| MCP server           | `http://localhost:4000/stealthy-auto-browse/mcp/`               |
| Queue health         | `http://localhost:4000/stealthy-auto-browse/__queue/health`     |
| Cluster status       | `http://localhost:4000/stealthy-auto-browse/__queue/status`     |

Each replica: 256 MB RAM, up to 1 GB swap. HAProxy sticky routing:

- `/mcp/*` — pinned by `Mcp-Session-Id` header
- everything else — pinned by `INSTANCEID` cookie, max 1 concurrent request per replica

### Claude Code

| Endpoint           | URL                                                                |
| ------------------ | ------------------------------------------------------------------ |
| Chat completions   | `http://localhost:4000/` (via LiteLLM)                             |
| MCP server (OAuth) | `http://localhost:4000/claudebox/mcp/`                             |
| MCP server (GLM)   | `http://localhost:4000/claudebox-zai/mcp/`                         |
| File upload        | `http://localhost:4000/claudebox/files/<workspace>/<path>`         |
| File list          | `http://localhost:4000/claudebox/files/<workspace>`                |
| Workspace status   | `http://localhost:4000/claudebox/status`                           |
| Cancel run         | `POST http://localhost:4000/claudebox/run/cancel?workspace=<name>` |

Auth: `CLAUDEBOX_API_TOKEN` for `/claudebox/`, `CLAUDEBOX_ZAI_API_TOKEN` for `/claudebox-zai/`.

Workspace isolation: pass `x-claude-workspace: <name>` in request headers. Each workspace has its own file context and conversation history.

### MCP tools

All four services are configured as MCP servers in LiteLLM — 34 tools total. Any model that supports tool use gets access to all of them.

**hybrids3:** `upload_object`, `download_object`, `delete_object`, `list_objects`, `list_buckets`, `object_info`, `presign_url`

**stealthy_auto_browse:** `goto`, `screenshot`, `get_text`, `get_html`, `get_interactive_elements`, `click`, `system_click`, `fill`, `system_type`, `send_key`, `scroll`, `wait_for_element`, `wait_for_text`, `eval_js`, `mouse_move`, `browser_action`, `run_script`

**claudebox** (OAuth/Max) and **claudebox_zai** (GLM via z.ai): `claude_run`, `read_file`, `write_file`, `list_files`, `delete_file`

`claude_run` runs any prompt through Claude Code's full agentic loop — shell access, file I/O, tools, everything. Pass a `workspace` name to scope it to a workspace directory.

---

## Testing

The test suite validates every service end-to-end against a running stack. Stack must be up before running tests.

```bash
# Run all 28 tests
make test
# or
bash test.sh

# Run specific tests
bash test.sh test_health_endpoints test_mcp_tools_loaded
```

Tests cover:
- **Health** — all service health endpoints, docker compose service status
- **LiteLLM** — endpoints, model registration, auth, chat completions, streaming
- **Nginx** — routing to all backends
- **MCP** — 34 tools loaded across 4 servers, auth rejection
- **HybridS3** — CRUD, public read, auth on writes
- **Browser** — navigation, interactive elements, screenshots, full flow
- **Claudebox** — chat via LiteLLM, direct API, file ops, z.ai reachability
- **Integration** — browser → screenshot → upload → LLM summary

---

## License

WTFPL
