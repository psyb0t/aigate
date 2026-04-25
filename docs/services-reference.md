# Services Reference

## LiteLLM

| Endpoint               | URL                                           | Auth                    |
| ---------------------- | --------------------------------------------- | ----------------------- |
| Chat completions       | `POST /chat/completions`                      | `Bearer $LITELLM_MASTER_KEY` |
| Embeddings             | `POST /embeddings`                            | `Bearer $LITELLM_MASTER_KEY` |
| Image generation       | `POST /images/generations`                    | `Bearer $LITELLM_MASTER_KEY` |
| Audio transcription    | `POST /audio/transcriptions`                  | `Bearer $LITELLM_MASTER_KEY` |
| Text-to-speech         | `POST /audio/speech`                           | `Bearer $LITELLM_MASTER_KEY` |
| Models list            | `GET /models`                                 | `Bearer $LITELLM_MASTER_KEY` |
| Health check           | `GET /health/liveliness`                      | none                    |
| MCP server (all tools) | `POST /mcp/`                                  | `Bearer $LITELLM_MASTER_KEY` |
| Admin UI               | `GET /ui/`                                    | optional basic auth     |

The admin UI at `/ui/` is rate-limited to 30 requests/minute by default (configurable via `RATELIMIT_ADMIN` in `.env`). Set `LITELLM_UI_BASIC_AUTH=user:password` in `.env` to enable HTTP basic auth on top of that.

---

## Claudebox

### Chat (via LiteLLM)

Use claudebox models through the standard LiteLLM chat completions endpoint. Pass workspace via extra headers:

```bash
curl http://localhost:4000/chat/completions \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "claudebox-sonnet",
    "messages": [{"role": "user", "content": "analyze data.csv and summarize it"}],
    "extra_headers": {"X-Claude-Workspace": "myproject"}
  }'
```

Available models: `claudebox-haiku`, `claudebox-sonnet`, `claudebox-opus`, `claudebox-glm-4.5-air`, `claudebox-glm-4.7`, `claudebox-glm-5.1`

### Direct API endpoints

Base URLs: `http://localhost:4000/claudebox/` (OAuth/API key) and `http://localhost:4000/claudebox-zai/` (GLM).

All endpoints (except `/health`) require `Authorization: Bearer $CLAUDEBOX_API_TOKEN` (or `$CLAUDEBOX_ZAI_API_TOKEN` for the zai instance).

| Method | Path                                  | Description                                              |
| ------ | ------------------------------------- | -------------------------------------------------------- |
| `GET`  | `/claudebox/health`                   | Health check — no auth required                          |
| `GET`  | `/claudebox/status`                   | Returns which workspaces currently have running Claude processes |
| `POST` | `/claudebox/run`                      | Run a prompt through Claude Code                         |
| `POST` | `/claudebox/run/cancel?workspace=<x>` | Kill the running Claude process in a workspace           |
| `PUT`  | `/claudebox/files/<workspace>/<path>` | Upload a file to a workspace                             |
| `GET`  | `/claudebox/files/<workspace>/<path>` | Download a file from a workspace                         |
| `GET`  | `/claudebox/files/<workspace>`        | List files in a workspace                                |
| `GET`  | `/claudebox/files`                    | List files in the root workspace directory               |
| `DELETE`| `/claudebox/files/<workspace>/<path>`| Delete a file from a workspace                           |

### POST /claudebox/run — request body

| Field                | Type   | Description                                                              | Default         |
| -------------------- | ------ | ------------------------------------------------------------------------ | --------------- |
| `prompt`             | string | The prompt to send to Claude Code                                        | _(required)_    |
| `workspace`          | string | Subpath under `/workspaces` for isolation                                | default workspace |
| `model`              | string | `haiku`, `sonnet`, `opus`, or full model name                            | account default |
| `systemPrompt`       | string | Replace the default system prompt entirely                               | _(none)_        |
| `appendSystemPrompt` | string | Append to the default system prompt without replacing it                 | _(none)_        |
| `jsonSchema`         | string | JSON Schema string — Claude returns JSON matching this schema            | _(none)_        |
| `effort`             | string | Reasoning effort: `low`, `medium`, `high`, `max`                        | _(none)_        |
| `outputFormat`       | string | `json` or `json-verbose` (includes full tool call history)               | `json`          |
| `noContinue`         | bool   | Start a fresh session instead of continuing the previous one             | `false`         |
| `resume`             | string | Resume a specific session by session ID                                  | _(none)_        |
| `fireAndForget`      | bool   | Keep the Claude process running even if the HTTP client disconnects      | `false`         |

