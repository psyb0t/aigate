# Usage

## Chat Completions

Standard OpenAI-compatible chat completions. Works with any OpenAI SDK, library, or tool that supports custom base URLs.

```bash
# cloud provider (free tier, auto-fallback on rate limit)
curl http://localhost:4000/chat/completions \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{"model": "mistral-large", "messages": [{"role": "user", "content": "explain mixture of experts"}]}'

# streaming (SSE)
curl http://localhost:4000/chat/completions \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{"model": "cerebras-qwen3-235b", "messages": [{"role": "user", "content": "write a haiku"}], "stream": true}'
```

### Python (openai SDK)

```python
from openai import OpenAI

client = OpenAI(
    base_url="http://localhost:4000",
    api_key=LITELLM_MASTER_KEY,
)

# chat
resp = client.chat.completions.create(
    model="cerebras-qwen3-235b",
    messages=[{"role": "user", "content": "hello"}],
)
print(resp.choices[0].message.content)

# streaming
stream = client.chat.completions.create(
    model="cerebras-qwen3-235b",
    messages=[{"role": "user", "content": "count to 10"}],
    stream=True,
)
for chunk in stream:
    print(chunk.choices[0].delta.content or "", end="", flush=True)
```

---

## Browser Automation

The browser cluster can be used directly via the REST API, or indirectly by letting an LLM invoke browser tools through MCP.

### Direct REST API

```bash
# navigate to a page
curl -X POST http://localhost:4000/stealthy-auto-browse/ \
  -H "Authorization: Bearer $STEALTHY_AUTO_BROWSE_AUTH_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"action": "goto", "url": "https://example.com"}'

# get all visible text
curl -X POST http://localhost:4000/stealthy-auto-browse/ \
  -H "Authorization: Bearer $STEALTHY_AUTO_BROWSE_AUTH_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"action": "get_text"}'

# find all interactive elements with their coordinates
curl -X POST http://localhost:4000/stealthy-auto-browse/ \
  -H "Authorization: Bearer $STEALTHY_AUTO_BROWSE_AUTH_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"action": "get_interactive_elements", "visible_only": true}'

# click at coordinates (OS-level, undetectable)
curl -X POST http://localhost:4000/stealthy-auto-browse/ \
  -H "Authorization: Bearer $STEALTHY_AUTO_BROWSE_AUTH_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"action": "system_click", "x": 640, "y": 400}'

# type text (OS-level keyboard input)
curl -X POST http://localhost:4000/stealthy-auto-browse/ \
  -H "Authorization: Bearer $STEALTHY_AUTO_BROWSE_AUTH_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"action": "system_type", "text": "hello world"}'

# screenshot — returns raw PNG (1920x1080 by default, always resize)
curl -H "Authorization: Bearer $STEALTHY_AUTO_BROWSE_AUTH_TOKEN" \
  "http://localhost:4000/stealthy-auto-browse/screenshot/browser?whLargest=512" -o screenshot.png
curl -H "Authorization: Bearer $STEALTHY_AUTO_BROWSE_AUTH_TOKEN" \
  "http://localhost:4000/stealthy-auto-browse/screenshot/browser?width=800" -o screenshot.png

# run a multi-step script atomically (all steps on the same replica, single request)
curl -X POST http://localhost:4000/stealthy-auto-browse/ \
  -H "Authorization: Bearer $STEALTHY_AUTO_BROWSE_AUTH_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "action": "run_script",
    "steps": [
      {"action": "goto", "url": "https://duckduckgo.com"},
      {"action": "system_click", "x": 950, "y": 513},
      {"action": "system_type", "text": "what is groq?"},
      {"action": "send_key", "key": "enter"},
      {"action": "wait_for_element", "selector": "[data-testid='\''result'\'']", "timeout": 10},
      {"action": "get_text"}
    ]
  }'
```

Browser sessions are sticky via the `INSTANCEID` cookie. Use a persistent HTTP client to keep your session on the same replica across requests.

### Python — search, screenshot, upload, summarize

