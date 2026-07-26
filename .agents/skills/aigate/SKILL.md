---
name: aigate
description: Self-hosted AI platform — one `docker-compose up`, one OpenAI-compatible endpoint at http://localhost:4000. Bundles inference (Groq/Cerebras/OpenRouter/HuggingFace/Mistral/Cohere/Ollama/vLLM/llama.cpp/claudebox/pibox-zai/Anthropic/OpenAI), MCP tool use, a stealth browser cluster, image generation (FLUX/DALL-E/SD), speech synthesis (Kokoro/Qwen3-TTS/OpenAI TTS), transcription (Whisper/Parakeet), S3-compatible object storage, agentic code execution (Claude Code + pi-coding-agent + sandboxed piston), web search (SearXNG), an email gateway (mailbox), a Telegram client (Telethon), time-series forecasting + tabular ML (predictalot), audio/video production (audiolla/flickies), an async job queue (proxq), and a web UI (LibreChat) — all reachable through one bearer token and automatic per-model fallback routing. Use when the user wants a one-command self-hosted OpenAI-compatible stack that aggregates many providers/tools behind a single endpoint instead of wiring each service up individually.
homepage: https://github.com/psyb0t/aigate
user-invocable: true
permissions:
  network:
    - outbound HTTP to the aigate endpoint (default http://localhost:4000, or wherever it's deployed)
    - aigate itself reaches out to model providers, MCP tool backends, and the open internet on the user's behalf (web search, browser automation, email, Telegram)
  shell:
    - docker / docker compose (bring the stack up/down, read logs)
    - curl (call the OpenAI-compatible endpoint and direct service routes)
metadata:
  openclaw:
    emoji: "🚪"
    primaryEnv: AIGATE_TOKEN
    requires:
      bins:
        - docker
        - curl
---

# aigate — self-hosted AI platform behind one endpoint

A self-hosted AI platform. One `docker-compose up` stands up inference, tool use, browser automation, image generation, speech synthesis, transcription, object storage, agentic code execution, web search, an email gateway, a Telegram client, time-series forecasting, an async job queue, and a web UI — all behind a single OpenAI-compatible endpoint at `http://localhost:4000`. Point any existing OpenAI-client library or `curl` at it and it works. Everything else is opt-in via `.env` flags; the always-on core is nginx, LiteLLM, PostgreSQL, Redis, and the `proxq` async job queue (at `/q/`, no flag needed).

## Security & safety

**This is a very high-capability, very high-blast-radius stack. Treat the endpoint and its token like root on the host.** A single `AIGATE_TOKEN` bearer can, depending on what's enabled:

- Hold API keys/credentials for many cloud model providers (Groq, Cerebras, OpenRouter, HuggingFace, Mistral, Cohere, Anthropic, OpenAI) plus flat-rate agent backends (Claude Code OAuth/API key, z.ai).
- Execute arbitrary code — two full agentic coding agents (claudebox, pibox-zai) with shell + file access, plus sandboxed multi-language execution (piston).
- Drive a real browser (stealth Camoufox cluster) that can log into sites, fill forms, and act as the user across the open web.
- Send email and Telegram messages on the user's behalf (mailbox, Telethon) — mailbox additionally holds plaintext IMAP/SMTP credentials in its YAML config.
- Read/write S3-compatible object storage with a public-read bucket.

**No per-tool scoping by default.** `AIGATE_TOKEN` is a single all-or-nothing capability grant — every per-service token (`CLAUDEBOX_API_TOKEN`, `PIBOX_ZAI_API_TOKEN`, `PREDICTALOT_AUTH_TOKEN`, `AUDIOLLA_AUTH_TOKEN`, `FLICKIES_AUTH_TOKEN`, `STEALTHY_AUTO_BROWSE_AUTH_TOKEN`, `HYBRIDS3_MASTER_KEY`, `MCP_TOOLS_AUTH_TOKEN`, `TELETHON_AUTH_KEY`, etc.) defaults to it unless the operator explicitly overrides each one separately. Handing an agent the token is not "give it chat access" — it's granting code execution, browser automation, and messaging in one shot, with no way to grant a narrower subset unless the operator has pre-split the per-service tokens. An agent must only be given `AIGATE_TOKEN` when it is fully trusted and only for the specific action the user explicitly requested — never pass it to an agent "just in case it needs something."

Treat aigate as a **trusted host only**. Concretely:
- Never expose port `4000` directly to the public internet. Use Cloudflare Tunnel (`CLOUDFLARED=1`) or Tailscale (`TAILSCALE=1`) — both keep no ports open on the host — or put a real authenticating gateway/reverse-proxy in front of it.
- Every request needs `Authorization: Bearer $AIGATE_TOKEN` (or a per-service override token) — there is no unauthenticated path once a service is enabled. Don't hardcode the token in scripts committed to a repo; source it from `.env`/environment.
- Internal services (Postgres, Redis, LiteLLM, and most optional services) bind to no host ports at all — only nginx is exposed. Don't add host port mappings for internal services unless you specifically need direct access and understand you're widening the blast radius.
- `piston` runs `privileged: true` (required for nsjail's own isolation, not a bypass of it) and lives on an internal-only network with no outbound internet — don't change that without understanding why.
- Guard `.env` and any mailbox/Telethon config files — they hold plaintext secrets and are gitignored for a reason.

## When to use

- The user wants a single self-hosted endpoint that speaks the OpenAI API and routes across many providers with automatic fallback (free-tier cloud → flat-rate → pay-per-token → local).
- The user wants bundled AI tooling (browser automation, image/speech/transcription, code execution, storage, search, email, Telegram, forecasting) reachable via MCP tools or REST without standing up each service by hand.
- The user wants to run models fully locally (CPU or NVIDIA GPU) with no external calls, or mix local + cloud with automatic fallback between them.
- The user needs a chat web UI (LibreChat) pre-wired to every enabled model and tool.

## When NOT to use

- The user only needs one specific provider's API directly — aigate is overhead if the goal is just "call OpenAI" with no routing/tooling/fallback need.
- Untrusted/multi-tenant exposure without a real auth gateway in front — aigate's bearer-token model is not a substitute for per-user authz.
- The user needs Windows-native or non-Docker deployment — this stack is Docker Compose only.

## Quick start

```bash
git clone https://github.com/psyb0t/aigate
cd aigate
cp .env.example .env
# edit .env: set AIGATE_TOKEN, flip the flags for the providers/services you want to 1
make limits    # writes .env.limits sized to this machine's RAM/CPU
make run-bg    # start the stack in the background
```

Gateway is at `http://localhost:4000`. Call it like any OpenAI-compatible endpoint:

```bash
curl http://localhost:4000/chat/completions \
  -H "Authorization: Bearer $AIGATE_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"model": "local-ollama-cpu-llama3.2-3b", "messages": [{"role": "user", "content": "hello"}]}'
```

`model` selects the provider/route; LiteLLM handles fallback automatically if the requested one rate-limits or fails. See `references/setup.md` for the full env/routing story.

## What's bundled and how to reach it

Everything below sits behind the same `http://localhost:4000` endpoint and the same `AIGATE_TOKEN` bearer — aigate's job is exposing them, not reimplementing them. Enable each with its `.env` flag; disabled services are excluded from routing/fallback entirely.

- **Inference + routing** — `/chat/completions`, `/embeddings`, `/images/generations`, `/audio/*` (OpenAI-compatible, via LiteLLM). Model name picks the provider: free-tier cloud (Groq, Cerebras, OpenRouter, HuggingFace, Mistral, Cohere), flat-rate agents (claudebox = Claude Code, pibox-zai = pi-coding-agent/z.ai), pay-per-token (Anthropic, OpenAI), or fully local CPU/CUDA (Ollama, vLLM, llama.cpp, talkies, sd.cpp). Fallback chains retry the next provider automatically on 429/5xx.
- **MCP tool use** — any function-calling model can autonomously invoke `generate_image`, `generate_tts`, `search_web`, `execute_code`, and per-service MCP tools (browser, storage, mailbox, Telethon, predictalot, audiolla, flickies, claudebox/pibox-zai agent tools). Auto-enabled with the underlying service.
- **Browser automation** — `stealthy-auto-browse`, 5-replica stealth Camoufox cluster behind HAProxy. REST + MCP (`BROWSER=1`).
- **Agentic code execution** — claudebox (Claude Code) and pibox-zai (pi-coding-agent/z.ai) for full shell+file agentic tasks; piston at `/piston/` for sandboxed nsjail-isolated one-shot code execution (`CLAUDEBOX=1`, `PIBOX_ZAI=1`, `PISTON=1`).
- **Object storage** — `hybrids3` at `/storage/`, S3-compatible, plain HTTP + boto3, public-read uploads, presigned URLs (`HYBRIDS3=1`).
- **Image generation** — cloud (FLUX, DALL-E, SD) and local CPU/CUDA (`SDCPP=1` / `SDCPP_CUDA=1`) via `/images/generations` or MCP.
- **Speech synthesis + transcription** — `talkies` unifies both under `/audio/speech` and `/audio/transcriptions` (Kokoro, Qwen3-TTS, Whisper, Parakeet, Canary — `TALKIES=1` / `TALKIES_CUDA=1`); cloud TTS/ASR routes through the same endpoints.
- **Web search** — SearXNG at `/searxng/`, plus MCP `search_web` (`SEARXNG=1`).
- **Email gateway** — `mailbox` at `/mailbox/`, stateless IMAP+SMTP across N accounts from one YAML config, REST + MCP (`MAILBOX=1`, needs `MAILBOX_CONFIG` + `MAILBOX_AUTH_TOKEN`).
- **Telegram client** — `telethon` at `/telethon/`, REST + MCP (`TELETHON=1`, needs API ID/hash + string session).
- **Time-series forecasting + tabular ML** — `predictalot` at `/predictalot/` (CPU) and `/predictalot-cuda/` (GPU), REST + MCP (`PREDICTALOT=1` / `PREDICTALOT_CUDA=1`).
- **Audio production** — `audiolla` at `/audiolla/` / `/audiolla-cuda/` — stem separation, mastering, MIDI, text-to-audio, REST + MCP (`AUDIOLLA=1` / `AUDIOLLA_CUDA=1`).
- **Video toolkit** — `flickies` at `/flickies/` / `/flickies-cuda/` — lipsync, face restore, ffmpeg ops, REST + MCP (`FLICKIES=1` / `FLICKIES_CUDA=1`).
- **Async job queue** — `proxq` at `/q/` — queue any OpenAI-path request, poll `/q/__jobs/{id}`, avoids client-side timeouts on long inference.

## Web UI

LibreChat at `/librechat/` (`LIBRECHAT=1`) — pre-configured with every enabled model and MCP tool, conversation history, file uploads, WebSocket streaming. Email/password auth; the first registered user becomes admin (then set `LIBRECHAT_ALLOW_REGISTRATION=false`). Admin UI for LiteLLM itself is at `/ui/`, optionally behind nginx basic auth (`LITELLM_UI_BASIC_AUTH`).

## Setup details

For docker-compose bring-up, required env/keys, ports, and model/routing config, see `references/setup.md`.