Returns **409 Conflict** if the workspace already has a running Claude process.

### Response format (json)

```json
{
  "type": "result",
  "subtype": "success",
  "isError": false,
  "result": "the response text",
  "numTurns": 3,
  "durationMs": 12400,
  "totalCostUsd": 0.049,
  "sessionId": "abc123-...",
  "usage": {
    "inputTokens": 312,
    "outputTokens": 87,
    "cacheReadInputTokens": 1024
  }
}
```

### Response format (json-verbose)

Same as `json` but includes a `turns` array with every tool call, tool result, and assistant message:

```json
{
  "type": "result",
  "subtype": "success",
  "result": "Done. I created data_summary.md with statistics.",
  "turns": [
    {
      "role": "assistant",
      "content": [
        {"type": "tool_use", "id": "toolu_abc", "name": "Bash", "input": {"command": "head data.csv"}}
      ]
    },
    {
      "role": "tool_result",
      "content": [
        {"type": "toolResult", "toolUseId": "toolu_abc", "isError": false, "content": "id,name,value\n1,foo,42\n..."}
      ]
    }
  ],
  "numTurns": 5,
  "totalCostUsd": 0.089,
  "sessionId": "abc123-..."
}
```

### OpenAI-compatible endpoint

Claudebox also speaks OpenAI's `chat/completions` protocol directly. This is what LiteLLM uses internally, but you can also hit it directly:

| Method | Path                               | Description                      |
| ------ | ---------------------------------- | -------------------------------- |
| `GET`  | `/claudebox/openai/v1/models`      | List available models            |
| `POST` | `/claudebox/openai/v1/chat/completions` | Chat completions (streaming + non-streaming) |

Custom headers for workspace control:

| Header                          | Description                                                      |
| ------------------------------- | ---------------------------------------------------------------- |
| `X-Claude-Workspace`            | Workspace subpath to run in                                      |
| `X-Claude-Continue`             | Set to `1`, `true`, or `yes` to continue the previous session    |
| `X-Claude-Append-System-Prompt` | Text to append to the system prompt for this request             |

Note: `temperature`, `max_tokens`, `tools`, and other standard OpenAI fields are accepted but silently ignored — Claude Code manages these internally.

### MCP server

Claudebox exposes an MCP server at `/claudebox/mcp/`. 5 tools: `claude_run`, `read_file`, `write_file`, `list_files`, `delete_file`. See [mcp-tools.md](mcp-tools.md) for full parameter reference.

### Workspace isolation

Each workspace subpath gets its own directory, file context, and conversation history. Only one Claude process can run per workspace at a time — concurrent requests return 409. Use different workspace names for parallel work:

```bash
# these run concurrently without conflicting
curl -X POST http://localhost:4000/claudebox/run \
  -H "Authorization: Bearer $CLAUDEBOX_API_TOKEN" \
  -d '{"prompt": "write a Go HTTP server", "workspace": "go-project"}'

curl -X POST http://localhost:4000/claudebox/run \
  -H "Authorization: Bearer $CLAUDEBOX_API_TOKEN" \
  -d '{"prompt": "write pytest tests", "workspace": "py-tests"}'
```

---

## Object Storage (hybrids3)

Base URL: `http://localhost:4000/storage/`

### HTTP API

