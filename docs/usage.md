# Usage

## Chat Completions

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
    "model": "mistral-large",
    "messages": [{"role": "user", "content": "explain mixture of experts"}]
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

## Browser Automation

The browser cluster can be used in two ways: directly via the REST API, or indirectly by letting an LLM invoke browser tools through MCP (see [mcp-tools.md](mcp-tools.md)).

### Direct REST API

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

### Python Example — Search, Screenshot, and Summarize

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
    json={"model": "smart", "messages": [
        {"role": "user", "content": f"Summarize these search results:\n\n{text[:8000]}"}
    ]})
print(r.json()["choices"][0]["message"]["content"])
print(f"Screenshot: {BASE}/storage/uploads/search.png")
```

## Object Storage

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

## Claudebox — Agentic Tasks

[Claudebox](https://github.com/psyb0t/docker-claudebox) wraps Claude Code in a Docker container and exposes it as an API. Each request runs through Claude Code's full agentic loop — it can read/write files, run shell commands, install packages, browse the web, and use tools, all within an isolated workspace.

Two instances are running: one authenticated via your OAuth token or Anthropic API key, and one connected to z.ai for GLM models. Both provide identical APIs and workspace capabilities.

**Always-active skills** — drop a `SKILL.md` file into a named subdirectory under `.data/claudebox/config/.always-skills/` (or `.data/claudebox-zai/config/.always-skills/` for the z.ai instance) and it will be injected into the system prompt of every Claude invocation automatically — no restarts needed, applies to API, MCP, chat, everything.

```
.data/claudebox/config/.always-skills/
└── my-rules/
    └── SKILL.md   ← injected into every session
```

Example `SKILL.md`:

```markdown
You are working inside a data pipeline project. Always use snake_case for variable names,
write pandas code compatible with Python 3.11, and never use deprecated APIs.
```

Skills stack — every `SKILL.md` found is appended in alphabetical order by directory name. Per-request `appendSystemPrompt` (via API header or request body) is appended after always-skills, so it always takes precedence.

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

## Image Generation

```bash
curl http://localhost:4000/images/generations \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{"model": "image-gen", "prompt": "a cat riding a skateboard, photorealistic"}'
```

## Vision

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

## Transcription

```bash
curl http://localhost:4000/audio/transcriptions \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -F "model=transcription" \
  -F "file=@audio.mp3"
```