```python
import requests

session = requests.Session()  # sticky via INSTANCEID cookie
BASE = "http://localhost:4000"
SAB_AUTH = {"Authorization": f"Bearer {STEALTHY_AUTO_BROWSE_AUTH_TOKEN}"}

def browser(action, **kwargs):
    r = session.post(f"{BASE}/stealthy-auto-browse/", headers=SAB_AUTH, json={"action": action, **kwargs})
    r.raise_for_status()
    return r.json()["data"]

# navigate and search
browser("goto", url="https://duckduckgo.com")
browser("system_click", x=950, y=513)
browser("system_type", text="what is groq?")
browser("send_key", key="enter")
browser("wait_for_element", selector="[data-testid='result']", timeout=10000)
text = browser("get_text")["text"]

# screenshot and upload
screenshot = session.get(f"{BASE}/stealthy-auto-browse/screenshot/browser", headers=SAB_AUTH).content
requests.put(
    f"{BASE}/storage/uploads/search.png",
    headers={"Authorization": f"Bearer {HYBRIDS3_UPLOADS_KEY}", "Content-Type": "image/png"},
    data=screenshot,
)

# ask an LLM to summarize
r = requests.post(f"{BASE}/chat/completions",
    headers={"Authorization": f"Bearer {LITELLM_MASTER_KEY}", "Content-Type": "application/json"},
    json={"model": "cerebras-qwen3-235b", "messages": [
        {"role": "user", "content": f"Summarize these search results:\n\n{text[:8000]}"}
    ]})
print(r.json()["choices"][0]["message"]["content"])
```

---

## Object Storage