| Method   | Path                              | Auth                        | Description                                        |
| -------- | --------------------------------- | --------------------------- | -------------------------------------------------- |
| `GET`    | `/storage/health`                 | none                        | Returns `{"status":"ok"}`                          |
| `GET`    | `/storage/`                       | master or bucket key        | List buckets (master sees all, bucket key sees own)|
| `GET`    | `/storage/<bucket>`               | public: none / private: key | List objects (supports `?prefix=` and `?max-keys=`)|
| `PUT`    | `/storage/<bucket>/<key>`         | bucket key or master key    | Upload object (MIME auto-detected)                 |
| `GET`    | `/storage/<bucket>/<key>`         | public: none / private: key | Download object                                    |
| `HEAD`   | `/storage/<bucket>/<key>`         | public: none / private: key | Object metadata — no body                          |
| `DELETE` | `/storage/<bucket>/<key>`         | bucket key or master key    | Delete object — 204 even if it doesn't exist       |
| `POST`   | `/storage/presign/<bucket>/<key>` | bucket key or master key    | Generate presigned URL                             |
| `POST`   | `/storage/mcp/`                   | per-tool `auth_key`         | MCP endpoint                                       |

Authentication: pass `Authorization: Bearer <key>` where `<key>` is the bucket's private key or `$HYBRIDS3_MASTER_KEY`.

The `uploads` bucket is configured as public-read — GET/LIST require no auth. PUT/DELETE always require the bucket key.

### Presigned URLs

```bash
# generate a presigned URL (expires in 1 hour by default, max 7 days)
curl -X POST "http://localhost:4000/storage/presign/uploads/photo.jpg?expires=3600" \
  -H "Authorization: Bearer $HYBRIDS3_UPLOADS_KEY"

# response for public bucket — plain URL, no expiry
{"url": "http://localhost:4000/storage/uploads/photo.jpg", "expires": null}

# response for private bucket — signed URL with expiry
{"url": "http://localhost:4000/storage/private/doc.pdf?X-Amz-Algorithm=...&X-Amz-Signature=...", "expires": 3600}

# use the presigned URL — no auth header needed
curl "http://localhost:4000/storage/uploads/photo.jpg"
```

### S3-compatible access (boto3)

```python
import boto3
from botocore.config import Config

s3 = boto3.client(
    "s3",
    endpoint_url="http://localhost:4000/storage",
    aws_access_key_id="uploads",           # bucket name (public_key)
    aws_secret_access_key=HYBRIDS3_UPLOADS_KEY,
    region_name="us-east-1",
    config=Config(signature_version="s3v4"),
)

s3.upload_file("image.png", "uploads", "image.png")
s3.download_file("uploads", "image.png", "local.png")
s3.list_objects_v2(Bucket="uploads", Prefix="images/")
s3.delete_object(Bucket="uploads", Key="image.png")

# generate presigned URL via boto3
url = s3.generate_presigned_url(
    "get_object",
    Params={"Bucket": "uploads", "Key": "image.png"},
    ExpiresIn=3600,
)
```

### Response headers

Every response includes `X-Request-Id` for log correlation and `X-Content-Type-Options: nosniff`. Upload responses include `ETag` (MD5 of content). GET/HEAD responses include `ETag`, `Last-Modified`, `Content-Length`, and `Content-Type` (auto-detected from content).

### Concurrency and locking

Each object key has its own async read-write lock. Multiple concurrent reads are allowed. Writes are exclusive — a write blocks all other readers and writers on that key. Requests that can't acquire the lock within 30 seconds, or that hold it for more than 300 seconds, get 503.

### TTL

The `uploads` bucket has TTL configured (default: `HYBRIDS3_UPLOADS_TTL`, typically 168h / 7 days). Uploading a file resets its expiry clock. A background sweep runs every minute and deletes expired objects.

---

## Browser Cluster (stealthy-auto-browse)

| Endpoint             | URL                                                                 | Auth                         |
| -------------------- | ------------------------------------------------------------------- | ---------------------------- |
| Browser API          | `POST /stealthy-auto-browse/`                                       | optional bearer token        |
| Screenshot (browser) | `GET /stealthy-auto-browse/screenshot/browser`                      | optional bearer token        |
| Screenshot (desktop) | `GET /stealthy-auto-browse/screenshot/desktop`                      | optional bearer token        |
| MCP server           | `POST /stealthy-auto-browse/mcp/`                                   | optional bearer token        |
| Queue health         | `GET /stealthy-auto-browse/__queue/health`                          | none                         |
| Cluster status       | `GET /stealthy-auto-browse/__queue/status`                          | none                         |

Set `STEALTHY_AUTO_BROWSE_AUTH_TOKEN` in `.env` to set the bearer auth token. Defaults to `lulz-4-security` if unset — always change this in production.

