# Changelog

All notable changes to this project are documented here.

## [v1.3.0] — 2026-04-24

**SearXNG self-hosted search + Langfuse LLM observability.**

- Add SearXNG (`SEARXNG=1`) — self-hosted meta-search (Google, Bing, DuckDuckGo, Wikipedia) at `/searxng/`
- Add `search_web` MCP tool — auto-enabled when `SEARXNG=1`; any function-calling model can search the web
- Add Langfuse (`LANGFUSE=1`) — LLM observability at `/langfuse/`; traces all LiteLLM requests (latency, tokens, cost, prompt, response)
- Langfuse uses the shared PostgreSQL instance (separate `langfuse` database, auto-created on first start)
- LiteLLM Langfuse integration via `success_callback`/`failure_callback` — injected by build-config when `LANGFUSE=1`
- mcp_tools auto-enable condition expanded to include SearXNG
- `.env.example` documented with SEARXNG/LANGFUSE flags and Langfuse credential generation instructions

## [v1.2.0] — 2026-04-25

**nuextract-v1.5 for structured extraction; all CPU models available on CUDA.**

- Add `iodose/nuextract-v1.5` to CPU ollama — fine-tuned Phi-3.5-mini for unstructured text → JSON extraction
- All CPU models now also registered on CUDA ollama — every small model available GPU-accelerated when `OLLAMA_CUDA=1`
- LibreChat registration enabled by default (`ALLOW_REGISTRATION=true`) — first user auto-promoted to admin
- proxq bumped to v0.9.0 — fixes upstream timeout not applied to HTTP client
- nginx proxq rate limit raised 120r/m → 600r/m
- `PROXQ_UPSTREAM_TIMEOUT` raised 10m → 30m

### Patches

- **v1.1.1** — proxq v0.9.0, rate limit 600r/m, upstream timeout 30m

## [v1.1.0] — 2026-04-24

**Local model lineup overhaul: gemma4, abliterated, reasoning, better code models.**

CPU (ollama):
- Add: phi4-mini (3.8B reasoning), gemma4:e2b (multimodal), gemma3:4b (lightweight vision fallback), qwen3-embedding:0.6b
- Drop: phi3.5 (superseded by phi4-mini), nomic-embed-text (bge-m3 is better)

CUDA (ollama-cuda):
- Add: gemma4:e4b + e2b (multimodal), deepseek-coder-v2:16b (MoE code), deepseek-r1:8b (reasoning), qwen3-abliterated:16b (uncensored chat), gemma4-abliterated:e4b (uncensored vision)
- Drop: dolphin-mistral:7b (outdated), dolphin3:latest (redundant)

- Fallback chains rewritten for all new/changed models
- Tests and docs updated throughout

### Patches

- **v1.0.1** — recommend-limits.sh: OS memory reserve (2 GB or 5% RAM), CPU local services use max-of-active + idle overhead like CUDA group. Add CHANGELOG.md.

## [v1.0.0] — 2026-04-24

**Breaking:** Global `CUDA=1` replaced with per-service flags.

- `OLLAMA_CUDA=1` — GPU inference
- `SDCPP_CUDA=1` — GPU image generation
- `SPEACHES_CUDA=1` — GPU STT
- `QWEN_TTS_CUDA=1` — GPU TTS
- Each CUDA service independently toggleable — no more implicit activation
- Docker Compose profiles, Makefile, build-config, resource calculator, tests, and all docs updated
- Fixed flaky tests: removed stale HF image models, fixed CUDA STT input, simplified dolphin-phi test

## [v0.13.0] — 2026-04-23

**Stable-diffusion.cpp image generation with CUDA resource semaphore.**

- Go wrapper for sd.cpp with CPU/CUDA backends, model hot-swap, idle timeout
- 5 image models: sd-turbo, sdxl-turbo, sdxl-lightning, flux-schnell, juggernaut-xi (CUDA); sd-turbo, sdxl-turbo (CPU)
- CUDA/CPU semaphore prevents GPU OOM — 503 on contention
- MCP auto-discovers sdcpp models, generate_image works end-to-end
- E2E test: LLM calls tool, MCP generates image, LLM responds with link

### Patches

- **v0.13.3** — Merge ollama pullers into single service with PULL_CPU/PULL_CUDA flags (28 → 27 services)
- **v0.13.2** — Fallback chains for all 99 models, resource management docs, fixed stale defaults
- **v0.13.1** — Hardcode sdcpp listen address, documentation updates

## [v0.12.0] — 2026-04-23

**Rename ollama model prefixes.**

