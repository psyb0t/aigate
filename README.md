# aigate

[![CI](https://github.com/psyb0t/aigate/actions/workflows/pipeline.yml/badge.svg?branch=main)](https://github.com/psyb0t/aigate/actions/workflows/pipeline.yml)
[![version](https://raw.githubusercontent.com/psyb0t/aigate/badges/version.svg)](https://github.com/psyb0t/aigate/releases)
[![license](https://raw.githubusercontent.com/psyb0t/aigate/badges/license.svg)](LICENSE)

A self-hosted AI platform. One `docker-compose up`.

Everything an AI-powered workflow needs — inference, tool use, browser automation, image generation, speech synthesis, transcription, object storage, agentic code execution, web search, an email gateway, a Telegram client, time-series forecasting, an async job queue, and a web UI — behind a single OpenAI-compatible endpoint at `http://localhost:4000`. Point any existing client at it and it works.

### Models and routing

Models across multiple providers. Six providers offer free tiers (Groq, Cerebras, OpenRouter, HuggingFace, Mistral, Cohere) — **but "free" means rate-limited and capped**, not unlimited. See [free-tier reality check](docs/providers.md#free-tier-reality-check) for exact RPM/RPD/monthly caps before relying on a tier. Local providers run on your own hardware — CPU or NVIDIA GPU — with no network calls, no rate limits, and no usage costs (Ollama, talkies for ASR+TTS, vllm-wrap for text LLMs+embeddings, llamacpp-wrap for vision-VLMs incl. Surya OCR 2, stable-diffusion.cpp CPU, stable-diffusion.cpp CUDA, audiolla for audio production, predictalot for time-series forecasting). The gateway burns through providers in priority order and falls back automatically when one rate-limits or fails, so you're never paying for tokens you could have gotten free.

### Tools and capabilities

MCP tools across multiple servers. Any model with function calling can invoke them autonomously — the model orchestrates, you just prompt.

- **Stealth browser cluster** — 5 Camoufox replicas behind HAProxy, real OS-level mouse and keyboard input, zero CDP exposure. Passes Cloudflare, CreepJS, BrowserScan, and every other bot detector we've thrown at it.
- **Two agentic coding agents** — full shell access, persistent workspaces, file I/O, tool use. Claude Code (your subscription or API key) and pi-coding-agent pointed at z.ai for GLM models. Both expose REST API, OpenAI-compatible endpoint, and MCP server.
- **Sandboxed code execution** — piston at `/piston/`. Multi-language code execution in nsjail-isolated sandboxes (own user namespace, chroot, seccomp, cgroups, no network). Default install: Python + Node. Add Bash / Deno / Go / Rust / TypeScript / 40+ other languages via `PISTON_LANGUAGES` + rebuild. REST API + `execute_code` MCP tool any function-calling LLM can call to compute deterministic results (hashes, parses, transforms) instead of guessing.
- **Object storage** — S3-compatible, public-read uploads, presigned URLs, auto-expiry. Plain HTTP and boto3.
- **Image generation** — FLUX, DALL-E, Stable Diffusion (cloud + local CPU/CUDA via stable-diffusion.cpp) via MCP tools that return persistent URLs, not base64 blobs. Local CPU: sd-turbo, sdxl-turbo. Local CUDA adds: sdxl-lightning, flux-schnell, juggernaut-xi.
- **Text-to-speech** — Kokoro (CPU + CUDA-ONNX, English+Chinese, voice presets), Qwen3-TTS (CUDA, voice cloning + voice-design + emotion control via the `instructions` field), OpenAI TTS.
- **Transcription** — Whisper (cloud + local CPU/CUDA), Parakeet (~3400× real-time on CPU).
- **Web search** — SearXNG self-hosted meta-search (Google, Bing, DuckDuckGo, Wikipedia) via MCP `search_web` tool.
- **Telegram client** — Telethon at `/telethon/`. Send/read/edit/delete messages, list dialogs, forward, send files from URL, manage group membership. REST API + MCP tools.
- **Email gateway** — mailbox at `/mailbox/`. Stateless IMAP+SMTP across N accounts from one YAML config — unified inbox, per-account list/search/CRUD, SMTP send. REST API + flat MCP tool set (`mailbox` parameter selects account).
- **Time-series forecasting + tabular ML** — predictalot at `/predictalot/`. Five foundation forecasters (chronos-2, timesfm-2.5, moirai-2, toto-1, sundial-base-128m) across six forecast types (univariate, multivariate, past/future covariates, samples) with per-type weighted ensembles at `/v1/timeseries/<type>/…` + a sibling `/v1/tabular/*` family in v1.0.0 — 9 supervised backends (lightgbm, xgboost, hist-gbt, random-forest, logistic, mlp, svm-rbf, knn, naive-bayes) and 3 meta-learners (calibrated / stacking / diversified). REST API for both families + 26 MCP tools (foundation models only — tabular is REST-only). CPU or CUDA.
- **Audio production** — audiolla at `/audiolla/`. Stem separation (Demucs / UVR), restoration (UVR de-reverb / de-echo / de-noise), mastering (matchering / pedalboard chains + curated presets like `master-for-spotify`, `podcast-cleanup`, `vocal-cleanup`), MIR analysis (BPM / key / LUFS / beats / onsets / melody / chords / segments), DSP transforms (sox + ffmpeg), loudness normalization, speech enhancement (DeepFilterNet), VAD (silero), diarization (pyannote), CLAP embeddings + zero-shot classification, AudioSet tagging (AST), audio→MIDI (basic-pitch), MIDI compose / inspect / transform / render via fluidsynth, **text-to-audio generation** (stable-audio-open / musicgen / riffusion / audioldm2 — CUDA only), ad-hoc op-chain pipelines, async jobs + webhooks. REST API + MCP tools. **v1.0+ contract:** JSON body on every audio endpoint, raw bytes only at `PUT /v1/files/{path}`, `output_path` xor `output_url` mandatory for any audio-producing call.
- **Video toolkit** — flickies at `/flickies/`. **Lipsync** via LatentSync 1.5 (ByteDance, Apache-2.0, ~8 GB VRAM, default on CUDA) and Wav2Lip / Wav2Lip-GAN (LRS2 non-commercial, gated). **Face restore** via GFPGAN v1.4. **ffmpeg ops** — trim, concat, transcode (incl. gif + fps + codec change), scale, mux audio, extract audio, thumbnail grid. **ffprobe info**. Async jobs + webhooks. REST API + 11 MCP tools. Same JSON-body + `output_path` xor `output_url` contract as audiolla. GFPGAN + LatentSync 1.5 are CUDA-only; CPU image runs ffmpeg ops + slow Wav2Lip-CPU.

Ask a Groq model to research something and it opens a browser, reads pages, screenshots them, uploads to storage, and comes back with a summary and links. The model decides what tools to use and in what order.

### Web UI

LibreChat at `/librechat/` — pre-configured with all models and MCP tools, conversation history, file uploads, WebSocket streaming. Email/password auth, first user becomes admin.

### Infrastructure

Multiple containers. Nginx reverse proxy with per-endpoint rate limiting. PostgreSQL + MongoDB for persistence. Two Redis instances (cache + browser session sync). Async job queue for long-running inference. Cloudflare Tunnel for public exposure with zero open ports.

### Security

Network-isolated by default — internal services have no host ports. Every endpoint requires auth. Application containers carry `no-new-privileges:true` (genuine carve-outs: piston needs `privileged:true` for nsjail; tailscale needs `NET_ADMIN` for the userspace tun device). File path pre-flight validation on startup.

### Everything is opt-in

Enable what you want in `.env`, ignore what you don't. The core stack (nginx, LiteLLM, PostgreSQL, Redis, proxq) is always on. Every provider, local model, MCP server, and extra service is a flag flip away.

`make run-bg`. That's the whole install.

## Architecture

```
client
  ▼
cloudflared (CLOUDFLARED=1) │ tailscale (TAILSCALE=1, tailnet-only)
  ▼
nginx :4000                                          ┌──────────── always on ────────────┐
  ├─► /claudebox/            → claudebox             │ nginx, LiteLLM, PostgreSQL, Redis │
  ├─► /pibox-zai/            → pibox-zai             │ proxq — everything else is opt-in │
  ├─► /stealthy-auto-browse/ → HAProxy → [browser ×5]└───────────────────────────────────┘
  ├─► /storage/              → hybrids3
  ├─► /q/                    → proxq → LiteLLM (async, returns job ID)
  ├─► /librechat/            → LibreChat (web UI, LIBRECHAT=1)
  ├─► /searxng/              → SearXNG (meta-search, SEARXNG=1)
  ├─► /telethon/             → Telethon (Telegram client, TELETHON=1)
  ├─► /predictalot/          → predictalot (time-series forecasting, CPU, PREDICTALOT=1)
  ├─► /predictalot-cuda/     → predictalot (time-series forecasting, NVIDIA GPU, PREDICTALOT_CUDA=1)
  ├─► /audiolla/             → audiolla (audio-production REST + MCP, CPU, AUDIOLLA=1)
  ├─► /audiolla-cuda/        → audiolla (audio-production REST + MCP, NVIDIA GPU, AUDIOLLA_CUDA=1)
  ├─► /flickies/             → flickies (video toolkit REST + MCP, CPU, FLICKIES=1)
  ├─► /flickies-cuda/        → flickies (video toolkit REST + MCP, NVIDIA GPU, FLICKIES_CUDA=1)
  ├─► /mailbox/              → mailbox (IMAP+SMTP gateway, MAILBOX=1)
  ├─► /piston/               → piston (sandboxed multi-language code execution, PISTON=1)
  └─► /                      → LiteLLM (sync)
                                  ├─ Groq               (free: 30 RPM, 1K-14.4K RPD per model, GROQ=1)
                                  ├─ Cerebras           (free: 5 RPM / 30K TPM / 1M TPD, 4 models only, CEREBRAS=1)
                                  ├─ OpenRouter         (free: 50 RPD $0 / 1K RPD with $10+, OPENROUTER=1)
                                  ├─ HuggingFace        (free: $0.10/mo credits — eval only, HUGGINGFACE=1)
                                  ├─ Mistral            (free "Experiment" tier — exact limits not published, MISTRAL=1)
                                  ├─ Cohere             (trial: 1K calls/MONTH — runs out fast, COHERE=1)
                                  ├─ Ollama CPU         (local, OLLAMA=1)
                                  ├─ Ollama CUDA        (local, NVIDIA, OLLAMA_CUDA=1)
                                  ├─ Talkies CPU        (local, unified ASR + Kokoro TTS, TALKIES=1)
                                  ├─ Talkies CUDA       (local, NVIDIA, full ASR + Kokoro + Qwen3-TTS voice cloning, TALKIES_CUDA=1)
                                  ├─ sd.cpp CPU         (local, image gen, SDCPP=1)
                                  ├─ sd.cpp CUDA        (local, image gen, SDCPP_CUDA=1)
                                  ├─ vLLM CPU           (local, text LLM + embeddings, VLLM=1)
                                  ├─ vLLM CUDA          (local, NVIDIA, text LLM + embeddings, VLLM_CUDA=1)
                                  ├─ llama.cpp CPU      (local, GGUF + vision-VLM incl. Surya OCR 2, LLAMACPP=1)
                                  ├─ llama.cpp CUDA     (local, NVIDIA, GGUF + vision-VLM incl. Surya OCR 2, LLAMACPP_CUDA=1)
                                  ├─ claudebox          (flat-rate, CLAUDEBOX=1)
                                  ├─ pibox-zai          (flat-rate, PIBOX_ZAI=1)
                                  ├─ Anthropic          (pay-per-token, ANTHROPIC=1)
                                  └─ OpenAI             (pay-per-token, OPENAI=1)

MCP servers (all optional):
  ├─ stealthy_auto_browse  — run_script: multi-step browser automation (BROWSER=1)
  ├─ hybrids3              — file upload, download, list, delete, presign (HYBRIDS3=1)
  ├─ claudebox             — agentic Claude Code via OAuth or API key (CLAUDEBOX=1)
  ├─ pibox_zai             — agentic pi-coding-agent via z.ai/GLM (PIBOX_ZAI=1)
  ├─ mcp_tools             — generate_image + generate_tts + search_web + execute_code (auto-enabled with image/TTS/SearXNG/piston)
  ├─ telethon              — Telegram send/read/edit messages, dialogs, files, group management (TELETHON=1)
  ├─ predictalot           — time-series forecasting via 5 foundation models × 6 type-routed endpoints + per-type ensemble (PREDICTALOT=1 and/or PREDICTALOT_CUDA=1)
  ├─ audiolla              — audio-production: stem separation, restoration, mastering, MIR, DSP, loudness, speech enhancement, diarization, MIDI compose + render, workflow presets + ad-hoc pipelines (AUDIOLLA=1 / AUDIOLLA_CUDA=1)
  ├─ flickies              — video toolkit: lipsync (LatentSync 1.5 + Wav2Lip), face restore (GFPGAN), ffmpeg ops — trim/concat/transcode/scale/mux_audio/extract_audio/thumbnail_grid (FLICKIES=1 / FLICKIES_CUDA=1)
  ├─ mailbox               — IMAP+SMTP gateway: inbox, list/search/send across N accounts (MAILBOX=1)
  └─ piston (via mcp_tools) — execute_code: sandboxed multi-language code execution via nsjail (PISTON=1 — hosted by the mcp_tools aggregator, not a standalone MCP server)
```

All persistent data lives under `.data/` by default (bind mounts). Override the base with `DATA_DIR` or per-service with `DATA_DIR_*` env vars (e.g. `DATA_DIR_OLLAMA=/mnt/nas/ollama`) — see [`.env.example`](.env.example) for the full list. The default directory structure is tracked in git via `.gitkeep` files so the right directories exist on a fresh clone — contents are gitignored.

Default writable locations:

| Path                                         | Used by                      | Notes                                                                                      |
| -------------------------------------------- | ---------------------------- | ------------------------------------------------------------------------------------------ |
| `.data/claudebox/config/.always-skills/`     | claudebox                    | Drop `<name>/SKILL.md` files here — injected into every Claude session automatically       |
| `.data/claudebox/workspace/`                 | claudebox                    | Persistent task workspaces                                                                 |
| `.data/pibox-zai/config/`                    | pibox-zai                    | pi config dir (`telegram.yml`, cron history, etc.)                                         |
| `.data/pibox-zai/workspace/`                 | pibox-zai                    | Persistent workspace root (subdirs per task)                                               |
| `.data/hybrids3/`                            | hybrids3                     | Object storage data                                                                        |
| `.data/nginx/`                               | nginx-auth-init              | Generated htpasswd (from `LITELLM_UI_BASIC_AUTH`)                                          |
| `.data/ollama/`                              | ollama, ollama-cuda          | Downloaded model weights (shared — CPU and CUDA instances read the same blobs)             |
| `.data/talkies/`                             | talkies, talkies-cuda        | HuggingFace cache for all talkies models (Whisper × 3, Parakeet, Canary × 3, Kokoro). Shared between CPU and CUDA; CPU image loads a subset, CUDA loads the full set. |
| `.data/talkies-voices/`                      | talkies-cuda                 | User-supplied Qwen3-TTS reference voices — drop `<name>.wav` (10-30s clean speech) and use as `voice=<name>` on `/v1/audio/speech` (nested paths supported) |
| `.data/sdcpp/models/`                        | sdcpp, sdcpp-cuda            | Downloaded stable-diffusion model weights (shared between CPU and CUDA)                    |
| `.data/librechat/`                           | librechat, librechat-mongodb | Conversation data (MongoDB), file uploads                                                  |
| `.data/cloudflared/`                         | cloudflared                  | Tunnel config and credentials (if using named tunnel)                                      |
| `.data/tailscale/`                           | tailscale                    | Tailscale node state (machine key, DERP info) — auto-created on first run                  |
| `.data/predictalot/models/`                  | predictalot, predictalot-cuda | Downloaded HuggingFace snapshots for the 5 forecasters (~1.4GB total)                     |
| `.data/audiolla/`                            | audiolla, audiolla-cuda      | Demucs weights (~6GB) + UVR models + torch hub + staged files (bind-mounted as `/data`; CPU and CUDA variants share the same cache) |
| `.data/flickies/`                            | flickies, flickies-cuda      | Model weights (~6GB total: S3FD + Wav2Lip ×2 + GFPGAN v1.4 + LatentSync 1.5) + staged file uploads (bind-mounted as `/data`; CPU and CUDA variants share the same cache) |
| `.data/vllm/models/<org>/<repo>/`            | vllm, vllm-cuda, vllm-pull   | Flat HF-repo layout (no blobs/snapshots dedup) — `vllm-pull` populates via `huggingface-cli download --local-dir`. Shared by CPU and CUDA wrappers and by any other service that mounts the same dir. Default: Nomic embed v2 + Qwen3-0.6B. |
| `.data/mailbox/`                             | mailbox                      | Recommended host path for the mailbox YAML config (`config.yaml` — gitignored, holds plaintext IMAP/SMTP creds) |

## Services

| Service                                                                                                        | Description                                                                                                                                                                                                                                                                                                                                                                   |
| -------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Nginx**                                                                                                      | Single entry point on port 4000. Routes by URL path, enforces per-endpoint rate limits (configurable via `RATELIMIT_*` env vars), configurable proxy timeouts (`TIMEOUT_*`), restores real client IP behind Cloudflare, and optionally adds HTTP basic auth on the admin UI. All config is embedded inline.                                                                   |
| **LiteLLM**                                                                                                    | OpenAI-compatible API proxy. Latency-based routing, Redis response caching (10-minute TTL), automatic retries, per-model fallback chains, and client-side JSON schema validation. Manages API keys and usage via PostgreSQL.                                                                                                                                                  |
| **[proxq](https://github.com/psyb0t/docker-proxq)**                                                            | Async HTTP job queue proxy. Sits in front of LiteLLM at `/q/` — queues inference requests in Redis, returns a job ID instantly, forwards to upstream in the background. Poll `/__jobs/{id}` for status, `/__jobs/{id}/content` for the raw response. Only OpenAI API paths are queued (chat/completions, embeddings, audio, images); everything else passes through directly. |
| **PostgreSQL**                                                                                                 | Key management, budget tracking, usage analytics for LiteLLM.                                                                                                                                                                                                                                                                                                                 |
| **Redis**                                                                                                      | LiteLLM response cache and rate limiting. Also used by proxq (DB 1) for job queue storage.                                                                                                                                                                                                                                                                                    |
| **[claudebox](https://github.com/psyb0t/docker-claudebox)** _(optional, `CLAUDEBOX=1`)_ | Claude Code CLI in API mode. Full agentic loop — shell access, file I/O, tool use, persistent workspaces. Uses your OAuth token (Pro/Max/Team subscription) or Anthropic API key. Exposes REST API, OpenAI-compatible endpoint, and MCP server.                                                                                                 |
| **[pibox](https://github.com/psyb0t/docker-pibox)** _(optional, `PIBOX_ZAI=1`)_ | [pi-coding-agent](https://github.com/earendil-works/pi-mono) in API mode, pointed at z.ai for GLM models. Speaks the Anthropic wire protocol — same agentic capabilities (shell, files, tools) as claudebox. REST API, OpenAI-compatible endpoint, `/files/*` CRUD, MCP server. The `-zai` suffix is the z.ai backend; future variants (e.g. `PIBOX_OPENAI`, `PIBOX_OR`) can run alongside. |
| **[hybrids3](https://github.com/psyb0t/docker-hybrids3)** _(optional, `HYBRIDS3=1`)_                           | S3-compatible object storage. Plain HTTP upload/download, boto3-compatible, bearer token auth, auto-expiry, MCP server. The `uploads` bucket is public-read — files are accessible by direct URL without signing.                                                                                                                                                             |
| **[stealthy-auto-browse](https://github.com/psyb0t/docker-stealthy-auto-browse)** _(optional, `BROWSER=1`)_    | 5 Camoufox (hardened Firefox) replicas behind HAProxy. Real OS-level mouse and keyboard input via PyAutoGUI — no CDP exposure. Passes Cloudflare, CreepJS, BrowserScan, Pixelscan. Redis cookie sync across replicas. REST API and MCP server.                                                                                                                                |
| **Ollama** _(optional, `OLLAMA=1`)_                                                                            | Local CPU inference. Runs llama3.2:3b, qwen3:4b, smollm2:1.7b, qwen2.5-coder:1.5b, qwen2.5-coder:3b, phi4-mini, gemma4:e2b, gemma3:4b (vision), nuextract-v1.5 (structured extraction), bge-m3, qwen3-embedding:0.6b (embeddings), dolphin-phi. Models are downloaded automatically on first start and cached in `.data/ollama/`. No GPU required.                            |
| **Ollama CUDA** _(optional, `OLLAMA_CUDA=1`)_                                                                  | Local NVIDIA GPU inference. Runs all CPU models on GPU plus: qwen3:8b, qwen3:30b-a3b (MoE generalist), qwen2.5vl:7b (vision-language), gemma4:e4b, qwen2.5-coder:7b, deepseek-coder-v2:16b, llama3.1:8b, qwen3-abliterated:16b, gemma4-abliterated:e4b (uncensored vision), deepseek-r1:8b, deepseek-r1:14b (R1-Distill-Qwen-14B), phi4-reasoning:plus (math/reasoning specialist). Flash attention and KV cache enabled. Shares model storage with CPU ollama — no duplicate downloads. Requires `nvidia-container-toolkit`.         |
| **[talkies](https://github.com/psyb0t/docker-talkies)** _(optional, `TALKIES=1`)_                              | Unified OpenAI-compatible speech service via `psyb0t/talkies:v0.9.0`. One container, both endpoints: `/v1/audio/transcriptions` and `/v1/audio/speech`. CPU image ships **6 models** — `whisper-large-v3`, `whisper-large-v3-turbo`, `canary-180m-flash`, `nemotron-3.5-asr-0.6b` (NVIDIA Nemotron-3.5-ASR-Streaming via parakeet.cpp, 40+ locales, per-word timestamps) for ASR, plus `kokoro-82m` (PyTorch) and `kokoro-82m-nvidia` (ONNXRuntime, same voices, no PyTorch on the hot path) for TTS. Stereo channel-split diarization (`diarization=true`), VAD-chunked long audio, idle-unload TTL. Weights cached in `.data/talkies/`. |
| **[talkies CUDA](https://github.com/psyb0t/docker-talkies)** _(optional, `TALKIES_CUDA=1`)_                    | CUDA-accelerated talkies (`psyb0t/talkies:v0.9.0-cuda`). **14 models** — adds `parakeet-tdt-0.6b-v3`, `canary-1b-flash` (EN/DE/FR/ES + EN↔X translation), `canary-qwen-2.5b` (hybrid SALM), and the full Qwen3-TTS line on top of the CPU set: `qwen3-tts-0.6b` (Base 0.6B), `qwen3-tts-1.7b` (Base 1.7B), `qwen3-tts-0.6b-custom` / `qwen3-tts-1.7b-custom` (CustomVoice — 9 preset speakers, 1.7B also takes emotion via `instructions`), `qwen3-tts-1.7b-design` (VoiceDesign — NL voice description via `instructions`). Drop reference `.wav` files into `${DATA_DIR_TALKIES}/custom-voices/` for Base-mode voice cloning. Kokoro TTS still runs on CPU even inside the CUDA image (fast enough that it doesn't need a GPU). Shares `.data/talkies/`. Requires `nvidia-container-toolkit`. |
| **sd.cpp CPU** _(optional, `SDCPP=1`)_                                                                         | Local CPU image generation via [stable-diffusion.cpp](https://github.com/leejet/stable-diffusion.cpp). Go wrapper with OpenAI-compatible `/v1/images/generations` endpoint, model hot-swap, idle timeout auto-unload. Models: sd-turbo, sdxl-turbo. Models cached in `.data/sdcpp/models/`.                                                                                   |
| **sd.cpp CUDA** _(optional, `SDCPP_CUDA=1`)_                                                                   | CUDA-accelerated image generation via stable-diffusion.cpp. Same wrapper as CPU with CUDA backend. Models: sd-turbo, sdxl-turbo, sdxl-lightning, flux-schnell, juggernaut-xi. Non-blocking — rejects concurrent requests with 503 instead of queuing (resource manager handles scheduling). Requires `nvidia-container-toolkit`.                                              |
| **vllm CPU** _(optional, `VLLM=1`)_                                                                            | Supervised wrapper around `vllm serve` on top of `vllm/vllm-openai-cpu`. Same surface as the CUDA variant — OpenAI-compatible `/v1/chat/completions`, `/v1/completions`, `/v1/embeddings`, idle-unload after `VLLM_MODEL_TTL`. Ships Nomic Embed v2 + Qwen3-0.6B; edit `vllm/models.cpu.json` to add more. Slower than llama.cpp (what ollama uses) for small models — included mostly for symmetry with the CUDA variant. Participates in the LiteLLM resource_manager `cpu-vllm` group. |
| **vllm CUDA** _(optional, `VLLM_CUDA=1`)_                                                                      | Supervised wrapper around `vllm serve` (FastAPI on top of `vllm/vllm-openai`). Holds at most one model in VRAM; lazy-loads on first request, idle-unloads after `VLLM_CUDA_MODEL_TTL` (default 10m). OpenAI-compatible `/v1/chat/completions`, `/v1/completions`, and `/v1/embeddings`. Ships Nomic Embed v2 (MoE 305M, embeddings) and Qwen3-0.6B (chat). `vllm-pull` downloads weights via `huggingface-cli download --local-dir` into a flat HF-repo layout (`models/<org>/<repo>/<files>`) shared with the CPU variant and any other service mounting the same dir. Edit `vllm/models.cuda.json` to add more. Participates in the LiteLLM resource_manager so it evicts (and gets evicted by) ollama-cuda / sdcpp-cuda / talkies-cuda under VRAM contention. Requires `nvidia-container-toolkit`. |
| **llamacpp CPU** _(optional, `LLAMACPP=1`)_                                                                    | Supervised wrapper around `llama-server` from llama.cpp on top of `ghcr.io/ggml-org/llama.cpp:server`. Same lifecycle surface as vllm-wrap (`/v1/chat/completions` proxy, `/api/ps`, `DELETE /api/ps/{model_id}`, idle-unload, `POST /unload`) but serves GGUF weights and supports **vision VLMs via mmproj** — vllm-CPU's vision support is weak, llama.cpp's isn't. Ships **Surya OCR 2** (`datalab-to/surya-ocr-2-gguf`, ~650M Qwen3-VL-style document model — OCR, layout detection, table recognition via **4 trained-in prompts**; see [docs/services/llamacpp.md](docs/services/llamacpp.md) for the exact prompt strings). Edit `llamacpp/models.cpu.json` to add more GGUFs. The wrapper transparently fetches `http(s)://` URLs in `image_url.url` and rewrites them to data URLs (`llama-server`'s `mtmd` only accepts data URLs natively). Sidecar `llamacpp-pull` populates weights via `huggingface-cli download --local-dir` reading both `models.cpu.json` + `models.cuda.json`. Participates in the LiteLLM resource_manager `cpu-llamacpp` group. **Performance reality:** small images (captchas, single-line crops) ~24 s; A4 pages @ 96 DPI ~2-3 min per page. Suitable for batch / overnight document work; use CUDA for interactive A4. |
| **llamacpp CUDA** _(optional, `LLAMACPP_CUDA=1`)_                                                              | Same wrapper as the CPU variant but on top of `ghcr.io/ggml-org/llama.cpp:server-cuda` with `--n-gpu-layers 999`. Strongly preferred for vision-VLM work — Surya OCR 2 on a single A4 page @ 96 DPI is **~6-12 s on CUDA vs ~2-3 min on CPU**. Captcha-sized crops are ~3 s. **Server-side PDF input** — Surya handler detects PDF in `image_url.url` (data URL or http URL), rasterizes per page via poppler-utils, loops the chat completion per page, and stitches with `<div data-page="N">` tags (full-page OCR) or `"page": N` JSON fields (layout / table-rec). Per-request `dpi_rescale_to` knob (default 96 cap, `-1` for native, hard cap 600). Shares `${DATA_DIR_LLAMACPP}/models/` with the CPU variant so enabling both doesn't duplicate downloads. Participates in the LiteLLM resource_manager `cuda-llamacpp` group, so it evicts (and is evicted by) ollama-cuda / sdcpp-cuda / talkies-cuda / vllm-cuda under VRAM contention. Requires `nvidia-container-toolkit`. |
| **[piston](https://github.com/engineer-man/piston)** _(optional, `PISTON=1`)_                                  | Sandboxed multi-language code execution. Default install: **Python + Node** only. Add Bash / Deno / Go / Rust / TypeScript / 40+ other languages via `PISTON_LANGUAGES` (upstream pkgs index — heads up most non-Python/Node entries are stuck at 2021-2023 versions). Languages are **pre-baked at image build time**, not pulled at runtime — so the container lives on `aigate-internal` ONLY with no outbound network (a popped neighbour container in `aigate-public` can't reach `piston:2000` to spawn arbitrary code). Adding a new language = bump `PISTON_LANGUAGES`, `make build`, redeploy. nsjail-based isolation per execution — own user namespace, chroot, seccomp filter, cgroups for CPU+memory+wall-clock+process-count caps. `PISTON_DISABLE_NETWORKING=true` by default so sandboxed code has no outbound network even within the container. REST API at `/piston/api/v2/*` behind nginx bearer auth (client `Authorization` is stripped before the proxy hop so `AIGATE_TOKEN` never reaches piston) + an `execute_code` MCP tool any function-calling LLM can call. Container runs `privileged: true` — that's what nsjail needs to set up isolation primitives, not what isolates the code (which lives in the nsjail subprocess inside). |
| **MCP tools** _(auto-enabled)_                                                                                 | Media generation and web search MCP server. Exposes `generate_image`, `generate_tts`, and `search_web` tools to any model with function calling. Discovers available models dynamically from LiteLLM. Returns structured JSON with persistent URLs (uploaded to HybridS3) — no base64 blobs. Auto-enabled when any image, TTS, or SearXNG provider is active.                 |
| **[LibreChat](https://github.com/danny-avila/LibreChat)** _(optional, `LIBRECHAT=1`)_                          | Web UI for LLM interaction at `/librechat/`. Pre-configured with all LiteLLM models and MCP tools. MongoDB-backed conversation storage. Email/password auth — first registered user becomes admin, then set `LIBRECHAT_ALLOW_REGISTRATION=false` and restart. WebSocket streaming. Configurable via `.env` (registration, rate limits, debug logging, JWT secrets).           |
| **[SearXNG](https://github.com/searxng/searxng)** _(optional, `SEARXNG=1`)_                                    | Self-hosted meta-search engine at `/searxng/`. Aggregates Google, Bing, DuckDuckGo, Wikipedia. No API key needed — runs entirely locally. Also powers the MCP `search_web` tool so any function-calling model can search the web autonomously. Protected by nginx admin auth.                                                                                                 |
| **[Telethon Plus](https://github.com/psyb0t/docker-telethon-plus)** _(optional, `TELETHON=1`)_                 | Telegram client at `/telethon/`. REST API and MCP server — send/read/edit/delete messages, list dialogs, forward messages, send files from URL, manage group membership. Requires a Telegram API ID/hash and a string session (see [my.telegram.org/apps](https://my.telegram.org/apps)). Bearer token auth.                                                                  |
| **[predictalot](https://github.com/psyb0t/docker-predictalot)** _(optional, `PREDICTALOT=1` and/or `PREDICTALOT_CUDA=1`)_ | Foundation time-series forecasting **and** supervised tabular ML over caller-engineered features. Bumped to **v1.0.1** in aigate v3.12.0 — **breaking from v0.2.x:** FM endpoints moved from `/v1/<type>/…` to `/v1/timeseries/<type>/…` (no redirect compatibility upstream); MCP tool names unchanged. Tabular surface at `/v1/tabular/*` is REST-only — 9 backends (lightgbm, xgboost, hist-gbt, random-forest, logistic, mlp, svm-rbf, knn, naive-bayes) × 3 modes (direction, value, quantile) + 3 meta-learners (calibrated, stacking, diversified). v1.0.1 itself is docs-only over v1.0.0 (upstream restructured the README into `docs/{timeseries,tabular,mcp,configuration,architecture,accuracy,errors}.md`; image bytes effectively identical). REST + MCP. Direct route (not via LiteLLM). FM models lazy-load on first request, auto-unload when idle. CPU and CUDA variants run side-by-side on distinct routes (`/predictalot/` and `/predictalot-cuda/`) and aliases, both sharing `.data/predictalot/models/`. CUDA needs `nvidia-container-toolkit`. Full API in upstream's [`docs/`](https://github.com/psyb0t/docker-predictalot/tree/main/docs). |
| **[audiolla](https://github.com/psyb0t/docker-audiolla)** _(optional, `AUDIOLLA=1` and/or `AUDIOLLA_CUDA=1`)_ | Self-hosted audio-production REST + MCP. Stem separation, restoration, mastering, MIR analysis, DSP transforms, loudness, speech enhancement, diarization, MIDI transcription + composition. **v1.0.1+ adds text-to-audio generation** (stable-audio-open, musicgen-small/medium [CC-BY-NC, gated on `AUDIOLLA_ENABLE_NONCOMMERCIAL=1`], riffusion, audioldm2 — all CUDA-only). Curated YAML workflow presets + ad-hoc op-chain pipelines that run server-side (intermediates stay in memory). **API contract:** JSON body on every audio endpoint; raw bytes only at `PUT /v1/files/{path}`; audio-producing calls require `output_path` (server stages under FILES_DIR — fetch via `GET /v1/files/<path>`) XOR `output_url` (server PUTs to a presigned URL). Async jobs + webhooks. Direct route (not via LiteLLM). Engines lazy-load + auto-unload. CPU and CUDA variants run side-by-side on distinct routes (`/audiolla/` and `/audiolla-cuda/`) and aliases, both sharing `.data/audiolla/`. CUDA needs `nvidia-container-toolkit`. Full API + v0.23→v1.0 migration cheatsheet in the [upstream README](https://github.com/psyb0t/docker-audiolla). |
| **[flickies](https://github.com/psyb0t/docker-flickies)** _(optional, `FLICKIES=1` and/or `FLICKIES_CUDA=1`)_ | Self-hosted video-toolkit REST + MCP. Sibling of audiolla (audio) and talkies (speech) — same JSON-body + `output_path` xor `output_url` contract, same async-job model, same bind-mount-`/data` story. **Lipsync** via `LatentSync 1.5` (ByteDance, Apache-2.0, default on CUDA, ~8 GB VRAM) and `wav2lip` / `wav2lip-gan` (LRS2 non-commercial — gated on `FLICKIES_ENABLE_NONCOMMERCIAL=1`; fast and low-VRAM). **Face restore** via `gfpgan v1.4` (TencentARC, Apache-2.0). **ffmpeg ops** (CPU): trim, concat, transcode (incl. gif + fps + codec change), scale, mux audio, extract audio, thumbnail grid. **ffprobe info**. 11 MCP tools total. Hot-swap eviction with idle unload after `FLICKIES_IDLE_UNLOAD_SECS` (default 600s). Tested ceiling: RTX 3060 12 GB — fits LatentSync 1.5 with headroom; Wav2Lip + GFPGAN chain peaks at ~5 GB. GFPGAN + LatentSync 1.5 are CUDA-only — the CPU image refuses to load them. CPU and CUDA variants run side-by-side on distinct routes (`/flickies/` and `/flickies-cuda/`) and aliases, both sharing `.data/flickies/`. CUDA needs `nvidia-container-toolkit`. Full API + `openapi.yaml` + generated Go / Python clients in the [upstream README](https://github.com/psyb0t/docker-flickies). |
| **[mailbox](https://github.com/psyb0t/docker-mailbox)** _(optional, `MAILBOX=1`)_                               | Stateless IMAP+SMTP gateway at `/mailbox/`. Drives N email accounts from a single YAML config — unified inbox, per-account list/search/CRUD, SMTP send. MCP enabled by default with a flat tool set (`mailbox` parameter selects account). Holds plaintext creds, so `MAILBOX_CONFIG` must point at a gitignored YAML on the host (template at `mailbox/config.example.yaml`). |
| **cloudflared** _(optional, `CLOUDFLARED=1`)_                                                                  | Cloudflare Tunnel. Disabled by default — enable with `CLOUDFLARED=1` in `.env`. Runs a quick tunnel (random `*.trycloudflare.com` URL, no account) or a named tunnel (fixed domain, requires config file and credentials).                                                                                                                                                    |
| **tailscale** _(optional, `TAILSCALE=1`)_                                                                      | Tailscale node running [`tailscale serve`](https://tailscale.com/kb/1242/tailscale-serve). Proxies to nginx on the tailnet only — no public exposure, no port forwarding. Set `TS_AUTHKEY` and `TS_HOSTNAME`, then access aigate at `https://<hostname>.<tailnet>.ts.net` from any tailnet-joined device.                                                                       |

## Security and Exposure

**Network isolation** — internal services live on the private `aigate-internal` Docker network with no host port bindings. PostgreSQL, Redis, and LiteLLM are always internal. Optional services (hybrids3, HAProxy, Ollama, talkies, vllm-wrap, llamacpp-wrap, sdcpp, piston, audiolla, predictalot, etc.) join the same private network when enabled. Services that need to reach the public internet (e.g. cloud LLM providers, HuggingFace model pulls) also join `aigate-public`; the rest are internal-only. Only nginx is exposed.

**Auth on everything** — every service requires a bearer token. LiteLLM needs `LITELLM_MASTER_KEY`. Claudebox instances each have their own token. Hybrids3 uses per-bucket keys. The stealthy browser cluster has an `AUTH_TOKEN` (defaults to `lulz-4-security` if unset). The MCP tools server validates `MCP_TOOLS_AUTH_TOKEN`. LibreChat has its own email/password auth — first registered user becomes admin; set `LIBRECHAT_ALLOW_REGISTRATION=false` in `.env` and restart after creating your account. The admin UI supports HTTP basic auth with rate limiting.

**No new privileges** — application containers carry `security_opt: no-new-privileges:true` by default. Two unavoidable exceptions: **piston** requires `privileged: true` to set up nsjail user namespaces + chroots inside the sandbox (the code-execution isolation lives one level deeper, inside nsjail itself), and **tailscale** requires `NET_ADMIN` for the userspace tun device. Both are documented in their service pages.

**Pre-flight validation** — `make run` and `make run-bg` validate that any file paths set in `.env` (e.g. `CLOUDFLARED_CONFIG`, `CLOUDFLARED_CREDS`) actually exist before starting Docker. If a path is set but missing, the stack refuses to start with a clear error rather than silently creating a broken directory mount.

**Public exposure** — if you want to reach the gateway from outside, use Cloudflare Tunnel instead of opening ports. Set `CLOUDFLARED=1` in `.env` for a quick `*.trycloudflare.com` URL (no account needed), or configure a named tunnel for a fixed custom domain. Traffic goes through Cloudflare's network before it reaches nginx — DDoS protection and TLS termination included.

→ [Cloudflare Tunnel setup](docs/services/cloudflared.md)

**Tailnet-only access** — if you only need access from your own devices and don't want to be on the public internet at all, set `TAILSCALE=1` to run a Tailscale node that proxies to nginx via `tailscale serve`. No port forwarding, no DNS, no certificates to manage — just `https://aigate.<your-tailnet>.ts.net` from any device on your tailnet.

→ [Tailscale setup](docs/services/tailscale.md)

## MCP Tools

Tools across optional servers. Any model that supports function calling can invoke them — the model decides when and how to use them based on the prompt.

→ [Full MCP tool reference with parameters](docs/mcp-tools.md)

## Providers and Models

Models across multiple providers. Six offer free tiers with no credit card required — but every "free" tier has a hard cap (RPM, RPD, monthly tokens, or monthly request count). Read [free-tier reality check](docs/providers.md#free-tier-reality-check) for exact numbers. Five providers run locally on your own hardware — CPU or NVIDIA GPU — with no rate limits. Per-model fallback chains route automatically through alternative providers when one fails or rate-limits.

### Routing philosophy

| Priority    | Tier             | Providers                                                | Reality                                                                                   |
| ----------- | ---------------- | -------------------------------------------------------- | ----------------------------------------------------------------------------------------- |
| 1st         | Free cloud       | Groq, Cerebras, OpenRouter, HuggingFace, Mistral, Cohere | Capped — see [free-tier reality check](docs/providers.md#free-tier-reality-check)         |
| 2nd         | Flat-rate        | claudebox (Max sub), pibox-zai (z.ai)                    | Costs the subscription, no extra per-call                                                 |
| 3rd         | Pay-per-token    | Anthropic, OpenAI                                        | Real money per token — last resort before going local                                     |
| Last resort | Local (CPU/CUDA) | Ollama, talkies (ASR + Kokoro + Qwen3-TTS), sd.cpp       | No external limits — bounded only by your hardware                                        |

### Fallback chains

Every model has a fallback chain defined in `litellm/config/fallbacks.json`. When a provider fails or rate-limits, LiteLLM tries the next one automatically. You request one model — the gateway figures out who can actually serve it.

Example: you request `groq-gpt-oss-120b`. Groq returns 429 (rate limited). LiteLLM silently retries with `cerebras-gpt-oss-120b`. Cerebras is down. It tries `mistral-large`. Mistral responds. You get the response — same format, same schema, no error. The `model` field in the response tells you which provider actually served it.

```
groq-gpt-oss-120b → 429 rate limited
  ↓ fallback
cerebras-gpt-oss-120b → 503 unavailable
  ↓ fallback
mistral-large → 200 ✓
```

For LLM chat models, chains follow the priority tiers: free cloud first, then flat-rate, then pay-per-token, then local. For image, TTS, and STT models, local models are preferred over paid cloud (they're free and have no rate limits). Small models fall back to other small models. Code models fall back to other code models. Local CUDA models fall back to local CPU models.

Chains are filtered at startup — `make run` regenerates the LiteLLM config and strips out any provider you haven't enabled. If you only have `GROQ=1` and `OLLAMA=1`, the chain skips everything in between.

### Local models (Ollama, CPU)

All local CPU models are last in fallback chains — used when cloud providers are rate-limited or unavailable. Ollama unloads models after 5 minutes of inactivity.

| Model name                            | Description                                                    | RAM    |
| ------------------------------------- | -------------------------------------------------------------- | ------ |
| `local-ollama-cpu-llama3.2-3b`        | General chat — smallest/fastest                                | ~2GB   |
| `local-ollama-cpu-qwen3-4b`           | General chat — better quality, thinking mode                   | ~2.6GB |
| `local-ollama-cpu-smollm2-1.7b`       | General chat — absolute tiniest                                | ~1GB   |
| `local-ollama-cpu-qwen2.5-coder-1.5b` | Code — smallest                                                | ~1GB   |
| `local-ollama-cpu-qwen2.5-coder-3b`   | Code — better quality                                          | ~2GB   |
| `local-ollama-cpu-phi4-mini`          | General chat (Microsoft Phi 4, 128K ctx)                       | ~2.5GB |
| `local-ollama-cpu-gemma4-e2b`         | General chat + vision (Google Gemma 4, 2.3B effective)         | ~7.2GB |
| `local-ollama-cpu-gemma3-4b`          | General chat + vision — lightweight (Google Gemma 3)           | ~2.6GB |
| `local-ollama-cpu-dolphin-phi`        | Uncensored assistant (Microsoft Phi)                           | ~1.6GB |
| `local-ollama-cpu-nuextract-v1.5`     | Structured data extraction — unstructured text → JSON          | ~2.3GB |
| `local-ollama-cpu-bge-m3`             | Text embeddings — long docs, multilingual (8192 token context) | ~570MB |
| `local-ollama-cpu-qwen3-embed-0.6b`   | Text embeddings — modern, efficient                            | ~500MB |

### Local models (Ollama CUDA — `OLLAMA_CUDA=1`)

CUDA models run with flash attention and quantized KV cache. See [Resource management](#resource-management) below for how VRAM is shared across services.

| Model name                                 | Description                                                      | VRAM   |
| ------------------------------------------ | ---------------------------------------------------------------- | ------ |
| `local-ollama-cuda-qwen3-8b`               | General chat — thinking mode                                     | ~5GB   |
| `local-ollama-cuda-qwen3-30b-a3b`          | Generalist MoE — 30B total / 3B active, fast on CUDA             | ~17GB  |
| `local-ollama-cuda-llama3.1-8b`            | General chat                                                     | ~5GB   |
| `local-ollama-cuda-gemma4-e2b`             | General chat + vision (Gemma 4, 2.3B effective)                  | ~7.2GB |
| `local-ollama-cuda-gemma4-e4b`             | General chat + vision — higher quality (Gemma 4, 4.5B effective) | ~9.6GB |
| `local-ollama-cuda-qwen2.5vl-7b`           | Vision-language — OCR, screenshots, charts, docs                 | ~5GB   |
| `local-ollama-cuda-qwen2.5-coder-7b`       | Code                                                             | ~5GB   |
| `local-ollama-cuda-deepseek-coder-v2-16b`  | Code — MoE, 2.4B active, 160K ctx                                | ~8.9GB |
| `local-ollama-cuda-deepseek-r1-8b`         | Reasoning / thinking model                                       | ~5.2GB |
| `local-ollama-cuda-deepseek-r1-14b`        | Reasoning — R1-Distill-Qwen-14B, stronger sibling of 8B          | ~9GB   |
| `local-ollama-cuda-phi4-reasoning-plus`    | Math / structured reasoning specialist (Microsoft, 14B + RL)     | ~11GB  |
| `local-ollama-cuda-qwen3-abliterated-16b`  | Uncensored — abliterated Qwen3                                   | ~9.8GB |
| `local-ollama-cuda-gemma4-abliterated-e4b` | Uncensored + vision — abliterated Gemma 4                        | ~9.6GB |
| `local-ollama-cuda-dolphin-phi`            | Uncensored assistant (tiny)                                      | ~1.6GB |
| `local-ollama-cuda-llama3.2-3b`            | General chat (Meta Llama 3.2)                                    | ~2.0GB |
| `local-ollama-cuda-qwen3-4b`               | General chat (Qwen3, thinking mode)                              | ~2.6GB |
| `local-ollama-cuda-smollm2-1.7b`           | Tiny general chat (HuggingFace SmolLM2)                          | ~1.0GB |
| `local-ollama-cuda-qwen2.5-coder-1.5b`     | Code completion (tiny)                                           | ~1.0GB |
| `local-ollama-cuda-qwen2.5-coder-3b`       | Code completion (small)                                          | ~2.0GB |
| `local-ollama-cuda-phi4-mini`              | General chat / reasoning (Microsoft Phi 4)                       | ~2.5GB |
| `local-ollama-cuda-gemma3-4b`              | General chat + vision — lightweight (Google Gemma 3)             | ~2.6GB |
| `local-ollama-cuda-nuextract-v1.5`         | Structured data extraction — unstructured text → JSON            | ~2.3GB |
| `local-ollama-cuda-bge-m3`                 | Text embeddings — long docs, multilingual (8192 ctx)             | ~570MB |
| `local-ollama-cuda-qwen3-embed-0.6b`       | Text embeddings — modern, efficient                              | ~500MB |

### Local transcription + TTS (talkies, CPU — `TALKIES=1`)

| Model name                                      | Description                                                                          |
| ----------------------------------------------- | ------------------------------------------------------------------------------------ |
| `local-talkies-whisper-large-v3`                | faster-whisper large-v3 — multilingual, highest accuracy                             |
| `local-talkies-whisper-large-v3-turbo`          | faster-whisper large-v3-turbo — multilingual, ~8× faster than large-v3               |
| `local-talkies-canary-180m-flash`               | NeMo Canary 180M flash — English-only ASR                                            |
| `local-talkies-kokoro-tts`                      | Kokoro 82M — TTS via `/v1/audio/speech`, ~41 voices across en/es/fr/hi/it/pt         |

### Local transcription + TTS (talkies, CUDA — `TALKIES_CUDA=1`)

Adds the heavier ASR models that need a GPU to be useful. Kokoro TTS still runs on CPU even inside the CUDA image.

| Model name                                      | Description                                                                          |
| ----------------------------------------------- | ------------------------------------------------------------------------------------ |
| `local-talkies-cuda-whisper-large-v3`           | faster-whisper large-v3 — multilingual (CUDA)                                        |
| `local-talkies-cuda-whisper-large-v3-turbo`     | faster-whisper large-v3-turbo — multilingual (CUDA)                                  |
| `local-talkies-cuda-parakeet-tdt-0.6b-v3`       | NeMo Parakeet TDT 0.6B v3 — 25 European languages                                    |
| `local-talkies-cuda-canary-180m-flash`          | NeMo Canary 180M flash — English-only ASR (CUDA)                                     |
| `local-talkies-cuda-canary-1b-flash`            | NeMo Canary 1B flash — EN/DE/FR/ES + EN↔X translation                                |
| `local-talkies-cuda-canary-qwen-2.5b`           | NeMo Canary-Qwen 2.5B SALM — hybrid ASR+LLM (English)                                |
| `local-talkies-cuda-kokoro-tts`                 | Kokoro 82M TTS (runs on CPU inside the CUDA image)                                   |
| `local-talkies-cuda-qwen3-tts`                  | Qwen3-TTS 0.6B (CUDA-only) — voice cloning via reference `.wav` in `${DATA_DIR_TALKIES}/custom-voices/` (`voice=<name>`); samples `alloy`/`echo`/`fable` baked in; 17 languages |

### Local image generation (sd.cpp, CPU — `SDCPP=1`)

| Model name                   | Description                                  |
| ---------------------------- | -------------------------------------------- |
| `local-sdcpp-cpu-sd-turbo`   | SD Turbo — fastest, smallest (~1.7GB)        |
| `local-sdcpp-cpu-sdxl-turbo` | SDXL Turbo — better quality, larger (~2.5GB) |

### Local image generation (sd.cpp, CUDA — `SDCPP_CUDA=1`)

| Model name                        | Description                                                 |
| --------------------------------- | ----------------------------------------------------------- |
| `local-sdcpp-cuda-sd-turbo`       | SD Turbo — fastest on GPU (~1.7GB VRAM)                     |
| `local-sdcpp-cuda-sdxl-turbo`     | SDXL Turbo — better quality (~2.5GB VRAM)                   |
| `local-sdcpp-cuda-sdxl-lightning` | SDXL Lightning — fast, high quality (~2.5GB VRAM)           |
| `local-sdcpp-cuda-flux-schnell`   | FLUX Schnell — best quality, largest (~7GB VRAM)            |
| `local-sdcpp-cuda-juggernaut-xi`  | Juggernaut XI — photorealistic SDXL fine-tune (~5GB VRAM)   |

Models auto-download on first use and cache in `.data/sdcpp/models/`.

### Local text LLM + embeddings (vllm, CPU — `VLLM=1`)

Supervised single-model wrapper around `vllm serve` (CPU). Only one model resident in RAM at a time. Same wrapper and surface as the CUDA variant; just slower. Add more by editing `vllm/models.cpu.json`.

| Model name                          | Description                                                       |
| ----------------------------------- | ----------------------------------------------------------------- |
| `local-vllm-nomic-embed-v2`         | Nomic Embed v2 (MoE, 305M active) — embeddings, 8192 ctx          |
| `local-vllm-qwen3-0.6b`             | Qwen 3 0.6B — chat / completions, 8192 ctx                        |

### Local text LLM + embeddings (vllm-cuda — `VLLM_CUDA=1`)

Supervised single-model wrapper around `vllm serve` (NVIDIA). Only one model resident in VRAM at a time — the wrapper restarts the subprocess when a different model is requested. Add more by editing `vllm/models.cuda.json`. Both variants share the same `${DATA_DIR_VLLM}/models/` weight store.

| Model name                              | Description                                                                |
| --------------------------------------- | -------------------------------------------------------------------------- |
| `local-vllm-cuda-nomic-embed-v2`        | Nomic Embed v2 (MoE, 305M active) — embeddings, 8192 ctx                  |
| `local-vllm-cuda-qwen3-0.6b`            | Qwen 3 0.6B — chat / completions, 16384 ctx                                |

→ [Full provider and model list](docs/providers.md)

### Resource management

Local services share limited hardware — a single GPU can't run an LLM, an image generator, and a TTS model simultaneously. The platform handles this automatically so you never have to think about it.

**Automatic unloading** — every local service unloads idle models after a configurable timeout. Ollama unloads after 5 minutes by default. sd.cpp unloads after 5 minutes (`SDCPP_IDLE_TIMEOUT` / `SDCPP_CUDA_IDLE_TIMEOUT`). Talkies unloads ASR models after `TALKIES_MODEL_TTL` (default 10 min) and Qwen3-TTS unloads on demand. predictalot lazy-loads each forecaster on first call and unloads after `PREDICTALOT_MODEL_IDLE_TIMEOUT` (default `30m`) — only the models you've actually asked for occupy memory. This means VRAM and RAM are only held while a model is actively serving or within its idle window.

**Hardware semaphores** — a LiteLLM callback (`resource_manager.py`) enforces mutual exclusion per hardware. An `asyncio.Semaphore(1)` ensures only one CUDA job runs at a time across all groups (LLM, image gen, TTS, STT). The same applies on CPU. If a CUDA image generation request arrives while a CUDA LLM model is loaded, the request waits for the semaphore, then the resource manager unloads the LLM before the image generation proceeds. This prevents GPU OOM without any manual intervention.

**Competing-group unload** — before each local request, all other groups on the same hardware are told to free resources. For example, a `local-sdcpp-cuda-flux-schnell` request will unload ollama-cuda models, every loaded talkies-cuda model, every loaded audiolla-cuda engine, and every loaded flickies-cuda engine before starting. Each service has its own unload mechanism: Ollama uses `keep_alive: 0`, sd.cpp uses `/sdcpp/v1/unload`, talkies / vllm-cuda / llamacpp-cuda use `DELETE /api/ps/{model}`, audiolla uses `POST /v1/unload` (bulk), flickies uses `DELETE /v1/engines/{slug}` per loaded engine. Audiolla and flickies are not LiteLLM-routed (they expose their own HTTP APIs) but still participate as competing groups so a LatentSync or Demucs session hoarding 7+ GiB VRAM cannot OOM-kill the next LiteLLM-routed call.

**Operator-facing unload** — `POST /v1/unload/cuda` and `POST /v1/unload/cpu` (and `POST /v1/unload` for both classes) fan out the eviction across every service on the given hardware class, for manual VRAM cleanup outside the LiteLLM path. Same bearer as the rest of aigate. See `docs/resource-management.md` for response shape.

**sd.cpp pre-load (image generation only)** — sd.cpp returns 503 `another load or generation in progress` while a model is mid-load (~5-20s for typical SDXL weights). LiteLLM's image-gen path retries internally + walks the fallback chain on 5xx, every retry hits the same lock, every retry 503s, and the whole chain ends with HTTP 200 + EMPTY `data` (router-side bug — image-gen fallback exhaustion masquerades as success). The resource manager pre-empts this by issuing an explicit `POST /sdcpp/v1/load?model=<key>` while it still holds the cuda-img / cpu-img semaphore — blocking until the backend is fully warm. By the time LiteLLM dispatches the actual `/v1/images/generations` call, attempt 1 succeeds. No 503 storm, no fallback amplification, no empty-data response. No-op when the model is already loaded.

**Auto-load on demand** — models load automatically when needed. Send a request to any model and its service loads it on the fly. No pre-loading, no manual model management. The sd.cpp wrapper accepts `/v1/images/generations` requests even when no model is loaded — it starts the sd-server subprocess with the right model automatically.

**Non-blocking rejection** — the sd.cpp wrapper uses `TryLock` instead of blocking. If a generation or model swap is already in progress, new requests get an immediate 503 instead of queuing indefinitely. The resource manager semaphore handles scheduling at a higher level — requests wait at the LiteLLM layer, not inside individual services.

The net effect: you can freely mix LLM chat, image generation, TTS, and STT requests across local services. The platform queues, unloads, loads, and routes automatically. The only constraint is throughput — one local job per hardware at a time.

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

Fill in the values — every variable is documented with comments in [`.env.example`](.env.example).

Everything is opt-in via flags in `.env`. API keys are stored separately and never activate anything on their own — set the flag to `1` to enable:

| Flag              | What it enables                                                                           |
| ----------------- | ----------------------------------------------------------------------------------------- |
| `OPENAI=1`        | OpenAI models (gpt-4o, o3, DALL-E, Whisper, TTS)                                          |
| `ANTHROPIC=1`     | Direct Anthropic API models                                                               |
| `CLAUDEBOX=1`     | claudebox service + models + MCP server (Claude Code via OAuth or API key)                |
| `PIBOX_ZAI=1`     | pibox-zai service + GLM models + MCP server (pi-coding-agent via z.ai)                    |
| `CEREBRAS=1`      | Cerebras models (free: 5 RPM / 30K TPM / 1M TPD, 4 models only — see [limits](docs/providers.md#free-tier-reality-check)) |
| `OPENROUTER=1`    | OpenRouter models (free: 50 RPD at $0, 1K RPD at $10+ credits — see [limits](docs/providers.md#free-tier-reality-check)) |
| `HUGGINGFACE=1`   | HuggingFace models (free: **$0.10/mo credits only**, eval tier — see [limits](docs/providers.md#free-tier-reality-check)) |
| `MISTRAL=1`       | Mistral AI models (free "Experiment" tier — exact limits not published, see your Admin dashboard) |
| `COHERE=1`        | Cohere models (trial: **1K calls/MONTH total cap** — see [limits](docs/providers.md#free-tier-reality-check)) |
| `GROQ=1`          | Groq models (free: 30 RPM, 1K-14.4K RPD per model — see [limits](docs/providers.md#free-tier-reality-check)) |
| `OLLAMA=1`        | Local Ollama CPU inference (~6GB+ RAM)                                                    |
| `OLLAMA_CUDA=1`   | Local Ollama NVIDIA GPU inference (requires `nvidia-container-toolkit`)                   |
| `TALKIES=1`       | Local talkies CPU — unified ASR (whisper + canary-180m) + Kokoro TTS (~4GB RAM)           |
| `TALKIES_CUDA=1`  | Local talkies CUDA — adds parakeet + canary-1b + canary-qwen-2.5b (requires `nvidia-container-toolkit`) |
| `SDCPP=1`         | Local stable-diffusion.cpp CPU image generation                                           |
| `SDCPP_CUDA=1`    | Local stable-diffusion.cpp CUDA image generation (requires `nvidia-container-toolkit`)    |
| `HYBRIDS3=1`      | Object storage service + MCP server (S3-compatible, plain HTTP, auto-expiry)              |
| `BROWSER=1`       | Stealth browser cluster + MCP server (~1.3GB RAM)                                         |
| `LIBRECHAT=1`     | LibreChat web UI at `/librechat/` with all models and MCP tools                           |
| `SEARXNG=1`       | SearXNG meta-search at `/searxng/` + MCP `search_web` tool                                |
| `TELETHON=1`      | Telegram client at `/telethon/` + MCP Telegram tools                                      |
| `CLOUDFLARED=1`   | Cloudflare Tunnel                                                                         |
| `TAILSCALE=1`     | Tailscale node — tailnet-only HTTP proxy to nginx (no public exposure)                    |
| `PREDICTALOT=1`   | predictalot at `/predictalot/` — time-series forecasting + MCP (CPU image)                |
| `PREDICTALOT_CUDA=1` | predictalot CUDA variant (requires `nvidia-container-toolkit`)                         |
| `AUDIOLLA=1`      | audiolla at `/audiolla/` — audio-production REST + MCP (CPU image)                         |
| `AUDIOLLA_CUDA=1` | audiolla CUDA variant — adds text-to-audio generation (requires `nvidia-container-toolkit`) |
| `FLICKIES=1`      | flickies at `/flickies/` — video toolkit (lipsync + face restore + ffmpeg) REST + MCP (CPU image; runs ffmpeg ops + Wav2Lip-CPU) |
| `FLICKIES_CUDA=1` | flickies CUDA variant — adds LatentSync 1.5 + GFPGAN (requires `nvidia-container-toolkit`) |
| `MAILBOX=1`       | mailbox IMAP+SMTP gateway at `/mailbox/` + MCP (needs `MAILBOX_CONFIG` + `MAILBOX_AUTH_TOKEN`) |

`make run` regenerates `litellm/config.yaml` before starting — only enabled providers are included, fallback chains are filtered to match.

If `CLOUDFLARED_CONFIG` or `CLOUDFLARED_CREDS` are set, `make run`/`make run-bg` will verify those files exist before starting. A missing file causes an immediate error — better than Docker silently mounting a directory instead.

### 3. Set resource limits

```bash
make limits
```

Reads your system's RAM, swap, and CPU core count and writes a `.env.limits` file with recommended `mem_limit`, `memswap_limit`, and `cpus` for every service. The Makefile picks this up automatically — no other steps needed.

Allocations are **proportional to your enabled services** — enabling more services means each gets a smaller slice. The script reads your `.env` flags (`CUDA`, `TALKIES`, `OLLAMA`, `BROWSER`, etc.) and only counts active services toward the RAM budget. Re-run it any time you enable or disable a service, move to a different server, or change your hardware.

CUDA services (`ollama-cuda`, `talkies-cuda`, `sdcpp-cuda`) are [resource-manager-aware](#resource-management) — only one has models loaded at a time, so the budget counts the largest plus small idle overhead for the others.

Set `MAXUSE` to cap the entire stack to a percentage of your machine's resources — useful when you're sharing the server with other workloads:

```bash
make limits            # use 100% of system resources (default)
MAXUSE=80 make limits  # cap the whole stack at 80% of RAM, swap, and CPU
```

Swap allocation is proportional: each service gets a swap budget matching its share of total RAM. If your server has abundant swap (e.g. 1TB on 16GB RAM), services can use up to 10× their RAM limit in swap — they'll crawl, but they won't get OOM-killed. Minimum is always 2×.

The `.env.limits` file is gitignored. Each server maintains its own.

### 4. Start

```bash
make run-bg   # detached (background)
make run      # foreground with logs
```

Gateway is at `http://localhost:4000`. Admin UI at `http://localhost:4000/ui/`. LibreChat at `http://localhost:4000/librechat/` (if `LIBRECHAT=1`). SearXNG at `http://localhost:4000/searxng/` (if `SEARXNG=1`).

On first start, Ollama will pull all local models in the background. talkies pre-downloads its enabled ASR + TTS models (whisper, canary, parakeet, nemotron, kokoro, qwen3-tts on CUDA) on boot, and `vllm-pull` / `llamacpp-pull` populate the wrapper model dirs from HuggingFace before their containers start. Everything caches to `.data/` and won't re-download on restart.

## Usage

```bash
# cloud provider (free tier — capped, see docs/providers.md#free-tier-reality-check; auto-fallback on 429)
curl http://localhost:4000/chat/completions \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{"model": "cerebras-gpt-oss-120b", "messages": [{"role": "user", "content": "hello"}]}'

# local model (no network, no rate limits)
curl http://localhost:4000/chat/completions \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{"model": "local-ollama-cpu-llama3.2-3b", "messages": [{"role": "user", "content": "hello"}]}'

# image generation
curl http://localhost:4000/images/generations \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{"model": "hf-flux-schnell", "prompt": "a cat riding a skateboard"}'

# local image generation (CUDA — sd-turbo, fast)
curl http://localhost:4000/images/generations \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{"model": "local-sdcpp-cuda-sd-turbo", "prompt": "a red panda in a forest", "size": "512x512"}'

# transcription (cloud — Groq Whisper, fast)
curl http://localhost:4000/audio/transcriptions \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -F "model=groq-whisper-large-v3" -F "file=@audio.mp3"

# local transcription (talkies — parakeet, English, very fast on CUDA)
curl http://localhost:4000/audio/transcriptions \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -F "model=local-talkies-cuda-parakeet-tdt-0.6b-v3" -F "file=@audio.mp3"

# stereo speaker diarization (left/right channel split)
curl http://localhost:4000/audio/transcriptions \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -F "model=local-talkies-cuda-parakeet-tdt-0.6b-v3" \
  -F "file=@call.wav" \
  -F "diarization=true" \
  -F "response_format=verbose_json"

# text-to-speech (local CPU Kokoro via talkies — many voices)
curl http://localhost:4000/audio/speech \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{"model": "local-talkies-kokoro-tts", "input": "Hello world", "voice": "af_heart"}' \
  -o speech.mp3

# text-to-speech (local CUDA — Qwen3-TTS, voice cloning)
curl http://localhost:4000/audio/speech \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{"model": "local-talkies-cuda-qwen3-tts", "input": "Hello world", "voice": "alloy"}' \
  -o speech.mp3

# text embeddings (local)
curl http://localhost:4000/embeddings \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{"model": "local-ollama-cpu-bge-m3", "input": "your text here"}'

# time-series forecasting (PREDICTALOT=1 / PREDICTALOT_CUDA=1 — direct route, not via LiteLLM)
# v1.0.0: type-routed under /v1/timeseries/<type>/. Pick a type: univariate / multivariate / covariates/{past,future} / covariates / samples
# v1.0.0 also ships a sibling /v1/tabular/* family (9 supervised backends + 3 meta-learners) — REST-only.
curl http://localhost:4000/predictalot/v1/timeseries/univariate/forecast \
  -H "Authorization: Bearer $PREDICTALOT_AUTH_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "chronos-2",
    "context": [[10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20]],
    "config": {"horizon": 5}
  }'

# mailbox — unified inbox across configured accounts (MAILBOX=1, direct route)
curl "http://localhost:4000/mailbox/inbox?limit=5" \
  -H "Authorization: Bearer $MAILBOX_AUTH_TOKEN"

# mailbox — send mail through a configured account
curl -X POST http://localhost:4000/mailbox/mailboxes/work/send \
  -H "Authorization: Bearer $MAILBOX_AUTH_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"to": ["someone@example.com"], "subject": "hello", "body_text": "from aigate"}'

# telethon — send a Telegram message (TELETHON=1, direct route)
curl -X POST http://localhost:4000/telethon/api/messages \
  -H "Authorization: Bearer $TELETHON_AUTH_KEY" \
  -H "Content-Type: application/json" \
  -d '{"chat": "@username", "text": "hello from aigate"}'
```

### Async (via proxq)

Any request sent through `/q/` is queued and processed in the background — useful for long-running inference that would otherwise time out.

```bash
# submit — returns instantly with a job ID
curl http://localhost:4000/q/v1/chat/completions \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{"model": "cerebras-gpt-oss-120b", "messages": [{"role": "user", "content": "write a novel"}]}'
# → 202 {"jobId": "550e8400-e29b-41d4-a716-446655440000"}

# check status
curl http://localhost:4000/q/__jobs/550e8400-e29b-41d4-a716-446655440000 \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY"
# → {"id": "...", "status": "running"}

# get the response (replays upstream response exactly)
curl http://localhost:4000/q/__jobs/550e8400-e29b-41d4-a716-446655440000/content \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY"
# → {"choices": [...], "usage": {...}}

# cancel
curl -X DELETE http://localhost:4000/q/__jobs/550e8400-e29b-41d4-a716-446655440000 \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY"
```

Only OpenAI API paths (`/v1/chat/completions`, `/v1/embeddings`, `/v1/audio/*`, `/v1/images/*`, `/v1/responses`) are queued. Health checks, model lists, key management, and admin UI requests pass through to LiteLLM directly.

Configurable via `.env`:

| Variable                       | Default | What it does                                                  |
| ------------------------------ | ------- | ------------------------------------------------------------- |
| `PROXQ_CONCURRENCY`            | `10`    | How many workers process jobs simultaneously                  |
| `PROXQ_TASK_RETENTION`         | `1h`    | How long completed jobs stay in Redis                         |
| `PROXQ_UPSTREAM_TIMEOUT`       | `10m`   | Max time to wait for LiteLLM to respond                       |
| `PROXQ_MAX_RETRIES`            | `0`     | Retry failed upstream calls (0 = no retries)                  |
| `PROXQ_RETRY_DELAY`            | `30s`   | Delay between retries (0 = exponential backoff)               |
| `PROXQ_MAX_BODY_SIZE`          | `10MB`  | Max request body size for queued requests                     |
| `PROXQ_DIRECT_PROXY_THRESHOLD` | `10MB`  | Bodies larger than this bypass the queue                      |
| `PROXQ_CACHE_MODE`             | `none`  | `none`, `memory` (LRU), or `redis` — cache upstream responses |
| `PROXQ_CACHE_TTL`              | `5m`    | How long cached responses stay fresh                          |
| `PROXQ_CACHE_MAX_ENTRIES`      | `10000` | Max entries for in-memory LRU cache                           |

→ [Per-service usage](docs/services/README.md) — browser automation, object storage, agentic claudebox tasks, vision, streaming, web search, time-series forecasting, email gateway, Telegram client, Python SDK examples

## Services Reference

All endpoints, auth requirements, request/response formats, and config options.

→ [Services index](docs/services/README.md)

## Agent integrations

The [skill](.agents/skills/aigate) works in any agent that reads `.agents/skills/`, and
installs natively in the clients below.

### Claude Code

```bash
claude plugin marketplace add psyb0t/agents
claude plugin install aigate@psyb0t
```

Claude Code prompts for the aigate URL and, if you're using `AIGATE_TOKEN` auth, the
token — the token is stored in your OS keychain.

### Codex

```bash
codex plugin marketplace add psyb0t/agents
codex plugin add aigate@psyb0t
```

Installed via the marketplace, the skill invokes as `$aigate:aigate`. Codex also picks
the skill up automatically with no install in any repo containing `.agents/skills/`,
where it invokes as plain `$aigate`.

### OpenClaw

The skill is published to ClawHub on every release:

```bash
openclaw skills install @psyb0t/aigate
```

## Makefile

```bash
make run           # start stack in foreground (validates file paths, rebuilds litellm config)
make run-bg        # start stack in background (validates file paths, rebuilds litellm config)
make down          # stop everything
make restart       # full restart
make logs          # follow logs
make build-config  # regenerate litellm/config.yaml from fragments (runs automatically on make run)
make limits              # generate .env.limits with recommended resource limits for this machine
MAXUSE=80 make limits    # same but cap the stack at 80% of total RAM/swap/CPU
make test          # run test suite (stack must be running)
```

## Testing

```bash
make test
```

Tests covering health, routing, auth, MCP, MCP media tools, storage CRUD, browser automation, claudebox, proxq async job lifecycle, local TTS/STT round-trips, CUDA audio, resource manager unload verification, local image generation (CPU/CUDA), MCP-to-sdcpp integration, LLM-to-MCP e2e tool calling, and security. Designed for zero/minimal token usage.

→ [Testing guide](docs/testing.md)

## Logs and Debugging

```bash
make logs                           # follow all logs
docker compose logs litellm -f      # follow one service
docker compose logs --since 5m      # last 5 minutes
```

LiteLLM logs every request with the model name, provider, latency, and token usage. When a fallback triggers, you'll see the failed provider and which one took over. The resource manager logs every semaphore acquire/release and every competing-group unload — search for `[resource_manager]` in the logs.

Per-service debug options:

| Variable                                   | Default | What it does                                                                       |
| ------------------------------------------ | ------- | ---------------------------------------------------------------------------------- |
| `SDCPP_VERBOSE` / `SDCPP_CUDA_VERBOSE`     | `false` | sd.cpp wrapper debug logging                                                       |
| `SDCPP_LOG_LEVEL` / `SDCPP_CUDA_LOG_LEVEL` | `info`  | sd.cpp wrapper log level                                                           |
| `LIBRECHAT_DEBUG_LOGGING`                  | `true`  | LibreChat verbose logging                                                          |
| `PREDICTALOT_LOG_LEVEL`                    | `INFO`  | predictalot log level (`DEBUG` for model-load + per-request diagnostics)           |
| `TELETHON_LOG_LEVEL`                       | `INFO`  | Telethon Plus log level                                                            |

Ollama and talkies log to stdout by default — visible in `docker compose logs`. mailbox doesn't expose a log-level env var — its verbosity is set in the YAML config (`MAILBOX_CONFIG`).

## Troubleshooting

**GPU out of memory** — the resource manager should prevent this, but if it happens: check `docker compose logs litellm | grep resource_manager` to verify the semaphore is working. Make sure you're not bypassing LiteLLM by hitting services directly. Run `make limits` to regenerate memory limits.

**Model download stuck** — Ollama pulls models in the background on first start. Large models (8B+) can take a while. Check progress with `docker compose logs ollama -f`. sd.cpp models download via `sdcpp-pull` — check `docker compose logs sdcpp-pull -f`. If a download fails, delete the partial file from `.data/` and restart.

**"Connection refused" or "Bad Gateway"** — the service isn't ready yet. Check `docker compose ps` for unhealthy containers. Check logs for the specific service. Common cause: a dependent service (PostgreSQL, Redis) hasn't started yet — Docker healthchecks handle this, but on slow machines the start period may not be enough.

**Slow local inference** — expected if the resource manager just swapped models. The first request after a swap includes model load time (seconds for Ollama, up to minutes for sd.cpp FLUX on CPU). Subsequent requests are fast until the idle timeout unloads the model. Increase idle timeouts to keep models warm longer.

**Rate limited on every provider** — all free tiers have hard caps. Quick reference: Groq 30 RPM + 1K-14.4K RPD per model, Cerebras **5 RPM / 30K TPM / 1M TPD on 4 models only**, OpenRouter 20 RPM on `:free` + 50 RPD ($0) or 1K RPD ($10+ credits), Mistral free "Experiment" tier (exact numbers not published — check your dashboard), Cohere 20 RPM chat with a **1K calls/month total cap**, HuggingFace **$0.10/mo credits** (eval only). Full table with official limit pages: [free-tier reality check](docs/providers.md#free-tier-reality-check). If you're hitting all of them at once, the fallback chain lands on flat-rate (claudebox), then pay-per-token (Anthropic/OpenAI), then local. Check `docker compose logs litellm | grep fallback` to see the chain in action. Consider enabling more free providers, or going local (`OLLAMA=1` / `OLLAMA_CUDA=1`) for unlimited.

**predictalot first request is slow / times out** — the five forecasters lazy-load on first call. Each downloads ~50-800MB of HuggingFace snapshots into `.data/predictalot/models/` and warms up before responding. `TIMEOUT_PREDICTALOT` defaults to `600s` for exactly this reason. Subsequent calls are fast until `PREDICTALOT_MODEL_IDLE_TIMEOUT` (default 30m) unloads them. Use `PREDICTALOT_PREFETCH` / `PREDICTALOT_PRELOAD` (see [`.env.example`](.env.example)) to download or load models at startup instead of on first request.

**mailbox refuses to start / `MAILBOX_CONFIG` errors** — the stack's pre-flight check requires `MAILBOX_CONFIG` to point at an existing YAML file on the host (`make run` aborts with a clear error otherwise — see `_FILE_VARS` in the Makefile). Copy `mailbox/config.example.yaml` to a gitignored host path (recommended: `.data/mailbox/config.yaml`), fill in your IMAP/SMTP creds, put at least one token in `auth.tokens:`, and mirror it as `MAILBOX_AUTH_TOKEN` in `.env`.

**Telethon "unauthorized" / no profile returned** — Telethon needs all three of `TELETHON_API_ID`, `TELETHON_API_HASH`, `TELETHON_SESSION` set in `.env`. Generate the string session once via `docker run -it --rm -e TELETHON_API_ID=... -e TELETHON_API_HASH=... psyb0t/telethon-plus:v0.2.0 login` — see [Telethon setup](docs/services/telethon.md). Without a session, the container starts but the API returns auth errors.

**Tests failing** — make sure the stack is running (`make run-bg`) and healthy (`docker compose ps`). Tests require the services they're testing to be enabled — `OLLAMA_CUDA=1` for Ollama CUDA tests, `SDCPP_CUDA=1` for sd.cpp CUDA tests, `PREDICTALOT=1` / `PREDICTALOT_CUDA=1` for forecasting tests, `MAILBOX=1` for mailbox tests, `TELETHON=1` for Telegram tests. The mailbox e2e send→recv→delete is additionally gated on `MAILBOX_TEST_MAILBOX_NAME` + `MAILBOX_TEST_ADDRESS` so it only fires when you've wired a real test mailbox. Run `bash test.sh --help` to see which tests are available and their requirements.

## License

WTFPL
