# aigate

A self-hosted AI gateway that unifies every major LLM provider behind a single OpenAI-compatible API. Automatic fallback chains burn through free tiers before touching anything paid. Beyond routing, the gateway integrates a full tool ecosystem through the [Model Context Protocol (MCP)](https://modelcontextprotocol.io/) — stealth browser automation, object storage, and agentic Claude Code instances — all exposed as tools that any model on the gateway can call autonomously.

One `docker compose up` and you have a production-ready AI stack with 53 models across 9 providers, 34 MCP tools, and automatic failover.

Built on [LiteLLM](https://github.com/BerriAI/litellm).

## Table of Contents

- [Architecture](#architecture)
- [Services](#services)
- [MCP Tool Ecosystem](#mcp-tool-ecosystem)
- [Providers and Models](#providers-and-models)
- [Model Groups and Fallbacks](#model-groups-and-fallbacks)
- [Setup](#setup)
- [Usage](#usage)
  - [Chat Completions](#chat-completions)
  - [MCP Tools in Chat](#mcp-tools-in-chat)
  - [Browser Automation](#browser-automation)
  - [Object Storage](#object-storage)
  - [Claudebox — Agentic Tasks](#claudebox--agentic-tasks)
  - [Image Generation](#image-generation)
  - [Vision](#vision)
  - [Transcription](#transcription)
- [Services Reference](#services-reference)
  - [LiteLLM](#litellm)
  - [Claudebox](#claudebox)
  - [Object Storage (hybrids3)](#object-storage-hybrids3)
  - [Browser Cluster (stealthy-auto-browse)](#browser-cluster-stealthy-auto-browse)
- [Testing](#testing)
- [License](#license)

## Architecture

```
client
  └─► nginx :4000
        ├─► /claudebox/            → claudebox (Claude Code, OAuth)
        ├─► /claudebox-zai/        → claudebox-zai (Claude Code, GLM via z.ai)
        ├─► /stealthy-auto-browse/ → HAProxy → [browser ×5]
        ├─► /storage/              → hybrids3
        └─► /                      → LiteLLM
                                        ├─ Groq          (free)
                                        ├─ Cerebras      (free)
                                        ├─ OpenRouter     (free)
                                        ├─ HuggingFace    (free)
                                        ├─ claudebox      (free, Max sub)
                                        ├─ claudebox-zai  (free, z.ai)
                                        ├─ Anthropic      (optional, paid)
                                        └─ OpenAI         (optional, paid)

MCP servers (34 tools, available to all models):
  ├─ stealthy_auto_browse  (17 tools) — browser navigation, clicks, typing, screenshots
  ├─ hybrids3              (7 tools)  — file upload, download, list, delete, presign
  ├─ claudebox             (5 tools)  — agentic Claude Code via OAuth
  └─ claudebox_zai         (5 tools)  — agentic Claude Code via z.ai/GLM
```

All persistent data lives under `.data/` (bind mounts, gitignored). Everything is defined in a single `docker-compose.yml` — no external config files.

## Services

| Service | Description |
|---------|-------------|
| **Nginx** | Single entry point on port 4000. Routes traffic to the correct backend based on URL path. All service configs (nginx, HAProxy, hybrids3) are embedded inline in docker-compose.yml. |
| **LiteLLM** | OpenAI-compatible API proxy with latency-based routing, Redis response caching, automatic retries, and provider fallback chains. Manages API keys, budgets, and usage tracking via PostgreSQL. |
| **PostgreSQL** | Stores LiteLLM key management, budget tracking, and usage analytics. |
| **Redis** | Powers LiteLLM's response cache (10-minute TTL) and rate limiting. |
| **[claudebox](https://github.com/psyb0t/docker-claudebox)** ×2 | Claude Code CLI running in API mode inside Docker containers. Each instance provides a full OpenAI-compatible chat endpoint, an HTTP API for file and workspace management, and an MCP server exposing 5 tools. One instance uses your Claude Max OAuth token, the other connects to z.ai for GLM models. Both support persistent workspaces, tool use, shell access, and file I/O. |
| **[hybrids3](https://github.com/psyb0t/docker-hybrids3)** | S3-compatible object storage with plain HTTP upload/download, bearer token authentication, automatic TTL-based expiry, and an MCP server. The `uploads` bucket is public-read — uploaded files are immediately accessible via direct URL without signing. Useful for hosting images for vision model calls or storing artifacts from agentic workflows. |
| **[stealthy-auto-browse](https://github.com/psyb0t/docker-stealthy-auto-browse)** | A cluster of 5 stealth browser replicas behind HAProxy. Each replica runs Camoufox (a hardened Firefox fork) with real OS-level mouse and keyboard input via PyAutoGUI — no Chrome DevTools Protocol exposure. Passes Cloudflare, CreepJS, BrowserScan, Pixelscan, and every major bot detector. Exposed as both a REST API and an MCP server, so any model on the gateway can autonomously browse the web, fill forms, take screenshots, and extract page content. |

## MCP Tool Ecosystem

The [Model Context Protocol](https://modelcontextprotocol.io/) is what makes this gateway more than just an LLM router. Four MCP servers are registered in LiteLLM, exposing a total of 34 tools. Any model that supports tool use (function calling) can invoke these tools during a conversation — the model decides when and how to use them based on the user's request.

This means you can ask a Groq model to browse a website, take a screenshot, upload it to object storage, and return the public URL — and it will orchestrate all of that autonomously through MCP tool calls.

### stealthy_auto_browse — 17 tools

Stealth browser automation. Navigate pages, interact with elements using real mouse/keyboard input, extract content, and take screenshots. All interactions are undetectable by bot detection systems.

| Tool | Description |
|------|-------------|
| `goto` | Navigate to a URL |
| `get_text` | Extract all visible text from the current page (up to 10,000 chars) |
| `get_html` | Get the full HTML source of the current page |
| `get_interactive_elements` | Find all clickable/interactive elements with their viewport coordinates |
| `screenshot` | Capture the browser viewport or full desktop as PNG |
| `system_click` | Click at specific viewport coordinates using OS-level mouse input |
| `system_type` | Type text using OS-level keyboard input |
| `send_key` | Send a keyboard key (enter, tab, escape, etc.) |
| `click` | Click a CSS selector |
| `fill` | Fill a form field by CSS selector |
| `scroll` | Scroll the page |
| `mouse_move` | Move the mouse to specific coordinates |
| `wait_for_element` | Wait for a CSS selector to appear on the page |
| `wait_for_text` | Wait for specific text to appear on the page |
| `eval_js` | Execute JavaScript in the browser context |
| `browser_action` | Perform browser-level actions (back, forward, refresh) |
| `run_script` | Execute a multi-step automation script atomically |

### hybrids3 — 7 tools

Object storage operations. Upload, download, list, and manage files in storage buckets. The `uploads` bucket is public-read, so uploaded files are immediately accessible via direct URL.

| Tool | Description |
|------|-------------|
| `upload_object` | Upload a file to a bucket |
| `download_object` | Download a file from a bucket |
| `delete_object` | Delete a file from a bucket |
| `list_objects` | List all files in a bucket |
| `list_buckets` | List all available buckets |
| `object_info` | Get metadata (size, content type, expiry) for a file |
| `presign_url` | Generate a pre-signed URL for time-limited access |

### claudebox — 5 tools (OAuth/Max)

Agentic Claude Code backed by your Claude Max subscription. Each tool call runs through Claude Code's full agentic loop with shell access, file I/O, and tool use within an isolated workspace.

| Tool | Description |
|------|-------------|
| `claude_run` | Run a prompt through Claude Code's full agentic loop |
| `read_file` | Read a file from the workspace |
| `write_file` | Write a file to the workspace |
| `list_files` | List files in the workspace |
| `delete_file` | Delete a file from the workspace |

### claudebox_zai — 5 tools (GLM via z.ai)

Same 5 tools as above, but backed by GLM models through [z.ai](https://z.ai)'s Anthropic-compatible API. Same workspace capabilities, different underlying model.

## Providers and Models

### Groq (free tier)

| Model | Alias |
|-------|-------|
| llama-3.1-8b-instant | `groq-llama-3.1-8b` |
| llama-3.3-70b-versatile | `groq-llama-3.3-70b` |
| llama-4-scout-17b-16e-instruct | `groq-llama-4-scout` _(multimodal)_ |
| moonshotai/kimi-k2-instruct | `groq-kimi-k2` |
| openai/gpt-oss-20b | `groq-gpt-oss-20b` |
| openai/gpt-oss-120b | `groq-gpt-oss-120b` |
| qwen/qwen3-32b | `groq-qwen3-32b` |
| compound-beta | `groq-compound` |
| compound-beta-mini | `groq-compound-mini` |
| whisper-large-v3 | `groq-whisper-large-v3` |
| whisper-large-v3-turbo | `groq-whisper-large-v3-turbo` |

### Cerebras (free tier)

1M tokens/day free, no credit card required. Among the fastest inference available (Llama 3.1 8B ~1,800 t/s, Qwen3 235B ~1,400 t/s).

| Model | Alias |
|-------|-------|
| qwen-3-235b-a22b-instruct-2507 | `cerebras-qwen3-235b` |
| gpt-oss-120b | `cerebras-gpt-oss-120b` _(rate-limited on free tier)_ |
| zai-glm-4.7 | `cerebras-glm-4.7` _(rate-limited on free tier)_ |
| llama3.1-8b | `cerebras-llama-3.1-8b` |

### OpenRouter (free tier)

50 req/day free (no credits), 1000 req/day with $10+ loaded.

| Model | Alias |
|-------|-------|
| nousresearch/hermes-3-llama-3.1-405b | `or-hermes-3-405b` |
| qwen/qwen3-coder | `or-qwen3-coder` |
| qwen/qwen3-next-80b-a3b-instruct | `or-qwen3-80b` |
| nvidia/nemotron-3-super-120b-a12b | `or-nemotron-120b` |
| minimax/minimax-m2.5 | `or-minimax-m2.5` |
| meta-llama/llama-3.3-70b-instruct | `or-llama-3.3-70b` |
| openai/gpt-oss-120b | `or-gpt-oss-120b` |
| openai/gpt-oss-20b | `or-gpt-oss-20b` |

### HuggingFace Inference Providers (free tier)

| Model | Alias |
|-------|-------|
| meta-llama/Llama-3.1-8B-Instruct | `hf-llama-3.1-8b` |
| meta-llama/Llama-3.3-70B-Instruct | `hf-llama-3.3-70b` |
| meta-llama/Llama-4-Scout-17B-16E-Instruct | `hf-llama-4-scout` _(multimodal)_ |
| Qwen/Qwen3-8B | `hf-qwen3-8b` |
| Qwen/QwQ-32B | `hf-qwq-32b` |
| deepseek-ai/DeepSeek-R1 | `hf-deepseek-r1` |
| Qwen/Qwen2.5-VL-72B-Instruct | `hf-qwen-vl-72b` _(multimodal)_ |
| Qwen/Qwen2.5-VL-7B-Instruct | `hf-qwen3-vl-8b` _(multimodal)_ |
| google/gemma-3-12b-it | `hf-gemma-3-12b` _(multimodal)_ |
| black-forest-labs/FLUX.1-schnell | `hf-flux-schnell` _(image gen)_ |
| black-forest-labs/FLUX.1-dev | `hf-flux-dev` _(image gen)_ |
| stabilityai/stable-diffusion-3.5-large-turbo | `hf-sd-3.5-turbo` _(image gen)_ |

### Claudebox — via OAuth (free with Max subscription)

Full Claude Code CLI in API mode, backed by your Claude Max subscription. These are not standard API calls — each request runs through Claude Code's full agentic loop with tool use, file I/O, shell access, and web browsing within a persistent workspace.

| Model | Alias |
|-------|-------|
| opus | `claudebox-opus` |
| sonnet | `claudebox-sonnet` |
| haiku | `claudebox-haiku` |

### Claudebox GLM — via z.ai (free)

[z.ai](https://z.ai) provides an Anthropic-compatible API backed by GLM models. Routed through a second claudebox instance pointed at z.ai — same agentic capabilities and workspace features as the OAuth instance above.

| Model | Alias |
|-------|-------|
| glm-5.1 | `claudebox-glm-5.1` |
| glm-4.7 | `claudebox-glm-4.7` |
| glm-4.5-air | `claudebox-glm-4.5-air` |

### Anthropic (optional, API key required)

| Model | Alias |
|-------|-------|
| claude-opus-4-6 | `anthropic-claude-opus-4` _(multimodal)_ |
| claude-sonnet-4-6 | `anthropic-claude-sonnet-4` _(multimodal)_ |
| claude-haiku-4-5 | `anthropic-claude-haiku-4` _(multimodal)_ |

### OpenAI (optional, API key required)

| Model | Alias |
|-------|-------|
| gpt-4o | `openai-gpt-4o` _(multimodal)_ |
| gpt-4o-mini | `openai-gpt-4o-mini` _(multimodal)_ |
| o3 | `openai-o3` |
| o3-mini | `openai-o3-mini` |
| dall-e-3 | `openai-dall-e-3` _(image gen)_ |
| gpt-image-1 | `openai-gpt-image-1` _(image gen)_ |
| whisper-1 | `openai-whisper` |
| tts-1 | `openai-tts-1` |
| tts-1-hd | `openai-tts-1-hd` |

## Model Groups and Fallbacks

Model groups let you use a single alias and let the gateway figure out which provider to hit. LiteLLM tries each model in priority order and automatically falls back to the next one when a provider fails, is rate-limited, or returns an error. Free providers are always tried first.

| Group | Fallback chain (priority order) |
|-------|--------------------------------|
| `fast` | groq-llama-3.1-8b → cerebras-llama-3.1-8b → claudebox-haiku → claudebox-glm-4.5-air → or-gpt-oss-20b → hf-llama-3.1-8b → openai-gpt-4o-mini |
| `smart` | cerebras-qwen3-235b → claudebox-sonnet → or-hermes-3-405b → or-qwen3-80b → cerebras-gpt-oss-120b → or-nemotron-120b → or-minimax-m2.5 → claudebox-glm-4.7 → cerebras-glm-4.7 → openai-gpt-4o → anthropic-claude-sonnet-4 → claudebox-opus → claudebox-glm-5.1 → groq-llama-3.3-70b |
| `vision` | openai-gpt-4o → anthropic-claude-sonnet-4 → claudebox-sonnet → claudebox-glm-4.7 → groq-llama-4-scout → hf-llama-4-scout → hf-qwen-vl-72b |
| `image-gen` | openai-dall-e-3 → hf-flux-schnell → hf-flux-dev |
| `transcription` | groq-whisper-large-v3-turbo → groq-whisper-large-v3 → openai-whisper |

Every individual model also has its own fallback chain configured. For example, if `groq-llama-3.3-70b` fails, it automatically tries `cerebras-qwen3-235b`, then `or-llama-3.3-70b`, then `hf-llama-3.3-70b`, then `claudebox-sonnet`, and so on. See `config.yaml` for the full fallback configuration.

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

Edit `.env` with your API keys and tokens:

```env
# Required — your master API key for the gateway itself
LITELLM_MASTER_KEY=sk-your-secret-here

# Required — internal auth tokens for claudebox containers
CLAUDEBOX_API_TOKEN=       # generate with: openssl rand -hex 32
CLAUDEBOX_ZAI_API_TOKEN=   # generate with: openssl rand -hex 32

# Required — Claude OAuth token (powers claudebox-* models, uses your Max subscription)
# Generate with: claude setup-token
CLAUDE_CODE_OAUTH_TOKEN=sk-ant-oat01-...

# Required — z.ai auth token (powers claudebox-glm-* models)
# Get one at: https://z.ai
ZAI_AUTH_TOKEN=...

# Required — free tier provider API keys
GROQ_API_KEY=gsk_...          # https://console.groq.com
HF_TOKEN=hf_...               # https://huggingface.co/settings/tokens
CEREBRAS_API_KEY=csk-...      # https://cloud.cerebras.ai
OPENROUTER_API_KEY=sk-or-v1-... # https://openrouter.ai

# Optional — object storage auth keys
HYBRIDS3_MASTER_KEY=    # generate with: openssl rand -hex 32
HYBRIDS3_UPLOADS_KEY=   # generate with: openssl rand -hex 32

# Optional — stealthy browser cluster auth
STEALTHY_AUTO_BROWSE_AUTH_TOKEN=    # leave empty to disable auth
STEALTHY_AUTO_BROWSE_NUM_REPLICAS=5

# Optional — paid providers (only needed if you want direct API access)
# ANTHROPIC_API_KEY=sk-ant-...
# OPENAI_API_KEY=sk-...

# Infrastructure — defaults work out of the box, change for production
POSTGRES_PASSWORD=...         # database password
REDIS_PASSWORD=...            # cache password
WORKERS=8                     # LiteLLM worker count (tune to CPU cores)
```

### 3. Start

```bash
docker compose up -d
```

The gateway is now available at `http://localhost:4000`. LiteLLM's admin UI is also accessible at the same address.

## Usage

### Chat Completions

Standard OpenAI-compatible chat completions. Works with any OpenAI SDK, library, or tool that supports custom base URLs.

```bash
# Use a model group — gateway picks the best available provider
curl http://localhost:4000/chat/completions \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "fast",
    "messages": [{"role": "user", "content": "hello"}]
  }'

# Target a specific provider
curl http://localhost:4000/chat/completions \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "groq-llama-3.3-70b",
    "messages": [{"role": "user", "content": "explain what an LPU is"}]
  }'

# Streaming
curl http://localhost:4000/chat/completions \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "cerebras-qwen3-235b",
    "messages": [{"role": "user", "content": "write a haiku about distributed systems"}],
    "stream": true
  }'
```

### MCP Tools in Chat

The gateway exposes an MCP endpoint at `/mcp/` that aggregates all 34 tools from all four MCP servers. You can list available tools and pass them to models that support function calling.

```bash
# List all available MCP tools
curl -X POST http://localhost:4000/mcp/ \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}'
```

When a model has access to MCP tools, it can autonomously decide to browse websites, upload files to storage, run code through Claude Code, or chain multiple tools together — all within a single conversation turn.

### Browser Automation

The browser cluster can be used in two ways: directly via the REST API, or indirectly by letting an LLM invoke browser tools through MCP.

#### Direct REST API

```bash
# Navigate to a page
curl -X POST http://localhost:4000/stealthy-auto-browse/ \
  -H "Content-Type: application/json" \
  -d '{"action": "goto", "url": "https://example.com"}'

# Get all visible text from the page
curl -X POST http://localhost:4000/stealthy-auto-browse/ \
  -H "Content-Type: application/json" \
  -d '{"action": "get_text"}'

# Find all interactive elements with their coordinates
curl -X POST http://localhost:4000/stealthy-auto-browse/ \
  -H "Content-Type: application/json" \
  -d '{"action": "get_interactive_elements", "visible_only": true}'

# Click at specific coordinates (OS-level, undetectable)
curl -X POST http://localhost:4000/stealthy-auto-browse/ \
  -H "Content-Type: application/json" \
  -d '{"action": "system_click", "x": 640, "y": 400}'

# Type text (OS-level keyboard input)
curl -X POST http://localhost:4000/stealthy-auto-browse/ \
  -H "Content-Type: application/json" \
  -d '{"action": "system_type", "text": "hello world"}'

# Take a screenshot (returns raw PNG)
curl http://localhost:4000/stealthy-auto-browse/screenshot/browser -o screenshot.png

# Run a multi-step automation script atomically
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

Browser sessions are sticky via the `INSTANCEID` cookie. Use a persistent HTTP client (e.g. `requests.Session()` in Python) to keep your session on the same browser replica across multiple requests.

#### Python Example — Search, Screenshot, and Summarize

```python
import requests, base64

session = requests.Session()  # sticky sessions via cookie
BASE = "http://localhost:4000"

def browser(action, **kwargs):
    r = session.post(f"{BASE}/stealthy-auto-browse/", json={"action": action, **kwargs})
    r.raise_for_status()
    return r.json()["data"]

# Navigate and search
browser("goto", url="https://duckduckgo.com")
browser("system_click", x=950, y=513)
browser("system_type", text="what is groq?")
browser("send_key", key="enter")
browser("wait_for_element", selector="[data-testid='result']", timeout=10000)

# Get page text
text = browser("get_text")["text"]

# Screenshot and upload to storage
screenshot = session.get(f"{BASE}/stealthy-auto-browse/screenshot/browser").content
requests.put(
    f"{BASE}/storage/uploads/search.png",
    headers={"Authorization": f"Bearer {UPLOADS_KEY}", "Content-Type": "image/png"},
    data=screenshot,
)

# Ask an LLM to summarize
r = requests.post(f"{BASE}/chat/completions",
    headers={"Authorization": f"Bearer {MASTER_KEY}", "Content-Type": "application/json"},
    json={"model": "groq-llama-3.3-70b", "messages": [
        {"role": "user", "content": f"Summarize these search results:\n\n{text[:8000]}"}
    ]})
print(r.json()["choices"][0]["message"]["content"])
print(f"Screenshot: {BASE}/storage/uploads/search.png")
```

### Object Storage

[hybrids3](https://github.com/psyb0t/docker-hybrids3) provides S3-compatible object storage with a simple HTTP interface. The `uploads` bucket is configured as public-read — anyone can download files by direct URL, but uploading and deleting requires authentication.

```bash
# Upload a file
curl -X PUT http://localhost:4000/storage/uploads/image.png \
  -H "Authorization: Bearer $HYBRIDS3_UPLOADS_KEY" \
  -H "Content-Type: image/png" \
  --data-binary @image.png

# Download (public, no auth required)
curl http://localhost:4000/storage/uploads/image.png -o image.png

# List files in the uploads bucket
curl http://localhost:4000/storage/uploads \
  -H "Authorization: Bearer $HYBRIDS3_UPLOADS_KEY"

# Delete a file
curl -X DELETE http://localhost:4000/storage/uploads/image.png \
  -H "Authorization: Bearer $HYBRIDS3_UPLOADS_KEY"
```

S3-compatible access via boto3:

```python
import boto3

s3 = boto3.client(
    "s3",
    endpoint_url="http://localhost:4000/storage",
    aws_access_key_id="uploads",
    aws_secret_access_key=HYBRIDS3_UPLOADS_KEY,
)
s3.upload_file("image.png", "uploads", "image.png")
# Public URL (no signing needed): http://localhost:4000/storage/uploads/image.png
```

Configure TTL and size limits in `.env`:

```env
HYBRIDS3_UPLOADS_TTL=168h        # auto-delete after (default 7 days)
HYBRIDS3_UPLOADS_MAX_SIZE=100MB  # per-file size limit
```

### Claudebox — Agentic Tasks

[Claudebox](https://github.com/psyb0t/docker-claudebox) wraps Claude Code in a Docker container and exposes it as an API. Each request runs through Claude Code's full agentic loop — it can read/write files, run shell commands, install packages, browse the web, and use tools, all within an isolated workspace.

Two instances are running: one backed by your Claude Max OAuth token, and one connected to z.ai for GLM models. Both provide identical APIs and workspace capabilities.

```bash
# Upload a file to a workspace
curl -X PUT http://localhost:4000/claudebox/files/myproject/data.csv \
  -H "Authorization: Bearer $CLAUDEBOX_API_TOKEN" \
  --data-binary @data.csv

# Ask Claude to analyze it (via LiteLLM)
curl http://localhost:4000/chat/completions \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "claudebox-sonnet",
    "messages": [{"role": "user", "content": "analyze data.csv and give me summary statistics"}],
    "extra_headers": {"x-claude-workspace": "myproject"}
  }'

# Check workspace status (which workspaces are busy)
curl http://localhost:4000/claudebox/status \
  -H "Authorization: Bearer $CLAUDEBOX_API_TOKEN"

# List files in a workspace
curl http://localhost:4000/claudebox/files/myproject \
  -H "Authorization: Bearer $CLAUDEBOX_API_TOKEN"

# Download a file from a workspace
curl http://localhost:4000/claudebox/files/myproject/results.json \
  -H "Authorization: Bearer $CLAUDEBOX_API_TOKEN"

# Cancel a running task
curl -X POST http://localhost:4000/claudebox/run/cancel?workspace=myproject \
  -H "Authorization: Bearer $CLAUDEBOX_API_TOKEN"
```

### Image Generation

```bash
curl http://localhost:4000/images/generations \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{"model": "image-gen", "prompt": "a cat riding a skateboard, photorealistic"}'
```

### Vision

Upload an image to storage, then pass its URL to a vision-capable model:

```bash
# Upload the image
curl -X PUT http://localhost:4000/storage/uploads/photo.jpg \
  -H "Authorization: Bearer $HYBRIDS3_UPLOADS_KEY" \
  --data-binary @photo.jpg

# Ask a vision model about it
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

### Transcription

```bash
curl http://localhost:4000/audio/transcriptions \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -F "model=transcription" \
  -F "file=@audio.mp3"
```

## Services Reference

### LiteLLM

| Endpoint | URL |
|----------|-----|
| Chat completions | `POST http://localhost:4000/chat/completions` |
| Models list | `GET http://localhost:4000/models` |
| Health check | `GET http://localhost:4000/health/liveliness` |
| MCP server (all tools) | `POST http://localhost:4000/mcp/` |
| Admin UI | `http://localhost:4000/` |

Authentication: all endpoints require `Authorization: Bearer $LITELLM_MASTER_KEY`.

### Claudebox

| Endpoint | URL |
|----------|-----|
| Chat completions (via LiteLLM) | `POST http://localhost:4000/chat/completions` with model `claudebox-*` |
| Direct API | `http://localhost:4000/claudebox/` |
| MCP server (OAuth) | `http://localhost:4000/claudebox/mcp/` |
| MCP server (GLM) | `http://localhost:4000/claudebox-zai/mcp/` |
| File upload | `PUT http://localhost:4000/claudebox/files/<workspace>/<path>` |
| File download | `GET http://localhost:4000/claudebox/files/<workspace>/<path>` |
| File list | `GET http://localhost:4000/claudebox/files/<workspace>` |
| Workspace status | `GET http://localhost:4000/claudebox/status` |
| Cancel run | `POST http://localhost:4000/claudebox/run/cancel?workspace=<name>` |
| Health | `GET http://localhost:4000/claudebox/health` |

Authentication: `/claudebox/` endpoints use `Authorization: Bearer $CLAUDEBOX_API_TOKEN`. `/claudebox-zai/` endpoints use `Authorization: Bearer $CLAUDEBOX_ZAI_API_TOKEN`. Health endpoints require no auth.

Workspace isolation: pass `x-claude-workspace: <name>` in request headers. Each workspace gets its own directory, file context, and conversation history.

### Object Storage (hybrids3)

| Endpoint | URL |
|----------|-----|
| Upload / download | `http://localhost:4000/storage/uploads/<key>` |
| List bucket | `GET http://localhost:4000/storage/uploads` |
| Health | `GET http://localhost:4000/storage/health` |
| MCP server | `http://localhost:4000/storage/mcp/` |
| S3-compatible | `http://localhost:4000/storage` (use with boto3/aws-cli) |

Authentication: writes and deletes require `Authorization: Bearer $HYBRIDS3_UPLOADS_KEY`. Downloads from the `uploads` bucket are public (no auth).

### Browser Cluster (stealthy-auto-browse)

| Endpoint | URL |
|----------|-----|
| Browser API | `POST http://localhost:4000/stealthy-auto-browse/` |
| Screenshot (browser) | `GET http://localhost:4000/stealthy-auto-browse/screenshot/browser` |
| Screenshot (desktop) | `GET http://localhost:4000/stealthy-auto-browse/screenshot/desktop` |
| MCP server | `http://localhost:4000/stealthy-auto-browse/mcp/` |
| Queue health | `GET http://localhost:4000/stealthy-auto-browse/__queue/health` |
| Cluster status | `GET http://localhost:4000/stealthy-auto-browse/__queue/status` |

Configuration: 5 browser replicas by default (configurable via `STEALTHY_AUTO_BROWSE_NUM_REPLICAS`). Each replica has 256 MB RAM and up to 1 GB swap. HAProxy handles sticky routing:

- MCP requests are pinned by `Mcp-Session-Id` header
- All other requests are pinned by `INSTANCEID` cookie, with max 1 concurrent request per replica

## Testing

The test suite validates every service end-to-end against the running stack. The stack must be up before running tests.

```bash
# Run all 28 tests
make test
# or
bash test.sh

# Run specific tests
bash test.sh test_health_endpoints test_mcp_tools_loaded

# List all available tests
bash test.sh --help
```

Tests cover:

- **Health** — all service health endpoints, docker compose service status, browser replica count
- **LiteLLM** — API endpoints, model registration, authentication (valid/invalid/missing keys), chat completions, SSE streaming
- **Nginx** — routing to all 5 backends (LiteLLM, claudebox, claudebox-zai, stealthy-auto-browse, hybrids3)
- **MCP** — all 34 tools loaded across 4 servers, per-server tool counts, specific tool presence, authentication
- **HybridS3** — full CRUD lifecycle (upload, download, list, delete, verify deletion), public read without auth, write rejection without auth
- **Browser** — page navigation, interactive element detection, screenshot capture, full automation flow (navigate, find elements, click, type, screenshot)
- **Claudebox** — chat completion via LiteLLM, direct API access via nginx, file operations (upload, download, list, delete), z.ai instance reachability
- **Integration** — end-to-end workflow: browser navigation → screenshot → upload to storage → verify public URL → LLM summarization

## License

WTFPL
