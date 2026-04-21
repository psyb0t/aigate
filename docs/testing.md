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
- **LiteLLM** — API endpoints, model registration (base models always, plus optional Ollama/CUDA/Speaches models when enabled), authentication (valid/invalid/missing keys), chat completions, SSE streaming
- **Nginx** — routing to all 5 backends, root path blocked (404), admin UI basic auth (no creds → 401, bad creds → 401, correct creds → 200, no-auth mode → 200), admin rate limiting (503/429 under rapid fire)
- **MCP** — all 18 tools loaded across 4 servers, per-server tool counts, specific tool presence, authentication
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
