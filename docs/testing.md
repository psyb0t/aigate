# Testing

The test suite validates every service end-to-end against the running stack. The stack must be up before running tests.

```bash
# Run all tests
make test
# or
bash test.sh

# Run specific tests
bash test.sh test_health_endpoints test_mcp_tools_loaded

# List all available tests
bash test.sh --help
```

## What's Tested

- **Health** — all service health endpoints, docker compose service status, browser replica count, cloudflared tunnel reachability (skipped if not running)
- **LiteLLM** — API endpoints, model registration (base models always, plus optional Ollama/CUDA/talkies models when enabled), authentication (valid/invalid/missing keys), chat completions, SSE streaming
- **Nginx** — routing to all backends, root path blocked (404), admin UI basic auth (no creds → 401, bad creds → 401, correct creds → 200, no-auth mode → 200), admin rate limiting (503/429 under rapid fire)
- **MCP** — all tools loaded across servers, per-server tool counts, specific tool presence, authentication
- **MCP Media** — image generation tool (via mcp_tools-generate_image), TTS tool (via mcp_tools-generate_tts), tool presence based on enabled providers, invalid model error handling, tool descriptions contain expected model names, sdcpp-cuda image generation through MCP, e2e LLM tool calling (qwen3-8b → tool_call → MCP generate_image → sdcpp-cuda → upload → LLM responds with link)
- **sd.cpp** _(SDCPP=1)_ — wrapper health, model listing, status fields, load/unload/double-load/double-unload, auto-load on generate, image generation, model swap (sd-turbo ↔ sdxl-turbo), cleanup unload. Both CPU and CUDA variants.
- **talkies** _(TALKIES=1 / TALKIES_CUDA=1)_ — `/healthz` reachability, `/v1/models` spot-checks presence of the core ASR slugs (CPU: `whisper-large-v3`, `whisper-large-v3-turbo`, `canary-180m-flash`; CUDA adds `parakeet-tdt-0.6b-v3`, `canary-1b-flash`, `canary-qwen-2.5b`) — see [talkies.md](services/talkies.md) for the full 11-model CPU / 20-model CUDA catalog, `/api/ps` returns the loaded list, `DELETE /api/ps/{model_id}` accepts URL-encoded slugs (404 on never-loaded model_ids), `POST /unload` returns 200, and end-to-end transcription + TTS through the LiteLLM proxy (asserts non-empty `text` field, MP3 body for `/v1/audio/speech`). The e2e transcription test is gated on the presence of `tests/.fixtures/audio.{wav,mp3,m4a,flac,ogg}` (skipped if missing — ffmpeg-decoded inside the service so any format works).
- **predictalot** _(PREDICTALOT=1 / PREDICTALOT_CUDA=1)_ — per-type model listings (`/v1/timeseries/univariate/models`, `/v1/timeseries/multivariate/models` — verifies non-members are excluded), bearer auth enforcement, univariate forecast via chronos-2, univariate ensemble (`forecast/ensemble`), unknown-model 404, non-member-of-type rejection (timesfm-2.5 on `/v1/timeseries/multivariate/forecast`), and the 26-tool MCP surface (`predictalot-forecast_univariate_chronos_2`, `predictalot-list_univariate_models`, etc.). FM paths use the new `/v1/timeseries/` prefix from upstream v1.0.0; the tabular ML surface added in v1.0.0 is REST-only upstream and not yet exercised by the smoke suite.
- **mailbox** _(MAILBOX=1)_ — open `/health`, auth enforcement on non-health endpoints, `/mailboxes` returns at least one configured account, MCP tool surface. Optional e2e (gated on `MAILBOX_TEST_MAILBOX_NAME` + `MAILBOX_TEST_ADDRESS`): send → poll IMAP → read → delete → verify gone.
- **telethon** _(TELETHON=1)_ — `get_me` returns own profile (verifies the string session is authorized), MCP tool surface
- **HybridS3** — full CRUD lifecycle (upload, download, list, delete, verify deletion), public read without auth, write rejection without auth, presigned URL generation and download
- **Browser** — page navigation, interactive element detection, screenshot capture, full automation flow (navigate, find elements, click, type, screenshot)
- **Claudebox** — chat completion via LiteLLM, direct API access via nginx, file operations (upload, download, list, delete), z.ai instance reachability, OpenAI-compatible models endpoint (both instances)
- **Integration** — end-to-end workflow: browser navigation → screenshot → upload to storage → verify public URL → LLM summarization
- **Security** — auth on every endpoint, cross-token isolation, MCP fake token and session hijack, nginx path normalization bypass, HTTP request smuggling (CL.TE/TE.CL), h2c smuggling, hop-by-hop header abuse, SSRF via browser and MCP to internal services, prompt injection key extraction, path traversal on claudebox and hybrids3, S3 presign abuse, stored XSS headers, model name injection, header injection, large payload rejection, docker socket removal verification, Docker Engine API isolation, internal port exposure, health endpoint info leakage

## Token Usage

Tests are designed for zero or minimal token consumption:

- **LiteLLM model list** — no tokens, just API metadata
- **MCP tool list** — no tokens, just tool registration check
- **Claudebox** — hits `/status` and `/openai/v1/models` directly (no inference), plus one minimal chat completion with `claudebox-haiku` to verify the OAuth token is valid
- **Browser, storage, nginx** — pure HTTP, no LLM calls
- **Integration test** — one model call with a short prompt; this is the only test that burns real tokens

To skip the integration test: `bash test.sh` and exclude `test_integration_*` from the run.