[hybrids3](https://github.com/psyb0t/docker-hybrids3) — S3-compatible, public-read uploads bucket, bearer token auth, TTL-based expiry.

### Basic CRUD

```bash
# upload (MIME type auto-detected from content)
curl -X PUT http://localhost:4000/storage/uploads/image.png \
  -H "Authorization: Bearer $HYBRIDS3_UPLOADS_KEY" \
  -H "Content-Type: image/png" \
  --data-binary @image.png

# download — public, no auth required
curl http://localhost:4000/storage/uploads/image.png -o image.png

# list files (supports ?prefix= and ?max-keys=)
curl "http://localhost:4000/storage/uploads?prefix=images/" \
  -H "Authorization: Bearer $HYBRIDS3_UPLOADS_KEY"

# delete
curl -X DELETE http://localhost:4000/storage/uploads/image.png \
  -H "Authorization: Bearer $HYBRIDS3_UPLOADS_KEY"
```

### Presigned URLs

Generate a time-limited URL that anyone can download without auth credentials:

```bash
# generate (default 1 hour, max 7 days)
curl -X POST "http://localhost:4000/storage/presign/uploads/report.pdf?expires=86400" \
  -H "Authorization: Bearer $HYBRIDS3_UPLOADS_KEY"

# response for public bucket — plain URL (no expiry needed since bucket is public-read anyway)
{"url": "http://localhost:4000/storage/uploads/report.pdf", "expires": null}

# download via presigned URL — no auth header
curl "http://localhost:4000/storage/uploads/report.pdf"
```

### Nested paths

Object keys support `/` for directory-like organization:

```bash
curl -X PUT "http://localhost:4000/storage/uploads/projects/myapp/build.tar.gz" \
  -H "Authorization: Bearer $HYBRIDS3_UPLOADS_KEY" \
  --data-binary @build.tar.gz

# list only that project's files
curl "http://localhost:4000/storage/uploads?prefix=projects/myapp/" \
  -H "Authorization: Bearer $HYBRIDS3_UPLOADS_KEY"
```

### boto3

```python
import boto3
from botocore.config import Config

s3 = boto3.client(
    "s3",
    endpoint_url="http://localhost:4000/storage",
    aws_access_key_id="uploads",              # bucket name (acts as public_key)
    aws_secret_access_key=HYBRIDS3_UPLOADS_KEY,
    region_name="us-east-1",
    config=Config(signature_version="s3v4"),
)

s3.upload_file("image.png", "uploads", "images/photo.png")
obj = s3.get_object(Bucket="uploads", Key="images/photo.png")
data = obj["Body"].read()

s3.list_objects_v2(Bucket="uploads", Prefix="images/")
s3.delete_object(Bucket="uploads", Key="images/photo.png")

# generate presigned URL
url = s3.generate_presigned_url(
    "get_object",
    Params={"Bucket": "uploads", "Key": "images/photo.png"},
    ExpiresIn=3600,
)
```

Configure TTL and size limits in `.env`:

```env
HYBRIDS3_UPLOADS_TTL=168h        # auto-delete after N time (default 7 days)
HYBRIDS3_UPLOADS_MAX_SIZE=100MB  # per-file size limit
```

---

## Claudebox — Agentic Tasks

[Claudebox](https://github.com/psyb0t/docker-claudebox) wraps Claude Code in a Docker container and exposes it as an API. Each request runs Claude Code's full agentic loop — it can read/write files, run shell commands, install packages, browse the web, and use tools, all within an isolated workspace.

Two instances: one using your OAuth token or Anthropic API key (`claudebox-*` models), one connected to z.ai for GLM models (`claudebox-glm-*` models). Both have identical APIs and workspace capabilities.

### Via LiteLLM chat completions

The simplest way — just use claudebox models in the standard chat API:

```bash
curl http://localhost:4000/chat/completions \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "claudebox-sonnet",
    "messages": [{"role": "user", "content": "list all Python files in this workspace"}],
    "extra_headers": {"X-Claude-Workspace": "myproject"}
  }'
```

### Via direct API

More control: structured output formats, session resumption, fire-and-forget, tool call history.

```bash
# basic run
curl -X POST http://localhost:4000/claudebox/run \
  -H "Authorization: Bearer $CLAUDEBOX_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"prompt": "write a Go HTTP server", "workspace": "go-project"}'

# with structured JSON output
curl -X POST http://localhost:4000/claudebox/run \
  -H "Authorization: Bearer $CLAUDEBOX_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "prompt": "extract the name and version from package.json",
    "workspace": "myproject",
    "jsonSchema": "{\"type\":\"object\",\"properties\":{\"name\":{\"type\":\"string\"},\"version\":{\"type\":\"string\"}},\"required\":[\"name\",\"version\"]}"
  }'

# with full tool call history
curl -X POST http://localhost:4000/claudebox/run \
  -H "Authorization: Bearer $CLAUDEBOX_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"prompt": "build the project and run tests", "workspace": "myapp", "outputFormat": "json-verbose"}'

# check which workspaces are busy
curl http://localhost:4000/claudebox/status \
  -H "Authorization: Bearer $CLAUDEBOX_API_TOKEN"

# cancel a running task
curl -X POST "http://localhost:4000/claudebox/run/cancel?workspace=myapp" \
  -H "Authorization: Bearer $CLAUDEBOX_API_TOKEN"
```

### File operations

```bash
# upload a file to a workspace
curl -X PUT http://localhost:4000/claudebox/files/myproject/data.csv \
  -H "Authorization: Bearer $CLAUDEBOX_API_TOKEN" \
  --data-binary @data.csv

# list files in a workspace
curl http://localhost:4000/claudebox/files/myproject \
  -H "Authorization: Bearer $CLAUDEBOX_API_TOKEN"

# download a file from a workspace
curl http://localhost:4000/claudebox/files/myproject/results.json \
  -H "Authorization: Bearer $CLAUDEBOX_API_TOKEN" \
  -o results.json

# delete a file
curl -X DELETE http://localhost:4000/claudebox/files/myproject/old.log \
  -H "Authorization: Bearer $CLAUDEBOX_API_TOKEN"
```

### File + task workflow

```bash
# 1. upload input data
curl -X PUT http://localhost:4000/claudebox/files/analysis/sales.csv \
  -H "Authorization: Bearer $CLAUDEBOX_API_TOKEN" \
  --data-binary @sales.csv

# 2. run analysis (Claude reads the file, writes a report)
curl -X POST http://localhost:4000/claudebox/run \
  -H "Authorization: Bearer $CLAUDEBOX_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"prompt": "analyze sales.csv, compute monthly totals and trends, write a report to report.md", "workspace": "analysis"}'

# 3. download the report
curl http://localhost:4000/claudebox/files/analysis/report.md \
  -H "Authorization: Bearer $CLAUDEBOX_API_TOKEN"
```

### Always-active skills

Drop a `SKILL.md` file into a named subdirectory under `.data/claudebox/config/.always-skills/` — it will be injected into the system prompt of every Claude invocation automatically. No restarts needed. Applies to API, MCP, chat, everything.

```
.data/claudebox/config/.always-skills/
└── coding-rules/
    └── SKILL.md   ← injected into every session
```

Example `SKILL.md`:

```markdown
When writing Go code, always use slog for structured logging, never fmt.Println.
When writing Python, always use pathlib for file paths, never os.path.
Always write tests alongside implementations.
```

Skills stack — every `SKILL.md` found is appended in alphabetical order by directory name. Per-request `appendSystemPrompt` or `X-Claude-Append-System-Prompt` is appended after always-skills, so per-request instructions take precedence.

---

## Image Generation

```bash
# image generation
curl http://localhost:4000/images/generations \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{"model": "hf-flux-schnell", "prompt": "cyberpunk city at night"}'
```

---

## Vision

Upload an image to storage (public URL), then pass it to a vision model:

```bash
# upload the image
curl -X PUT http://localhost:4000/storage/uploads/photo.jpg \
  -H "Authorization: Bearer $HYBRIDS3_UPLOADS_KEY" \
  -H "Content-Type: image/jpeg" \
  --data-binary @photo.jpg

# public URL — no auth needed to read from uploads bucket
# http://localhost:4000/storage/uploads/photo.jpg

# ask a vision model
curl http://localhost:4000/chat/completions \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "groq-llama-4-scout",
    "messages": [{
      "role": "user",
      "content": [
        {"type": "text", "text": "what is in this image?"},
        {"type": "image_url", "image_url": {"url": "http://YOUR_HOST:4000/storage/uploads/photo.jpg"}}
      ]
    }]
  }'
```

Vision-capable models: `groq-llama-4-scout`, `hf-llama-4-scout`, `hf-qwen-vl-72b`, `hf-qwen3-vl-8b`, `hf-gemma-3-12b`, `mistral-small`, `anthropic-claude-opus-4`, `anthropic-claude-sonnet-4`, `anthropic-claude-haiku-4`, `openai-gpt-4o`, `openai-gpt-4o-mini`, `claudebox-opus`, `claudebox-sonnet`, `claudebox-haiku`, `ollama-cpu-gemma3-4b`, `ollama-cuda-gemma3-4b`, `ollama-cuda-gemma3-12b`.

---

## Transcription

```bash
curl http://localhost:4000/audio/transcriptions \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -F "model=groq-whisper-large-v3" \
  -F "file=@audio.mp3"
```

Transcription models: `groq-whisper-large-v3-turbo`, `groq-whisper-large-v3`, `voxtral-small`, `openai-whisper`, `local-speaches-whisper-distil-large-v3`, `local-speaches-parakeet-tdt-0.6b`, `local-speaches-cuda-whisper-distil-large-v3` (CUDA), `local-speaches-cuda-parakeet-tdt-0.6b` (CUDA).

---

## Text-to-Speech

```bash
# CPU — Kokoro (multiple voices)
curl http://localhost:4000/audio/speech \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{"model": "local-speaches-kokoro-tts", "input": "Hello world", "voice": "af_heart"}' \
  -o speech.mp3

# CUDA — Qwen3-TTS (voice cloning)
curl http://localhost:4000/audio/speech \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{"model": "local-qwen3-cuda-tts", "input": "Hello world", "voice": "alloy"}' \
  -o speech.mp3
```

TTS models: `local-speaches-kokoro-tts` (CPU, many voices), `local-qwen3-cuda-tts` (CUDA, voices: alloy/echo/fable), `openai-tts-1`, `openai-tts-1-hd`.
