# Services Reference

## LiteLLM

| Endpoint               | URL                                           | Auth                    |
| ---------------------- | --------------------------------------------- | ----------------------- |
| Chat completions       | `POST /chat/completions`                      | `Bearer $LITELLM_MASTER_KEY` |
| Embeddings             | `POST /embeddings`                            | `Bearer $LITELLM_MASTER_KEY` |
| Image generation       | `POST /images/generations`                    | `Bearer $LITELLM_MASTER_KEY` |
| Audio transcription    | `POST /audio/transcriptions`                  | `Bearer $LITELLM_MASTER_KEY` |
| Models list            | `GET /models`                                 | `Bearer $LITELLM_MASTER_KEY` |
| Health check           | `GET /health/liveliness`                      | none                    |
| MCP server (all tools) | `POST /mcp/`                                  | `Bearer $LITELLM_MASTER_KEY` |
| Admin UI               | `GET /litellm-admin/`                         | optional basic auth     |

The admin UI at `/litellm-admin/` is rate-limited to 5 requests/minute. Set `LITELLM_UI_BASIC_AUTH=user:password` in `.env` to enable HTTP basic auth on top of that. Direct access to `/ui` returns 404.

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

Set `STEALTHY_AUTO_BROWSE_AUTH_TOKEN` in `.env` to require bearer auth. Leave empty to disable auth.

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

All actions: `goto`, `get_text`, `get_html`, `get_interactive_elements`, `screenshot`, `system_click`, `system_type`, `send_key`, `click`, `fill`, `scroll`, `mouse_move`, `wait_for_element`, `wait_for_text`, `eval_js`, `browser_action`, `run_script`.

`run_script` accepts a `steps` array of action objects — executes them sequentially on the same replica in a single HTTP round-trip:

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

## Cloudflared (optional)

Disabled by default. Enable via `COMPOSE_PROFILES=cloudflared` in `.env`.

### Quick tunnel (no account needed)

```env
COMPOSE_PROFILES=cloudflared
```

Cloudflare assigns a random `*.trycloudflare.com` URL and logs it on startup:

```bash
docker compose up -d
docker compose logs cloudflared | grep trycloudflare
```

### Named tunnel (fixed domain, requires Cloudflare account)

```env
COMPOSE_PROFILES=cloudflared
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
