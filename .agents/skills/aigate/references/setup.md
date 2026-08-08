# aigate setup

Accurate to the aigate `README.md` / `docker-compose.yml` / `.env.example` at time of writing. Re-check those files if this drifts.

## Bring-up

```bash
git clone https://github.com/psyb0t/aigate
cd aigate
cp .env.example .env
# edit .env — see "Required env" below, then flip service flags to 1
make limits      # writes .env.limits sized to this machine's RAM/swap/CPU
make run-bg      # start detached
# or: make run   # start in foreground with logs
```

`make run` / `make run-bg` regenerate `litellm/config.yaml` from fragments (only enabled providers + filtered fallback chains) and pre-flight-validate any file-path env vars (e.g. `MAILBOX_CONFIG`, `CLOUDFLARED_CONFIG`) actually exist before starting containers.

Other Makefile targets: `make down`, `make restart`, `make logs`, `make build-config` (regenerate litellm config only), `make test` (stack must already be running).

## Ports

Single exposed port: **`4000`** (nginx), hardcoded — not env-configurable. Everything else (Postgres, Redis, LiteLLM, and most optional services) binds to no host port at all; they're reached only through nginx's path-based routing on `:4000`. Do not add host port mappings for internal services unless you specifically need direct access.

- Gateway (OpenAI-compatible): `http://localhost:4000`
- LiteLLM admin UI: `http://localhost:4000/ui/`
- LibreChat (if `LIBRECHAT=1`): `http://localhost:4000/librechat/`
- SearXNG (if `SEARXNG=1`): `http://localhost:4000/searxng/`
- Async queue (proxq): `http://localhost:4000/q/`
- Direct-routed services (not via LiteLLM): `/predictalot/`, `/predictalot-cuda/`, `/audiolla/`, `/audiolla-cuda/`, `/flickies/`, `/flickies-cuda/`, `/mailbox/`, `/telethon/`, `/piston/`, `/storage/` (hybrids3), `/claudebox/`, `/pibox-zai/`, `/stealthy-auto-browse/`

## Required env / keys

Core, always needed regardless of which optional services you enable:

| Variable | Purpose |
| --- | --- |
| `AIGATE_TOKEN` | Master bearer token. Every per-service token below defaults to this value when left unset — one token authenticates against LiteLLM, claudebox, pibox-zai, predictalot, mcp_tools, stealthy-auto-browse, hybrids3, telethon, audiolla, flickies, talkies, talkies-cuda. Override a specific `*_AUTH_TOKEN` / `*_API_TOKEN` var to scope that service separately. |
| `LITELLM_MASTER_KEY` | Optional override; defaults to `AIGATE_TOKEN` when unset. |
| `POSTGRES_DB` / `POSTGRES_USER` / `POSTGRES_PASSWORD` / `DATABASE_URL` | LiteLLM's key/usage/budget store. |
| `REDIS_PASSWORD` | LiteLLM response cache + rate limiting + proxq job queue (DB 1). |
| `LITELLM_UI_BASIC_AUTH` | `user:pass` for nginx basic auth in front of `/ui/`. Leave empty to disable (LiteLLM's own login still applies). |
| `LITELLM_USERNAME` / `LITELLM_PASSWORD` | LiteLLM's own admin UI login. |

All requests carry `Authorization: Bearer $AIGATE_TOKEN` (or the relevant per-service override):

```bash
curl http://localhost:4000/chat/completions \
  -H "Authorization: Bearer $AIGATE_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"model": "local-ollama-cpu-llama3.2-3b", "messages": [{"role": "user", "content": "hello"}]}'
```

Per-service keys/tokens only matter once you flip that service's flag to `1`. Every variable is documented inline in `.env.example` — read the comment above each block before enabling. Notable ones:

- Cloud providers: `GROQ=1`, `CEREBRAS=1`, `OPENROUTER=1`, `HUGGINGFACE=1`, `MISTRAL=1`, `COHERE=1`, `ANTHROPIC=1`, `OPENAI=1` each need their own API key var alongside the flag (e.g. `OPENAI_API_KEY`).
- `CLAUDEBOX=1` needs Claude OAuth token or Anthropic API key; token defaults to `AIGATE_TOKEN` via `CLAUDEBOX_API_TOKEN`.
- `PIBOX_ZAI=1` needs a z.ai key; token defaults via `PIBOX_ZAI_API_TOKEN`.
- `MAILBOX=1` needs `MAILBOX_CONFIG` pointing at an existing host YAML file (copy `mailbox/config.example.yaml`, fill IMAP/SMTP creds, put a token under `auth.tokens:`) and `MAILBOX_AUTH_TOKEN` mirroring that token.
- `TELETHON=1` needs `TELETHON_API_ID`, `TELETHON_API_HASH`, `TELETHON_SESSION` (generate the string session once via the telethon-plus `login` command — see `docs/services/telethon.md` upstream).
- `CLOUDFLARED=1` / `TAILSCALE=1` are the two supported ways to expose the gateway beyond localhost without opening host ports — prefer these over publishing `4000` directly.
- CUDA variants of any service (`*_CUDA=1`) require `nvidia-container-toolkit` on the host.

## Model routing

LiteLLM regenerates its config on every `make run`/`make run-bg`, including only enabled providers. Fallback chains (`litellm/config/fallbacks.json`) are priority-ordered and filtered to what's actually enabled:

1. Free cloud (Groq, Cerebras, OpenRouter, HuggingFace, Mistral, Cohere) — rate-limited/capped, not unlimited.
2. Flat-rate (claudebox, pibox-zai) — costs the subscription, no extra per-call charge.
3. Pay-per-token (Anthropic, OpenAI) — real money per token.
4. Local (Ollama, talkies, sd.cpp, vLLM, llama.cpp) — no external limits, bounded only by local hardware.

Model names encode the route, e.g. `groq-gpt-oss-120b`, `local-ollama-cpu-llama3.2-3b`, `local-sdcpp-cuda-sd-turbo`. On a rate-limit or failure, LiteLLM automatically retries the next model in that model's fallback chain; the response's `model` field reports who actually served it. Async/long-running calls can go through `/q/` (proxq) instead of the sync path — submit, get a job ID back immediately, poll `/q/__jobs/{id}`.

Resource contention on local CUDA/CPU services (LLM vs image-gen vs TTS/STT all fighting for the same GPU) is handled automatically by a LiteLLM callback (`resource_manager.py`) — one job per hardware class at a time, idle models auto-unload, competing services get told to free VRAM/RAM before a request proceeds. No manual model management needed.

## Data / persistence

All persistent state lives under `.data/` (bind mounts), overridable via `DATA_DIR` or per-service `DATA_DIR_*`. Contents are gitignored; the directory tree itself is tracked via `.gitkeep`.