### Cluster configuration

- 5 browser replicas by default — set `STEALTHY_AUTO_BROWSE_NUM_REPLICAS` to change
- Each replica: 256 MB RAM, up to 1 GB swap
- HAProxy routes requests to replicas and enforces session stickiness:
  - MCP requests: pinned by `Mcp-Session-Id` header
  - All other requests: pinned by `INSTANCEID` cookie, max 1 concurrent request per replica

### Browser API request body

```json
{
  "action": "goto",
  "url": "https://example.com"
}
```

Atomic actions: `goto`, `get_text`, `get_html`, `get_interactive_elements`, `screenshot`, `system_click`, `system_type`, `send_key`, `click`, `fill`, `scroll`, `mouse_move`, `wait_for_element`, `wait_for_text`, `eval_js`, `browser_action`.

`run_script` composes multiple actions into a single request — executes them sequentially on the same replica in a single HTTP round-trip:

```json
{
  "action": "run_script",
  "steps": [
    {"action": "goto", "url": "https://example.com"},
    {"action": "wait_for_element", "selector": "h1", "timeout": 5},
    {"action": "get_text"}
  ]
}
```

---

## sd.cpp — Local Image Generation (optional, `SDCPP=1`)

Local image generation via [stable-diffusion.cpp](https://github.com/leejet/stable-diffusion.cpp) with a Go wrapper. CPU variant runs with `SDCPP=1`, CUDA variant with `SDCPP_CUDA=1`. Both expose an OpenAI-compatible `/v1/images/generations` endpoint proxied through LiteLLM.

### Endpoints (internal — accessed through LiteLLM, not directly via nginx)

| Endpoint | URL | Description |
| -------- | --- | ----------- |
| Image generation | `POST /v1/images/generations` | OpenAI-compatible, proxied through LiteLLM |
| Load model | `POST /sdcpp/v1/load?model=<key>` | Pre-load a model without generating |
| Unload model | `POST /sdcpp/v1/unload` | Free VRAM/RAM |
| Cancel generation | `POST /sdcpp/v1/cancel` | Kill in-progress generation |
| Status | `GET /sdcpp/v1/status` | Current state: loaded model, generating, process info |
| Models list | `GET /v1/models` | Available models |
| Health | `GET /sdcpp/v1/health` | Wrapper health check |

### Models

**CPU** (`SDCPP=1`): sd-turbo, sdxl-turbo

**CUDA** (`SDCPP_CUDA=1`): sd-turbo, sdxl-turbo, sdxl-lightning, flux-schnell, juggernaut-xi

### Behavior

- **Auto-load**: sending a generation request loads the model automatically if not loaded
- **Model hot-swap**: requesting a different model stops the current sd-server, starts a new one
- **Idle timeout**: unloads model after 5 minutes of inactivity (configurable)
- **Non-blocking**: concurrent requests get 503 immediately instead of queuing. The LiteLLM resource manager semaphore handles scheduling.
- **CUDA resource manager**: only one CUDA job (LLM, image gen, TTS, STT) runs at a time. Competing services are unloaded before the request proceeds.

### Environment variables

| Variable | Default | Description |
| -------- | ------- | ----------- |
| `SDCPP_IDLE_TIMEOUT` | `5m` | CPU idle timeout before auto-unload |
| `SDCPP_CUDA_IDLE_TIMEOUT` | `5m` | CUDA idle timeout before auto-unload |
| `SDCPP_MEM_LIMIT` | `12g` | CPU container memory limit |
| `SDCPP_MEMSWAP_LIMIT` | `24g` | CPU container memory + swap limit |
| `SDCPP_CPUS` | `4.0` | CPU container CPU limit |
| `SDCPP_CUDA_MEM_LIMIT` | `12g` | CUDA container memory limit |
| `SDCPP_CUDA_MEMSWAP_LIMIT` | `24g` | CUDA container memory + swap limit |
| `SDCPP_CUDA_CPUS` | `4.0` | CUDA container CPU limit |
| `SDCPP_LOAD_TIMEOUT` / `SDCPP_CUDA_LOAD_TIMEOUT` | `10m` | Max time to wait for model load |
| `SDCPP_VERBOSE` / `SDCPP_CUDA_VERBOSE` | `false` | Debug logging |
| `SDCPP_LOG_LEVEL` / `SDCPP_CUDA_LOG_LEVEL` | `info` | Log level |

---

## MCP Tools — Media Generation (auto-enabled)

Auto-enabled when any image or TTS provider is active (HuggingFace, OpenAI, Speaches, SDCPP, CUDA). Runs as an internal service — no direct nginx route, accessed only through LiteLLM's aggregated MCP endpoint at `/mcp/`.

| Endpoint               | URL                | Auth                              |
| ---------------------- | ------------------ | --------------------------------- |
| MCP server (via proxy) | `POST /mcp/`       | `Bearer $LITELLM_MASTER_KEY`      |
| Health (internal only) | `GET :8000/health`  | none (not exposed via nginx)      |

### Tools

- `generate_image` — create images from text prompts (FLUX, DALL-E, Stable Diffusion depending on enabled providers)
- `generate_tts` — generate speech audio from text (Kokoro, Qwen3-TTS, OpenAI TTS depending on enabled providers)

Both tools return structured JSON with persistent HybridS3 URLs — no base64 blobs sent to the LLM.

See [mcp-tools.md](mcp-tools.md#mcp_tools--2-tools-auto-enabled-with-imagetts-providers) for full parameter reference.

### Environment variables

| Variable               | Default  | Description                          |
| ---------------------- | -------- | ------------------------------------ |
| `MCP_TOOLS_AUTH_TOKEN`  | —       | Bearer token for MCP auth (required) |
| `MCP_MEM_LIMIT`        | `256m`   | Container memory limit               |
| `MCP_MEMSWAP_LIMIT`    | `512m`   | Container memory + swap limit        |
| `MCP_CPUS`             | `0.5`    | CPU limit                            |

---

## LibreChat (optional, `LIBRECHAT=1`)

Web UI for LLM interaction at `/librechat/`. Pre-configured with all LiteLLM models and MCP tools. Uses MongoDB for conversation storage.

| Endpoint      | URL                          | Auth                     |
| ------------- | ---------------------------- | ------------------------ |
| Web UI        | `GET /librechat/`            | email/password (own auth)|
| API           | `/librechat/api/*`           | JWT (managed by LibreChat)|

### Authentication

LibreChat has its own email/password authentication — no basic auth (SPAs and basic auth are incompatible due to Authorization header collision). The first registered user automatically becomes admin. After creating your account, set `LIBRECHAT_ALLOW_REGISTRATION=false` in `.env` and restart to lock registration.

### MCP tools integration

All MCP tools from the LiteLLM aggregated endpoint are available in LibreChat conversations. Connected via streamable-http with `apiKey.source: admin` (bypasses LibreChat's OAuth detection probe). Configuration in `librechat/librechat.yaml`.

### Environment variables

| Variable                              | Default                                  | Description                                  |
| ------------------------------------- | ---------------------------------------- | -------------------------------------------- |
| `LIBRECHAT_DOMAIN_CLIENT`             | `http://librechat:3080/librechat`        | Public URL for client (sets `<base href>`)   |
| `LIBRECHAT_DOMAIN_SERVER`             | `http://librechat:3080/librechat`        | Public URL for server API                    |
| `LIBRECHAT_CREDS_KEY`                 | —                                        | Encryption key for stored credentials (64 hex chars) |
| `LIBRECHAT_CREDS_IV`                  | —                                        | Encryption IV (32 hex chars)                 |
| `LIBRECHAT_JWT_SECRET`                | —                                        | JWT signing secret                           |
| `LIBRECHAT_TITLE_MODEL`               | `groq-llama-3.3-70b`                     | Model for auto-titling conversations         |
| `LIBRECHAT_ALLOW_REGISTRATION`        | `true`                                   | Set to `false` after creating admin account  |
| `LIBRECHAT_ALLOW_EMAIL_LOGIN`         | `true`                                   | Enable email/password login                  |
| `LIBRECHAT_ALLOW_SOCIAL_LOGIN`        | `false`                                  | Enable social login providers                |
| `LIBRECHAT_ALLOW_UNVERIFIED_EMAIL_LOGIN` | `true`                                | Allow login without email verification       |
| `LIBRECHAT_DEBUG_LOGGING`             | `true`                                   | Enable debug-level logging                   |
| `LIBRECHAT_DEBUG_CONSOLE`             | `false`                                  | Log to console (in addition to file)         |
| `LIBRECHAT_MEM_LIMIT`                 | `512m`                                   | LibreChat container memory limit             |
| `LIBRECHAT_MEMSWAP_LIMIT`             | `1g`                                     | LibreChat container memory + swap limit      |
| `LIBRECHAT_CPUS`                      | `1.0`                                    | LibreChat CPU limit                          |
| `LIBRECHAT_MONGO_MEM_LIMIT`           | `512m`                                   | MongoDB container memory limit               |
| `LIBRECHAT_MONGO_MEMSWAP_LIMIT`       | `1g`                                     | MongoDB container memory + swap limit        |
| `LIBRECHAT_MONGO_CPUS`                | `0.5`                                    | MongoDB CPU limit                            |
| `RATELIMIT_LIBRECHAT`                 | `500r/m`                                 | Nginx rate limit                             |
| `RATELIMIT_LIBRECHAT_BURST`           | `100`                                    | Burst allowance                              |
| `TIMEOUT_LIBRECHAT`                   | `600s`                                   | Nginx proxy timeout                          |
| `LIBRECHAT_MAX_BODY_SIZE`             | `25m`                                    | Max upload size                              |
| `DATA_DIR_LIBRECHAT`                  | `${DATA_DIR}/librechat`                  | Data directory (MongoDB + uploads)           |

---

## SearXNG (optional, `SEARXNG=1`)

Self-hosted meta-search engine at `/searxng/`. Aggregates results from Google, Bing, DuckDuckGo, and Wikipedia. Protected by nginx admin auth (`LITELLM_UI_BASIC_AUTH`). Rate-limited to 60 req/min by default.

Also exposed to the MCP `search_web` tool — when `SEARXNG=1`, the MCP tools server gains a `search_web` tool that any function-calling model can invoke.

| Endpoint  | URL               | Auth               |
| --------- | ----------------- | ------------------ |
| Search UI | `GET /searxng/`   | nginx basic auth   |
| JSON API  | `GET /searxng/search?q=...&format=json` | nginx basic auth |

### Environment variables

| Variable                  | Default     | Description                          |
| ------------------------- | ----------- | ------------------------------------ |
| `RATELIMIT_SEARXNG`       | `60r/m`     | Nginx rate limit                     |
| `RATELIMIT_SEARXNG_BURST` | `20`        | Burst allowance                      |
| `TIMEOUT_SEARXNG`         | `60s`       | Nginx proxy timeout                  |
| `SEARXNG_MEM_LIMIT`       | `256m`      | Container memory limit               |
| `SEARXNG_MEMSWAP_LIMIT`   | `512m`      | Container memory + swap limit        |
| `SEARXNG_CPUS`            | `0.5`       | CPU limit                            |

Settings are in `searxng/settings.yml` (mounted read-only into the container). The default config enables HTML and JSON output formats and activates Google, Bing, DuckDuckGo, and Wikipedia engines with no rate limiter.

---

## Langfuse (optional, `LANGFUSE=1`)

LLM observability and tracing at `/langfuse/`. Tracks every LiteLLM request — latency, token usage, costs, model, prompt/response — and visualizes them in a web dashboard. When enabled, LiteLLM automatically sends `success_callback` and `failure_callback` events to Langfuse.

| Endpoint   | URL              | Auth                        |
| ---------- | ---------------- | --------------------------- |
| Web UI     | `GET /langfuse/` | Langfuse email/password auth |
| Public API | `/langfuse/api/public/*` | Langfuse public key |
| Health     | `GET /langfuse/api/public/health` | none |

### Setup

On first start, Langfuse creates its database schema automatically. Log in at `/langfuse/` and create an account (first user becomes owner). Then:

1. Go to **Settings → API Keys** and create a project key pair (`pk-lf-...` / `sk-lf-...`)
2. Add them to `.env`:
   ```env
   LANGFUSE_PUBLIC_KEY=pk-lf-...
   LANGFUSE_SECRET_KEY=sk-lf-...
   ```
3. Restart: `make restart`

LiteLLM will now send all traces. The `LANGFUSE_HOST` env var on the LiteLLM container points to `http://langfuse:3000` by default — no external network call.

### Environment variables

| Variable                   | Default                              | Description                                         |
| -------------------------- | ------------------------------------ | --------------------------------------------------- |
| `LANGFUSE_NEXTAUTH_SECRET` | —                                    | NextAuth session secret (generate once, don't change) |
| `LANGFUSE_SALT`            | —                                    | Password hashing salt (generate once, don't change) |
| `LANGFUSE_PUBLIC_KEY`      | _(empty)_                            | LiteLLM → Langfuse tracing public key               |
| `LANGFUSE_SECRET_KEY`      | _(empty)_                            | LiteLLM → Langfuse tracing secret key               |
| `LANGFUSE_HOST`            | `http://langfuse:3000`               | Override if running Langfuse externally             |
| `LANGFUSE_URL`             | `https://aigate.51k.eu/langfuse`     | Public URL (used as NextAuth callback base)         |
| `RATELIMIT_LANGFUSE`       | `300r/m`                             | Nginx rate limit                                    |
| `RATELIMIT_LANGFUSE_BURST` | `30`                                 | Burst allowance                                     |
| `TIMEOUT_LANGFUSE`         | `600s`                               | Nginx proxy timeout                                 |
| `LANGFUSE_MEM_LIMIT`       | `1g`                                 | Container memory limit                              |
| `LANGFUSE_MEMSWAP_LIMIT`   | `2g`                                 | Container memory + swap limit                       |
| `LANGFUSE_CPUS`            | `1.0`                                | CPU limit                                           |

---

## Cloudflared (optional, `CLOUDFLARED=1`)

Disabled by default. Enable by setting `CLOUDFLARED=1` in `.env`.

### Quick tunnel (no account needed)

```env
CLOUDFLARED=1
```

Cloudflare assigns a random `*.trycloudflare.com` URL and logs it on startup:

```bash
docker compose up -d
docker compose logs cloudflared | grep trycloudflare
```

### Named tunnel (fixed domain, requires Cloudflare account)

```env
CLOUDFLARED=1
CLOUDFLARED_CONFIG=/absolute/path/to/config.yml
CLOUDFLARED_CREDS=/absolute/path/to/credentials.json
```

Example `config.yml`:

```yaml
tunnel: <your-tunnel-id>
credentials-file: /etc/cloudflared/credentials.json
ingress:
  - hostname: aigate.yourdomain.com
    service: http://nginx:4000
  - service: http_status:404
```

Get your tunnel ID and credentials: [Cloudflare Tunnel guide](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/get-started/)

---

## Resource Management

Local services (Ollama, sd.cpp, Speaches, Qwen3-TTS) share limited hardware. The platform coordinates them automatically — no manual model management needed.

### Idle auto-unload

Every local service unloads models after a period of inactivity:

| Service | Default idle timeout | Configurable via |
| ------- | -------------------- | ---------------- |
| Ollama (CPU/CUDA) | 5 minutes | Ollama's built-in `keep_alive` |
| sd.cpp CPU | 5 minutes | `SDCPP_IDLE_TIMEOUT` |
| sd.cpp CUDA | 5 minutes | `SDCPP_CUDA_IDLE_TIMEOUT` |
| Speaches | On-demand unload | Resource manager triggers `DELETE /api/ps/{model}` |
| Qwen3 CUDA TTS | On-demand unload | Resource manager triggers `POST /unload` |

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
4. The request proceeds
5. On completion (success or failure), the semaphore is released

### Unload mechanisms

Each service has its own unload API:

| Service | Unload method |
| ------- | ------------- |
| Ollama | `POST /api/generate {"model": "...", "keep_alive": 0}` |
| sd.cpp | `POST /sdcpp/v1/unload` |
| Speaches | `DELETE /api/ps/{model_id}` |
| Qwen3 CUDA TTS | `POST /unload` |

### Non-blocking rejection

The sd.cpp wrapper uses `TryLock` — if a generation or model swap is in progress, new requests get 503 immediately instead of queuing. Scheduling happens at the LiteLLM layer via the semaphore, not inside individual services.
