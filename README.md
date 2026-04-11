# aigate

A self-healing multi-provider AI gateway with free-first routing. One OpenAI-compatible endpoint, every provider, automatic fallbacks that prefer free tiers before spending a cent. Built on Docker Compose.

## What's in it

One `docker compose up` gives you:

- **Nginx** on port 4000 — single entry point, routes to all backends
- **LiteLLM proxy** — OpenAI-compatible API for all providers, latency-based routing, caching, retries, fallbacks
- **PostgreSQL** — key management, budgets, usage tracking
- **Redis** — response caching + rate limiting
- **[docker-claude-code](https://github.com/psyb0t/docker-claude-code)** (×2) — Claude Code running in API mode, one per provider
- **[HybridS3](https://github.com/psyb0t/docker-hybrids3)** — S3-compatible object storage at `/storage/` for hosting files/images (with MCP server)
- **[docker-stealthy-auto-browse](https://github.com/psyb0t/docker-stealthy-auto-browse)** — cluster of 5 stealth browser replicas behind HAProxy at `/stealthy-auto-browse/` (with MCP server)

## Routing

All traffic goes through nginx on port 4000:

| Path prefix               | Backend                                  |
| ------------------------- | ---------------------------------------- |
| `/claude-code/*`          | claude-code container (Claude OAuth)     |
| `/claude-code-zai/*`      | claude-code-zai container (GLM via z.ai) |
| `/stealthy-auto-browse/*` | HAProxy → 5 browser replicas             |
| `/storage/*`              | HybridS3 object storage                  |
| `/*`                      | LiteLLM (all model providers)            |

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

50 req/day free (no credits loaded), 1000 req/day with $10+. Only models confirmed working with API key auth.

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

Uses [docker-claude-code](https://github.com/psyb0t/docker-claude-code) in API mode with a Claude OAuth token. Not just a chat API — runs the full Claude Code CLI, so it can use tools, read/write files in the workspace, run shell commands, etc.

| Model  | Alias                |
| ------ | -------------------- |
| opus   | `claude-code-opus`   |
| sonnet | `claude-code-sonnet` |
| haiku  | `claude-code-haiku`  |

### Claude Code GLM — via z.ai

[z.ai](https://z.ai) provides an Anthropic-compatible API serving GLM models. Routed through a second docker-claude-code instance pointed at z.ai — same workspace/tool-use capabilities as above.

| Model       | Alias                     |
| ----------- | ------------------------- |
| glm-5.1     | `claude-code-glm-5.1`     |
| glm-4.7     | `claude-code-glm-4.7`     |
| glm-4.5-air | `claude-code-glm-4.5-air` |

### Anthropic (API key, optional)

| Model             | Alias                                      |
| ----------------- | ------------------------------------------ |
| claude-opus-4-6   | `anthropic-claude-opus-4` _(multimodal)_   |
| claude-sonnet-4-6 | `anthropic-claude-sonnet-4` _(multimodal)_ |
| claude-haiku-4-5  | `anthropic-claude-haiku-4` _(multimodal)_  |

### OpenAI (API key, optional)

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

Use these as the model name — LiteLLM picks the best available and falls back automatically:

| Group           | Members (priority order)                                                                                                                                                                                                                                                                   |
| --------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `fast`          | groq-llama-3.1-8b → cerebras-llama-3.1-8b → claude-code-haiku → claude-code-glm-4.5-air → or-gpt-oss-20b → hf-llama-3.1-8b → openai-gpt-4o-mini                                                                                                                                            |
| `smart`         | cerebras-qwen3-235b → claude-code-sonnet → or-hermes-3-405b → or-qwen3-80b → cerebras-gpt-oss-120b → or-nemotron-120b → or-minimax-m2.5 → claude-code-glm-4.7 → cerebras-glm-4.7 → openai-gpt-4o → anthropic-claude-sonnet-4 → claude-code-opus → claude-code-glm-5.1 → groq-llama-3.3-70b |
| `vision`        | openai-gpt-4o → anthropic-claude-sonnet-4 → claude-code-sonnet → claude-code-glm-4.7 → groq-llama-4-scout → hf-llama-4-scout → hf-qwen-vl-72b                                                                                                                                              |
| `image-gen`     | openai-dall-e-3 → hf-flux-schnell → hf-flux-dev                                                                                                                                                                                                                                            |
| `transcription` | groq-whisper-large-v3-turbo → groq-whisper-large-v3 → openai-whisper                                                                                                                                                                                                                       |

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

Edit `.env` and fill in your keys:

```env
# Required — LiteLLM master key (your API key for this gateway)
LITELLM_MASTER_KEY=sk-your-secret-here

# Required — internal auth tokens for claude-code containers
CLAUDE_CODE_API_TOKEN=generate-with-openssl-rand-hex-32
CLAUDE_CODE_ZAI_API_TOKEN=generate-with-openssl-rand-hex-32

# Required — Claude Code OAuth token (for claude-code-* models)
# Get it: claude setup-token
CLAUDE_CODE_OAUTH_TOKEN=sk-ant-oat01-...

# Required — z.ai auth token (for claude-code-glm-* models)
# Get it: https://z.ai
ZAI_AUTH_TOKEN=...

# Required — Groq (free tier): https://console.groq.com
GROQ_API_KEY=gsk_...

# Required — HuggingFace (free tier): https://huggingface.co/settings/tokens
HF_TOKEN=hf_...

# Required — Cerebras (free tier, 1M tokens/day): https://cloud.cerebras.ai
CEREBRAS_API_KEY=csk-...

# Required — OpenRouter (free tier): https://openrouter.ai
OPENROUTER_API_KEY=sk-or-v1-...

# Optional — direct Anthropic API
# ANTHROPIC_API_KEY=sk-ant-...

# Optional — OpenAI
# OPENAI_API_KEY=sk-...

# Optional — HybridS3 object storage keys
HYBRIDS3_MASTER_KEY=generate-with-openssl-rand-hex-32
HYBRIDS3_UPLOADS_KEY=generate-with-openssl-rand-hex-32

# Optional — Stealthy Auto Browse cluster
STEALTHY_AUTO_BROWSE_AUTH_TOKEN=    # leave empty to disable auth
STEALTHY_AUTO_BROWSE_NUM_REPLICAS=5
```

### 3. Run

```bash
docker compose up -d
```

Gateway and LiteLLM UI at `http://localhost:4000`

### 4. Test

```bash
curl http://localhost:4000/chat/completions \
  -H "Authorization: Bearer YOUR_LITELLM_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{"model": "groq-llama-3.1-8b", "messages": [{"role": "user", "content": "hello"}]}'
```

## Object Storage (HybridS3)

S3-compatible object storage for hosting images and files so you can pass URLs directly into vision model API calls. Backed by [HybridS3](https://github.com/psyb0t/docker-hybrids3) — supports bearer token auth, plain HTTP upload, S3/boto3 compatibility, and automatic TTL expiry.

| Endpoint            | URL                                    |
| ------------------- | -------------------------------------- |
| S3 / plain HTTP API | `http://localhost:4000/storage`        |
| Health              | `http://localhost:4000/storage/health` |
| MCP server          | `http://localhost:4000/storage/mcp/`   |

The `uploads` bucket is **public-read** — no auth needed to fetch objects. Auth required to write.

Configure in `.env`:

```env
HYBRIDS3_MASTER_KEY=generate-with-openssl-rand-hex-32
HYBRIDS3_UPLOADS_KEY=generate-with-openssl-rand-hex-32
HYBRIDS3_UPLOADS_TTL=168h        # auto-delete after (default 7 days)
HYBRIDS3_UPLOADS_MAX_SIZE=100MB  # per-file size limit
```

### Plain HTTP upload/download

```bash
# Upload (bearer token auth)
curl -X PUT http://localhost:4000/storage/uploads/image.jpg \
  -H "Authorization: Bearer $HYBRIDS3_UPLOADS_KEY" \
  --data-binary @image.jpg

# Download (public — no auth)
curl http://localhost:4000/storage/uploads/image.jpg -o image.jpg
```

### S3 / boto3

```python
import boto3

s3 = boto3.client(
    "s3",
    endpoint_url="http://localhost:4000/storage",
    aws_access_key_id="uploads",
    aws_secret_access_key=HYBRIDS3_UPLOADS_KEY,
)

s3.upload_file("image.jpg", "uploads", "image.jpg")

# Public URL — no signing needed
url = "http://localhost:4000/storage/uploads/image.jpg"

# Or generate a presigned URL (private buckets)
url = s3.generate_presigned_url("get_object", Params={"Bucket": "uploads", "Key": "image.jpg"}, ExpiresIn=3600)
```

### Use in a vision model call

```bash
curl http://localhost:4000/chat/completions \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "vision",
    "messages": [{
      "role": "user",
      "content": [
        {"type": "text", "text": "what is in this image?"},
        {"type": "image_url", "image_url": {"url": "http://YOUR_SERVER:4000/storage/uploads/image.jpg"}}
      ]
    }]
  }'
```

> **Note:** For external LLM providers (OpenAI, Anthropic) to fetch the image, the URL must be publicly reachable — works on any server with a public IP or domain.

## Stealthy Auto Browse

A cluster of [docker-stealthy-auto-browse](https://github.com/psyb0t/docker-stealthy-auto-browse) browser replicas behind HAProxy. Each replica runs Camoufox (custom Firefox) with real OS-level mouse/keyboard input via PyAutoGUI. Passes Cloudflare, CreepJS, BrowserScan, Pixelscan, and all major bot detectors.

| Endpoint       | URL                                                         |
| -------------- | ----------------------------------------------------------- |
| Browser API    | `http://localhost:4000/stealthy-auto-browse/`               |
| MCP server     | `http://localhost:4000/stealthy-auto-browse/mcp/`           |
| HAProxy stats  | exposed internally on port 8081                             |
| Queue health   | `http://localhost:4000/stealthy-auto-browse/__queue/health` |
| Cluster status | `http://localhost:4000/stealthy-auto-browse/__queue/status` |

Configure in `.env`:

```env
STEALTHY_AUTO_BROWSE_AUTH_TOKEN=    # leave empty to disable auth
STEALTHY_AUTO_BROWSE_NUM_REPLICAS=5 # number of browser replicas
STEALTHY_AUTO_BROWSE_QUEUE_TIMEOUT=300  # seconds to wait in queue
```

Each replica: 256 MB RAM limit, 1 GB swap (total 1.25 GB per browser).

HAProxy routes:

- `/mcp/*` — sticky by `Mcp-Session-Id` header (MCP sessions stay on same replica)
- everything else — sticky by `INSTANCEID` cookie (browser sessions stay on same replica), max 1 concurrent request per replica

### Browser API usage

```bash
# Navigate to a URL
curl -X POST http://localhost:4000/stealthy-auto-browse/goto \
  -H "Content-Type: application/json" \
  -d '{"url": "https://example.com"}'

# Take a screenshot (returns base64 PNG)
curl -X POST http://localhost:4000/stealthy-auto-browse/screenshot \
  -H "Content-Type: application/json" \
  -d '{}'

# Get page text
curl -X POST http://localhost:4000/stealthy-auto-browse/get_text \
  -H "Content-Type: application/json" \
  -d '{}'

# Click at coordinates
curl -X POST http://localhost:4000/stealthy-auto-browse/system_click \
  -H "Content-Type: application/json" \
  -d '{"x": 640, "y": 400}'

# Type text
curl -X POST http://localhost:4000/stealthy-auto-browse/system_type \
  -H "Content-Type: application/json" \
  -d '{"text": "hello world"}'
```

## MCP Servers

Both HybridS3 and the browser cluster expose MCP (Model Context Protocol) servers. LiteLLM proxies these to all models that support tool use — any model on the gateway can navigate the web, take screenshots, and upload files.

The MCP servers are configured in `config.yaml` and available to all LiteLLM models automatically.

### Available MCP tools

**HybridS3** (`hybrids3`):

- `upload_file` — upload a file to a bucket
- `get_file` — fetch a file's content or URL
- `list_files` — list files in a bucket
- `delete_file` — delete a file

**Stealthy Auto Browse** (`stealthy_auto_browse`):

- `goto` — navigate to a URL
- `screenshot` — take a screenshot (returns base64 PNG)
- `get_text` — extract all text from current page
- `get_html` — get raw HTML
- `get_interactive_elements` — list clickable elements with coordinates
- `click` — click an element by selector
- `system_click` — click at screen coordinates (stealth)
- `fill` — fill an input field
- `system_type` — type text via OS keyboard (stealth)
- `send_key` — send a key press
- `scroll` — scroll the page
- `wait_for_element` — wait for a CSS selector
- `wait_for_text` — wait for text to appear
- `eval_js` — run JavaScript on the page
- `mouse_move` — move mouse to coordinates
- `browser_action` — perform a named browser action
- `run_script` — run a multi-step automation script atomically

### Example: AI agent that browses the web and uploads screenshots

```bash
curl http://localhost:4000/chat/completions \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "groq-llama-3.3-70b",
    "messages": [{
      "role": "user",
      "content": "Go to duckduckgo.com, search for '\''what is groq?'\'', get the results text, take a screenshot, upload it to the uploads bucket as search-result.png, and tell me the public URL and what you found."
    }]
  }'
```

The model will autonomously:

1. Call `goto` → navigate to DuckDuckGo
2. Call `get_interactive_elements` → find the search box
3. Call `system_click` + `system_type` → type the query
4. Call `send_key` → press Enter
5. Call `get_text` → read the results
6. Call `screenshot` → capture the page
7. Call `upload_file` → store in HybridS3
8. Return the public URL and a summary of findings

## File API

The claude-code containers support file management. Use the nginx routes to upload files, then reference them in prompts — Claude Code will read and process them directly.

**Auth:** use `CLAUDE_CODE_API_TOKEN` for `/claude-code/*`, `CLAUDE_CODE_ZAI_API_TOKEN` for `/claude-code-zai/*`.

```bash
# Upload a file
curl -X PUT http://localhost:4000/claude-code/files/myproject/data.csv \
  -H "Authorization: Bearer $CLAUDE_CODE_API_TOKEN" \
  --data-binary @data.csv

# List files in a workspace
curl http://localhost:4000/claude-code/files/myproject \
  -H "Authorization: Bearer $CLAUDE_CODE_API_TOKEN"

# Download a file
curl http://localhost:4000/claude-code/files/myproject/data.csv \
  -H "Authorization: Bearer $CLAUDE_CODE_API_TOKEN"

# Delete a file
curl -X DELETE http://localhost:4000/claude-code/files/myproject/data.csv \
  -H "Authorization: Bearer $CLAUDE_CODE_API_TOKEN"

# Check which workspaces are busy
curl http://localhost:4000/claude-code/status \
  -H "Authorization: Bearer $CLAUDE_CODE_API_TOKEN"

# Kill a running process
curl -X POST "http://localhost:4000/claude-code/run/cancel?workspace=myproject" \
  -H "Authorization: Bearer $CLAUDE_CODE_API_TOKEN"

# Use the uploaded file in a prompt
curl http://localhost:4000/chat/completions \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{"model": "claude-code-sonnet",
       "messages": [{"role": "user", "content": "analyze the CSV at data.csv"}],
       "extra_headers": {"x-claude-workspace": "myproject"}}'
```

**Workspace isolation** — pass `x-claude-workspace` to isolate sessions. Each workspace has its own file context and conversation history. Multiple workspaces run concurrently.

## Claude Code OAuth token

The `CLAUDE_CODE_OAUTH_TOKEN` uses your Claude Max subscription — no per-token API costs. Get it by running `claude setup-token` with an existing [docker-claude-code](https://github.com/psyb0t/docker-claude-code) install.

The token expires daily. To refresh:

```bash
TOKEN=$(python3 -c "import json; print(json.load(open('$HOME/.claude/.credentials.json'))['claudeAiOauth']['accessToken'])")
sed -i "s|^CLAUDE_CODE_OAUTH_TOKEN=.*|CLAUDE_CODE_OAUTH_TOKEN=$TOKEN|" .env
docker compose restart claude-code
```

## Notes

- All traffic enters through nginx on port 4000 — no other ports are exposed
- LiteLLM starts only after all dependencies are healthy
- Routing is latency-based with automatic retries (3) and provider fallbacks
- Free-tier providers (Cerebras, OpenRouter, Groq, HF, claude-code, claude-code-glm) are prioritized — paid APIs are last resort
- HuggingFace free tier includes a small monthly credit allowance (amount not officially published) — use smaller models for high-volume use
- All persistent data lives under `.data/` (bind mounts) — back it up or move it as needed
- The `.data/` directory is git-ignored; Docker creates subdirectories on first run

## License

WTFPL