- `ollama-cpu-*` → `local-ollama-cpu-*`, `ollama-cuda-*` → `local-ollama-cuda-*`
- Follows `local-<provider>-<hardware>-<model>` convention
- README intro rewritten

### Patches

- **v0.12.1** — Fix prefix to include provider name (local-cpu → local-ollama-cpu)

## [v0.11.0] — 2026-04-22

**MCP media tools, LibreChat web UI, image pinning.**

- MCP server: `generate_image` + `generate_tts` with dynamic model discovery, structured JSON, HybridS3 uploads
- LibreChat web UI at `/librechat/` with LiteLLM backend and MCP tools
- All container images pinned to exact versions
- All provider YAMLs annotated with `model_info.mode` for media models

### Patches

- **v0.11.1** — Docs: add LibreChat + MCP tools docs, fix stale counts (94→92 models, 18→20 tools)

## [v0.10.0] — 2026-04-21

**CUDA audio services, resource manager, new ollama models.**

- `speaches-cuda` — CUDA-accelerated Whisper STT
- `qwen3-cuda-tts` — CUDA TTS with voice cloning
- Resource manager callback: unloads competing CUDA/CPU groups before each request (prevents OOM)
- CUDA groups: cuda-llm, cuda-tts, cuda-stt; CPU groups: cpu-tts, cpu-stt
- `GPU_NVIDIA` renamed to `CUDA` (more precise)
- stealthy-auto-browse v1.0.0: all browser tools → single `run_script` tool
- 9 new tests for audio and resource management

### Patches

- **v0.10.1** — Docs: correct model/tool counts, fix browser examples, label optional services

## [v0.9.0] — 2026-04-20

**GPU support with nvidia runtime, configurable data dirs.**

- `GPU_NVIDIA=1`: separate ollama-gpu instance with nvidia runtime
- 5 GPU models sized for 3060 12GB with per-model `num_gpu` control
- `DATA_DIR` / `DATA_DIR_<SERVICE>` env vars for relocating data directories
- All model names: `local-ollama-*` → `ollama-cpu-*` / `ollama-gpu-*`

## [v0.8.0] — 2026-04-20

**Replace moondream with gemma3:4b, add ollama tests.**

- Ollama test suite (4 tests: model registration, chat, embedding, vision)
- gemma3:4b as vision+chat model (moondream was broken)

## [v0.7.0] — 2026-04-18

**proxq async job queue proxy.**

- proxq (psyb0t/proxq) as always-on service in front of LiteLLM
- Async HTTP: submit request → get job ID → poll for result
- Whitelist mode: only OpenAI API paths are queued
- nginx routes `/q/` to proxq with rate limiting

### Patches

- **v0.7.3** — Bump proxq
- **v0.7.2** — Full proxq config via env vars (concurrency, retention, retries, caching)
- **v0.7.1** — Configurable nginx rate limits + timeouts via env vars, proxq v0.5.1

## [v0.6.5] — 2026-04-17

**Dynamic config build, all providers/services opt-in via flags.**

- `build-config.py` assembles LiteLLM config from per-provider YAML fragments based on `.env` flags
- All providers/services opt-in: `GROQ=1`, `CEREBRAS=1`, `CLAUDEBOX=1`, etc.
- Docker profiles for hybrids3, browser, ollama, speaches
- Fix postgres data loss: mount `.data/postgres` directly to PGDATA

### Patches

- **v0.6.6** — Fix DB

## [v0.6.0] — 2026-04-15

**Remove model group aliases, fix vision group.**

- Removed `model_group_alias` (silently broken — maps to one model, not a list)
- Removed group-level fallbacks
- Added local-ollama-moondream to vision group

### Patches

- **v0.6.4** — Bump claudebox v1.4.0, stealthy-auto-browse v0.22.5
- **v0.6.3** — Enable client-side JSON schema validation
- **v0.6.2** — Update claudebox
- **v0.6.1** — Patch

## [v0.5.0] — 2026-04-15

**Remove infinity reranker.**

- Removed infinity service (too RAM-hungry for CPU-only stacks)
- README cleanup

## [v0.4.0] — 2026-04-15

**Local reranking, 83 models.**

- Infinity reranking service with mxbai-rerank-xsmall-v1
- Resource limits in recommend-limits.sh

## [v0.3.0] — 2026-04-15

**82 models, local TTS, nginx rate limiting, security hardening.**

- Speaches: whisper STT, parakeet transcription, Kokoro TTS
- nginx rate limiting on all endpoints
- Cloudflare real IP restoration
- HAProxy admin restricted to private networks

## [v0.2.0] — 2026-04-15

Initial feature expansion.

## [v0.1.0] — 2026-04-15

Initial release.
