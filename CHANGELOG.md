# Changelog

All notable changes to this project are documented here.

## [v3.16.2] — 2026-07-31

**Mirror to GitLab only; Gitee is disabled until the account can publish.**

### Changed

- `git-mirror.yml` now enables GitLab only. Gitee requires a mobile number bound to the account before any repository can be public, and instead of refusing a public create it silently makes the repository private — so the mirror ran green while the result was visible to nobody. Re-enable `gitee_enabled` once the account is verified.

## [v3.16.1] — 2026-07-31

**Mirror the repository to GitLab and Gitee on every push.**

### Added

- `.github/workflows/git-mirror.yml` — push-mirrors every branch and tag to GitLab and Gitee, creating the repo on each if it does not exist yet and syncing the GitHub description (and topics, on GitLab). Read-only copies: the push is forced and refs deleted here are deleted there.
- Kept as its own workflow rather than a job in `pipeline.yml`, because the mirror needs to run on every branch push while `pipeline.yml` is tag-only and its `publish-to-clawhub` job has no ref guard — widening that trigger would publish to ClawHub on every branch push.

## [v3.16.0] — 2026-07-30

**Upgrade Talkies to 0.12.1, expose its profile-gated native APIs, and repair the MCP image's incompatible SDK install.**

### Added

- `/talkies/*` and `/talkies-cuda/*` proxy the corresponding native Talkies APIs, including live-ASR WebSocket upgrades and unbuffered CUDA PCM streaming. Each route is available only while its matching profile is enabled; disabled routes return `404`.
- Direct Talkies endpoints use the Aigate bearer token by default, with optional per-variant `TALKIES_AUTH_TOKEN` and `TALKIES_CUDA_AUTH_TOKEN` overrides. LiteLLM and MCP now send the same service credentials for mediated speech, voice listing, and model eviction calls.
- Direct-route rate, timeout, private-download, and live-stream limit settings are documented in `.env.example` and the Talkies service guide.
- Docker services now use bounded JSON log rotation (five 10 MB files) to prevent unbounded local log growth.

### Fixed

- Updated CPU and CUDA Talkies images to `0.12.1` and documented its newer model surface and streaming modes.
- Pinned the MCP SDK to the compatible v1 API line (`mcp==1.28.1`), eliminating the `mcp.server.fastmcp` startup crash. The MCP dependency set is now hash-locked with a seven-day release-age cutoff, and the image installs it with hash verification.
- Hardened the MCP image and service: digest-pinned base image, non-root runtime user, read-only filesystem, dropped capabilities, PID limit, `init`, and a restricted build context.

## [v3.15.8] — 2026-07-27

**Fix the Codex subsection of `## Agent integrations`, which told readers to add the marketplace but never told them how to install the plugin.**

### Fixed

- The Codex install snippet in the README was missing its install command — it ran `codex plugin marketplace add psyb0t/agents` and stopped. Added the missing line: `codex plugin add aigate@psyb0t`.
- The prose describing skill invocation conflated two different install paths. It now distinguishes them: installed via the marketplace, the skill invokes as `$aigate:aigate`; picked up automatically from the repo's own `.agents/skills/` with no install, it invokes as plain `$aigate`.

## [v3.15.7] — 2026-07-27

**Wire aigate into the Claude Code and Codex plugin ecosystems, and document every agent-integration channel in the README.**

### Added

- `.agents/.claude-plugin/plugin.json` — Claude Code plugin manifest (`name`, `description`, `author`, `homepage`, `license`, `keywords`). Declares `userConfig` for the aigate base URL and bearer token so Claude Code prompts for them at install time instead of requiring manual `.env` edits; the token is marked sensitive and stored in the OS keychain.
- `.agents/.codex-plugin/plugin.json` — Codex plugin manifest with the same metadata plus `version` and `"skills": "./skills/"`, pointing at the existing `.agents/skills/aigate/` skill.
- `## Agent integrations` section in the README with copy-pasteable install commands for Claude Code, Codex, and the OpenClaw skill.

## [v3.15.6] — 2026-07-27

**Add a GitHub Actions CI status badge to the README.**

### Added

- Added a GitHub Actions CI status badge to the README.

## [v3.15.5] — 2026-07-27

**Add self-hosted README badges.**

### Added

- Added self-hosted version and license badges; wired a badges job into pipeline.yml.

## [v3.15.4] — 2026-07-27

**Add a LICENSE file (WTFPL) so the project's license is explicit and detected by GitHub.**

### Added

- `LICENSE` — WTFPL (Do What The Fuck You Want To Public License), Version 2. The
  project previously shipped without a license file. The orchestration code
  (`docker-compose.yml`, `Makefile`, scripts, per-service config) is now explicitly
  WTFPL. The third-party services aigate composes (LibreChat, litellm, vLLM, SearXNG,
  llama.cpp, and the rest) are run as their own containers and retain their own
  upstream licenses.

## [v3.15.3] — 2026-07-26

**Local image generation fixes: `juggernaut-xi` could never load at all, SDXL generation OOMed at 1024×1024, and a failed image request could thrash the GPU for minutes.**

### Fixed

- **`local-sdcpp-cuda-juggernaut-xi` never worked — every load attempt failed since the model was added.** It was configured for split loading (`--diffusion-model` plus separate `--clip_l` / `--clip_g` / `--vae`), which cannot work for SDXL in stable-diffusion.cpp: the clip_g tensor prefix is chosen from a model-version probe that runs *before* the text encoders are loaded, so `cond_stage_model.1` is never emitted, `is_xl` never becomes true, and version detection fails with `get sd version from file failed`. This is still the behavior at upstream HEAD, so no version bump fixes it. Flux is unaffected because it is detected from `double_blocks` inside the diffusion model itself. `sdcpp/models.json` now points `juggernaut-xi` at the single-file `Juggernaut-XI-byRunDiffusion.safetensors` checkpoint (text encoders + VAE included), which detects as `Version: SDXL` and generates correctly. Requests for this model previously fell through to another model via the fallback chain, so callers received images from a *different* model under the `juggernaut-xi` name rather than an error.
- **VAE decode OOM at 1024×1024.** One-shot VAE decode requested a 7,680 MiB compute buffer on top of resident model weights, exceeding a 12 GB card and failing with `vae: failed to allocate the compute buffer`. `--vae-tiling` added to `juggernaut-xi` and `sdxl-lightning` in `sdcpp/models.json`; decode now completes in tiles. This also affected `sdxl-lightning` at its native 1024×1024 independently of the juggernaut change.
- **A single failed image request could thrash the GPU for minutes.** In `litellm/config/fallbacks.json`, every `local-sdcpp-cuda-*` model fell back to its own siblings (e.g. `juggernaut-xi` → `sdxl-lightning` → `flux-schnell`), and the `local-sdcpp-cpu-*` models likewise fell back to each other. Each sdcpp backend is a single `sd-server` process serving one model at a time, so a sibling hop cannot find spare capacity — it forces a full model swap (process kill + multi-GB reload), multiplied by the per-deployment retry count. Chains now route to genuinely independent capacity only: the other sdcpp backend, then `hf-flux-schnell`, then the OpenAI image models. Observed model swaps for a failing request dropped from 6–9 to 0–1.

### Changed

- `docker-compose.yml`: the `sdcpp-pull` init service now downloads the single-file `Juggernaut-XI-byRunDiffusion.safetensors` instead of the four split components (`juggernautXL_juggXIByRundiffusion-Q5_K_M.gguf`, `clip_l_sdxl.safetensors`, `clip_g.safetensors`, `xlVAEC_c91.safetensors`). The source repo is gated and requires the `HF_TOKEN` already passed to this service; the previously downloaded split files are no longer used and can be deleted (~3.5 GB). The checkpoint is ~6.6 GiB.
- `juggernaut-xi` VRAM footprint is now ~5 GB (was documented as ~2.5 GB against the quantized diffusion-only file). README and `docs/providers.md` updated.
- `HF_TOKEN` is now required to download the `juggernaut-xi` checkpoint (the source repo is gated). Without it that single model fails to download while the rest of the sdcpp models pull normally — noted in `.env.example`.

Operators pulling this release need `docker compose up -d --build --force-recreate sdcpp-cuda` — `models.json` is baked into the image (`COPY models.json /etc/sdcpp/models.json`), so a recreate without a rebuild silently keeps the old model definitions.

## [v3.15.2] — 2026-07-26

### Changed
- **Agent skill security hardening.** Hardened `.agents/skills/aigate/` SKILL.md's "Security & safety" section with an explicit guardrail: `AIGATE_TOKEN` is a single all-or-nothing capability grant with no per-tool scoping unless the operator has pre-split the per-service override tokens — an agent handed the token can trigger code execution, browser automation, and messaging in one shot, so it must only be given to fully trusted agents for the specific action the user explicitly requested. Documentation-only change; no behavior change.

## [v3.15.1] — 2026-07-26

### Fixed
- **Agent skill accuracy.** The `.agents/skills/aigate/` SKILL.md described the always-on core as "only nginx, LiteLLM, PostgreSQL, and Redis" — but `proxq` (the async job queue at `/q/`) also runs with no compose profile and is therefore always on. Corrected the always-on list to include `proxq`. No behavior change.

## [v3.15.0] — 2026-07-25

### Added
- **Agent skill + ClawHub publish.** Added `.agents/skills/aigate/` (SKILL.md + references/setup.md) documenting the single OpenAI-compatible endpoint at `:4000` and the bundled capabilities, plus a new tag-gated pipeline that publishes the skill to ClawHub.

## [v3.14.9] — 2026-07-20

**Bump claudebox v1.14.0-minimal → v2.0.13 and pibox-zai v0.12.0 → v0.14.0. Restores the claudebox v2 API-mode migration that had drifted out of `docker-compose.yml`, enables claudebox's MCP server, and fixes the file-ops 500s the drift caused.**

### Claudebox v1.14.0-minimal → v2.0.13

- `psyb0t/claudebox:v1.14.0-minimal` → `v2.0.13`.
- **Breaking (compose-file only, no external API change).** The claudebox service block now matches the v2 image contract:
  - `CLAUDE_MODE_API` / `CLAUDE_MODE_API_PORT` / `CLAUDE_MODE_API_TOKEN` env vars → `CLAUDEBOX_API_MODE` / `CLAUDEBOX_API_MODE_PORT` / `CLAUDEBOX_API_MODE_TOKEN`.
  - Config volume target `/home/claude/.claude` → `/home/aicode/.aicodebox`.
  - Workspace volume target `/workspaces` → `/workspace` (singular).
  - Healthcheck path `/health` → `/healthz`.
- **New:** `CLAUDEBOX_MCP_MODE=1` + `CLAUDEBOX_MCP_MODE_TOKEN` added to the service block. The v2 image gates its MCP server behind this separate mode flag (API mode alone doesn't mount it) — `/claudebox/mcp/` now answers `initialize` instead of 404.
- **Fixed:** `PUT /claudebox/files/*` was returning 500 because `.data/claudebox/workspace` on the host was root-owned while the v2 image's API process runs as uid 1000 (`aicode`). Re-chowned to match; file upload/download/list/delete all verified working.
- Operators running an older checkout of `docker-compose.yml` need `docker compose up -d --force-recreate claudebox` after pulling this release — the old env-var names and volume paths no longer match what the v2 image expects. If `.data/claudebox/workspace` predates this release, `chown -R 1000:1000` (or your `aicode` host UID) it once after pulling.
- `tests/test_claudebox.sh`: the `/claudebox/health` direct-API test case pointed at a path the v2 image dropped in favor of `/healthz` — updated to match.

### Pibox-zai v0.12.0 → v0.14.0

- `psyb0t/pibox:v0.12.0` → `v0.14.0`. No aigate-side config change — image-tag bump only.

Both services recreated and smoke-tested live through the LiteLLM proxy (`claudebox-sonnet`, `pibox-zai-glm-4.7`) and the full `tests/test_claudebox.sh` suite (chat, direct API health/status, file ops, OpenAI-compatible models — 4/4 passing).

## [v3.14.8] — 2026-07-19

**Cap LiteLLM container memory — plug the last unbounded-memory service in the stack. Fixes host-tanking crashes under sustained load.**

The `litellm` service in `docker-compose.yml` had no `mem_limit`, `memswap_limit`, or `pids_limit` — every other long-running service in the stack had memory caps set (via `.env.limits` or explicit compose defaults), but the LLM gateway itself was the one gap. Under sustained voidalpha traffic (LiteLLM Router state + connection pool retention + response body buffering on long streams + fallback context accumulation) the container was drifting from ~800 MiB idle to 3+ GiB over hours — with no ceiling, it would eventually starve the host on machines without enough headroom.

- `docker-compose.yml`: added the following env-var-tunable defaults to the `litellm` service block:
  - `mem_limit: ${LITELLM_MEM_LIMIT:-4g}`
  - `memswap_limit: ${LITELLM_MEMSWAP_LIMIT:-8g}`
  - `pids_limit: ${LITELLM_PIDS_LIMIT:-512}`
- Sizing rationale: 4 GiB matches the 4 workers (`LITELLM_WORKERS: 4`) at ~1 GiB per worker plus master overhead — enough headroom for connection pools and long-stream buffering without silently absorbing a real leak. Swap at 2× mem to match the compose convention already used for pibox-zai and other services. PIDs at 512 covers the async worker + subprocess pool with room to spare.
- Operators can override via `.env` if they want to tighten or loosen based on observed usage: `LITELLM_MEM_LIMIT=6g` (or whatever the host actually has room for). No default change; existing installations pick up the cap on next recreate.
- **Outcome:** if LiteLLM drifts up under load, it OOM-kills only the LiteLLM container (which auto-restarts under `restart: unless-stopped`) — the host stays alive. Contained failure instead of host-wide crash.

Full-stack sweep: every remaining service in `docker-compose.yml` has `mem_limit` + `cpus` set. The lone exception is `postgres-init`, a one-shot init container that runs at boot and exits — negligible blast radius. `pids_limit` project-wide coverage is still a defense-in-depth gap (only `litellm` has it as of this release) but not related to the memory-crash symptom this release addresses.

## [v3.14.7] — 2026-07-09

**Bump pibox v0.11.3 → v0.12.0. Image-tag bump only. Upstream now surfaces provider rejections as HTTP 400 instead of `200 + empty text`.**

- `psyb0t/pibox:v0.11.3` → `v0.12.0`. Base image tracked to `psyb0t/aicodebox:v0.11.0`.
- **Upstream behavior change:** when the upstream model rejects a request (content-safety filter / rate limit / auth failure), `/pibox-zai/openai/v1/chat/completions` now returns **HTTP 400** with the provider's error message instead of `200` with an empty completion body. The `PiAdapter` forwards the provider-error detail on `RunResult.provider_error` (pi reports it as `stopReason=error + errorMessage` on the assistant turn).
- **Aigate impact:** LiteLLM's proxy now sees a real `4xx` from pibox on filter / rate-limit / auth failures and treats it as retryable per its `num_retries: 3` + fallback chain — the standard recovery path. Previously a content-filter block became a phantom `200 + empty completion` that reached the caller as ambiguous silence. Callers who correctly check status will now get the real reason surfaced; anyone treating a `200 + empty text` as success needs to check the completion length or fall back appropriately.
- No API surface, env-var, or config change on the aigate side. Container recreated and verified healthy against the freshly-built local image.

### Heads-up

`psyb0t/pibox:v0.12.0` + `psyb0t/aicodebox:v0.11.0` may not be on Docker Hub at this tag's cut moment. Fresh pulls will fail until the upstream tags get pushed.

## [v3.14.6] — 2026-07-02

**Bump talkies v0.9.0 → v0.10.0 (CPU + CUDA) and flickies v0.3.0 → v0.3.1 (CPU + CUDA). Image-tag bump only. Both upstream releases are wire-compatible with their prior versions — no aigate-side changes required.**

### Talkies v0.9.0 → v0.10.0 (CPU + CUDA)

- `psyb0t/talkies:v0.9.0` → `v0.10.0`
- `psyb0t/talkies:v0.9.0-cuda` → `v0.10.0-cuda`

Upstream notes:
- **Configurable log level.** New `TALKIES_LOG_LEVEL` env var (falls back to `LOG_LEVEL`); case-insensitive `debug` / `info` / `warn` / `error` / `fatal`. Default `info`; an unrecognized value fails fast at startup.
- **Opt-in full-request DEBUG logging.** At `debug`, the HTTP boundary logs full request + response bodies as structured JSON. That's PII — TTS input text, cloned-voice reference transcripts, ASR transcripts all land in the log. A one-time WARNING fires at startup when `debug` is active; at `info` and above body content is never logged.
- **Housekeeping.** Repo-wide `black + isort` format pass plus committed `flake8` + `mypy` config.
- Wire-compatible with v0.9.0 — no API or request-shape change.

Note for aigate operators: this repo's `.env` already sets `TALKIES_LOG_LEVEL=DEBUG` + `TALKIES_CUDA_LOG_LEVEL=DEBUG`, so the new body logging is active out of the box. Flip both to `INFO` and recreate the containers to suppress the body dumps.

### Flickies v0.3.0 → v0.3.1 (CPU + CUDA)

- `psyb0t/flickies:v0.3.0` → `v0.3.1`
- `psyb0t/flickies:v0.3.0-cuda` → `v0.3.1-cuda`

Upstream notes:
- **Engine-unload memory-leak fix.** Applies to `wav2lip`, `wav2lip-gan`, `latentsync-1.5`, `gfpgan`. Previously weights stayed resident after eviction because Python's cyclic model graph wasn't collected before `torch.cuda.empty_cache()`. v0.3.1 runs `gc.collect()` first so the graph gets reclaimed. Fixes: idle sweep, `DELETE /v1/engines/{slug}` (the endpoint the aigate resource_manager + `POST /v1/unload/*` uses), and hot-swap between engines. Directly improves the v3.14.5 competing-group eviction path — before, evicting flickies-cuda released the Python object but VRAM stayed resident.
- **Opt-in DEBUG observability** (`FLICKIES_LOG_LEVEL=DEBUG`): ffmpeg commands + results, transform decisions (`stream_copy` vs `precise_reencode`), inference wall_secs, URL byte counts, job lifecycle, HTTP 4xx/5xx rejections.
- **Security.** Logged URLs are query-stripped so presigned credentials never hit the logs.
- No API surface change. `openapi.yaml info.version` → `0.3.1`.

### Heads-up

`psyb0t/talkies:v0.10.0` + `-cuda` and `psyb0t/flickies:v0.3.1` + `-cuda` may not be on Docker Hub at this tag's cut moment. Fresh pulls will fail until the upstream tags get pushed.

## [v3.14.5] — 2026-07-02

**Cross-service GPU eviction hardening: closes the resource_manager gap that let audiolla / flickies OOM-kill talkies / ollama by hoarding VRAM. Ships new `POST /v1/unload/{cuda,cpu}` endpoints. Bundles flickies v0.3.0 bump.**

### Cross-service eviction — closes the audiolla / flickies gap

`litellm/callbacks/resource_manager.py` `async_pre_call_hook` unloads every competing hardware-class service before allocating VRAM for a LiteLLM-routed call. Prior to this release only 5 CUDA groups were registered — `cuda-llm` (ollama), `cuda-img` (sdcpp), `cuda-stt-talkies`, `cuda-vllm`, `cuda-llamacpp`. Direct-HTTP services (audiolla, flickies) were NOT registered, so a Wav2Lip / LatentSync / Demucs session hoarding 7+ GiB of VRAM could OOM-kill talkies-cuda or ollama-cuda the moment they tried to load a model.

- Added groups `cuda-audiolla`, `cuda-flickies`, `cpu-audiolla`, `cpu-flickies` to `_ALL_CUDA_GROUPS` / `_ALL_CPU_GROUPS`.
- Added `_unload_cuda_audiolla` / `_unload_cpu_audiolla` — issue `POST /v1/unload` (audiolla's bulk-evict-every-loaded-engine endpoint).
- Added `_unload_cuda_flickies` / `_unload_cpu_flickies` — enumerate `GET /v1/engines`, `DELETE /v1/engines/{slug}` for every engine with `loaded: true`. Slug list is discovered live so new engines auto-participate.
- Injected `Authorization: Bearer $AIGATE_TOKEN` on downstream requests since audiolla and flickies both gate their APIs.
- No `_get_group()` mapping for `local-audiolla-*` / `local-flickies-*` — these services are not LiteLLM-routed, so the groups only ever appear as COMPETING groups (never as own-group), which is the intended behavior.

Verified live: a `POST /v1/chat/completions` targeting an ollama-cuda model triggers `[resource_manager] group=cuda-llm unloading competing: {cuda-audiolla, cuda-flickies, ...}` and each downstream unload logs its outcome.

### New endpoints — `POST /v1/unload/{cuda,cpu}` + `POST /v1/unload`

Same fan-out shape as the resource_manager competing-group unload, but exposed as plain HTTP endpoints for operators / oncall / scripts that need to free VRAM without piggybacking on a fake LLM call.

- `POST /v1/unload/cuda` — fans out concurrently to `ollama-cuda`, `sdcpp-cuda`, `talkies-cuda`, `vllm-cuda`, `llamacpp-cuda`, `audiolla-cuda`, `flickies-cuda`.
- `POST /v1/unload/cpu` — CPU counterpart, same 7 services.
- `POST /v1/unload` — convenience, runs both in sequence.
- Response shape: `{"class": "<class>", "results": {"<service>": {"status": "ok|empty|error|skipped", "unloaded": [...]}}}`. Per-service errors do not fail the whole call.
- Implemented in `mcp/server.py` as three `@mcp.custom_route(...)` handlers. Each downstream unload shape lives in a small per-service helper (`_unload_ollama`, `_unload_sdcpp`, `_unload_api_ps`, `_unload_audiolla`, `_unload_flickies`).
- Auth: same bearer as the rest of aigate (nginx enforces via the standard MCP_TOOLS_AUTH_TOKEN / AIGATE_TOKEN fallback). Downstream calls to auth-gated services carry the token via the new `AIGATE_TOKEN` env var on the mcp container.
- `nginx` routes: `location ~ ^/v1/unload(/(cuda|cpu))?$` proxies to `mcp:8000` with a 120s read/send timeout (some unloads take a few seconds to actually release VRAM). Same rate-limit zone as `/v1/audio/voices`.

### Flickies bump v0.2.0 → v0.3.0 (CPU + CUDA)

Image-tag bump only. Upstream v0.3.0 adds an optional `precise: bool` (default `false`) field on `POST /v1/video/trim` and `POST /v1/video/concat` (plus the matching MCP tools). `precise: false` keeps the existing `-c copy` stream-copy fast path (zero behavior change for current callers). `precise: true` re-encodes to libx264 CRF 18 + AAC 192k for frame-accurate boundaries — fixes `start_sec` snapping to the nearest keyframe and concat of mismatched codec / timebase / SAR inputs. Pure additive change upstream; defaults preserve prior behavior exactly. nginx + litellm proxy the new body field transparently — no aigate-side wiring.

### Heads-up

`psyb0t/flickies:v0.3.0` + `psyb0t/flickies:v0.3.0-cuda` may not be on Docker Hub at this tag's cut moment. Fresh pulls will fail until the upstream tags get pushed.

## [v3.14.4] — 2026-06-29

**Expose all 8 z.ai GLM models. Adds `glm-5.2` (new flagship), `glm-5-turbo`, `glm-5`, `glm-4.6`, `glm-4.5`. No removals.**

z.ai's live catalog at `https://api.z.ai/api/anthropic/v1/models` lists 8 GLM models; aigate was only exposing 3 (`glm-4.5-air`, `glm-4.7`, `glm-5.1`). This release brings the pibox-zai route surface up to parity with what z.ai actually serves.

### Added LiteLLM routes (`litellm/config/providers/pibox-zai.yaml`)

- `pibox-zai-glm-5.2` → `openai/glm-5.2` — newest flagship, dropped 2026-06-17
- `pibox-zai-glm-5-turbo` → `openai/glm-5-turbo` — fast tier
- `pibox-zai-glm-5` → `openai/glm-5` — earlier 5-series
- `pibox-zai-glm-4.6` → `openai/glm-4.6`
- `pibox-zai-glm-4.5` → `openai/glm-4.5`

All five smoke-tested end-to-end (`POST /v1/chat/completions` via litellm → pibox → z.ai). Returns content. Original three routes unchanged.

### Pibox container env

`PIBOX_AVAILABLE_MODELS` default expanded from `glm-4.5-air,glm-4.7,glm-5.1` → `glm-4.5,glm-4.5-air,glm-4.6,glm-4.7,glm-5,glm-5-turbo,glm-5.1,glm-5.2`. `docker-compose.yml` + `.env.example` updated. Pibox restart required (`docker compose up -d pibox-zai`) for the container to advertise all eight on `/openai/v1/models`.

### Docs

- `docs/providers.md` — pibox-zai table rewritten with all eight aliases, GLM Coding Plan quota multipliers per model (4-series = baseline 1×, 5-series = 3× peak / 2× off-peak, current 1× off-peak promo through end of September 2026 noted), recommendation to default to `glm-4.7` for batch / catalog work.

### Quota awareness (operator note)

Z.ai bills `glm-5.x` and `glm-5-turbo` at **3× during Beijing peak (14:00–18:00)** and 2× off-peak (1× under their current promo). The `glm-4.x` family bills at the flat baseline 1× rate. Adding the 5-series routes does not change billing for existing 4.x callers, but operators should be aware that defaulting an integration to `glm-5.2` will burn quota ~3× faster than `glm-4.7` during peak hours.

## [v3.14.3] — 2026-06-28

**Test-script catch-up to v3.14.2 provider audit. No prod / API / docs changes.**

The v3.14.2 release removed sunset-flagged Groq / Cerebras / OpenRouter aliases and added new free-tier candidates, but the shell test suite (`tests/test_*.sh`) still referenced the dead aliases — `bash tests/test_litellm.sh` would have flagged "missing" routes (false negatives) and any `tests/test_*.sh` doing inline `POST /v1/chat/completions` with a removed model name would have failed with HTTP 400 "Invalid model name". This patch syncs the test scripts.

- **`tests/test_litellm.sh`** — `EXPECTED_MODELS` array:
  - Removed: `groq-llama-3.1-8b`, `groq-llama-3.3-70b`, `groq-llama-4-scout`, `groq-kimi-k2`, `groq-qwen3-32b`, `cerebras-qwen3-235b`, `cerebras-llama-3.1-8b`, `or-minimax-m2.5`.
  - Added: `groq-qwen3.6-27b`, `groq-gpt-oss-safeguard-20b`, `or-nemotron-ultra-550b`, `or-nemotron-nano-9b`, `or-nemotron-nano-30b`.
  - Inline `POST` body in the chat-completion smoke + streaming smoke switched from `groq-llama-3.1-8b` to `groq-gpt-oss-20b` (the recommended replacement per Groq's deprecation schedule).
- **`tests/test_integration.sh`** — swapped `groq-llama-3.1-8b` → `groq-gpt-oss-20b` (2 call sites: website-identification LLM + integration ping-pong smoke).
- **`tests/test_piston.sh`** — swapped `groq-llama-3.3-70b` → `groq-gpt-oss-120b` in the local LLM-model variable used by the code-execution-via-LLM smoke.
- **`tests/test_proxq.sh`** — swapped `cerebras-llama-3.1-8b` → `cerebras-gpt-oss-120b` in the rate-limit smoke (cerebras free tier collapsed to 2 models; `gpt-oss-120b` is the survivor).
- **`tests/test_security.sh`** — swapped `groq-llama-3.1-8b` → `groq-gpt-oss-20b` in the prompt-injection smoke.
- **`tests/test_telethon.sh`** — swapped `groq-llama-3.3-70b` → `groq-gpt-oss-120b` in the bot-replies-with-LLM-response smoke.

`shellcheck` clean on all six files (no new warnings vs `v3.14.2` HEAD).

## [v3.14.2] — 2026-06-28

**Provider cleanup + pibox v0.11.2 (cheap schema retries). Removes sunset-flagged routes; adds new cloud models.**

### Pibox bump

- `psyb0t/pibox:v0.11.1` → `v0.11.2` (tracks `aicodebox v0.10.0`). Schema-mode retries on `/openai/v1/chat/completions` no longer replay the full original prompt — base allocates an ephemeral `/tmp/aicodebox/<uuid>/` workspace (mode `0o700`) and session-continues the retry conversation with a minimal corrective prompt (error + directive + schema, ~1.5k tokens). A 100k-token request needing 3 retries used to pay 400k input tokens; now ~100k + ~4.5k. PiAdapter contract unchanged. Wire shape unchanged.

### Provider model audit — removed dead/sunset routes

Cross-checked every `litellm/config/providers/*.yaml` route against each provider's live `/v1/models` endpoint. Removed:

- **Groq (sunset-flagged per Groq deprecations):**
  - `groq-kimi-k2` (`moonshotai/kimi-k2-instruct` — sunset 2025-10-10, `-0905` variant sunset 2026-04-15)
  - `groq-llama-3.1-8b` (`llama-3.1-8b-instant` — sunset 2026-08-16) → use `groq-gpt-oss-20b`
  - `groq-llama-3.3-70b` (`llama-3.3-70b-versatile` — sunset 2026-08-16) → use `groq-gpt-oss-120b`
  - `groq-llama-4-scout` (`meta-llama/llama-4-scout-17b-16e-instruct` — sunset 2026-07-17) → use `groq-gpt-oss-120b`
  - `groq-qwen3-32b` (`qwen/qwen3-32b` — sunset 2026-07-17) → use `groq-gpt-oss-120b`
- **Cerebras (free tier gutted to 2 models):**
  - `cerebras-qwen3-235b` (`qwen-3-235b-a22b-instruct-2507`)
  - `cerebras-llama-3.1-8b` (`llama3.1-8b`)
- **OpenRouter:**
  - `or-minimax-m2.5` (`minimax/minimax-m2.5:free` — `:free` variant pulled)

### Renamed model fields (alias names stable)

- `groq-compound`: `groq/compound-beta` → `groq/compound`
- `groq-compound-mini`: `groq/compound-beta-mini` → `groq/compound-mini`

### Added routes

- `groq-qwen3.6-27b` (`qwen/qwen3.6-27b`)
- `groq-gpt-oss-safeguard-20b` (`openai/gpt-oss-safeguard-20b`)
- `or-nemotron-ultra-550b` (`nvidia/nemotron-3-ultra-550b-a55b:free`, 1M ctx)
- `or-nemotron-nano-9b` (`nvidia/nemotron-nano-9b-v2:free`)
- `or-nemotron-nano-30b` (`nvidia/nemotron-3-nano-30b-a3b:free`, 256k ctx, reasoning)

### Config hygiene

- `litellm/config/fallbacks.json`: purged every reference to removed aliases (both as keys and chain values). 106 → 98 chains.
- `docs/providers.md`: Groq + Cerebras + OpenRouter tables rewritten; fallback example sentence updated to use a non-deprecated alias.
- `docs/services/librechat.md` + `docs/services/browser.md` + `README.md`: stale example/default model references swapped to live aliases.
- `LIBRECHAT_TITLE_MODEL` default flipped from `groq-llama-3.3-70b` → `groq-gpt-oss-120b` in `docker-compose.yml` + `.env.example` (active `.env` updated locally).

### Tests / verification

- `make build-config` → assembles 109 active models (was 112).
- All removed aliases return HTTP 400 "Invalid model name" through `/v1/chat/completions`.
- All new aliases serve OK end-to-end via litellm.
- Pibox `v0.11.2` post-deploy: 78% one-shot success, retry-attempt token cost flat (~12k/attempt avg) vs `v0.11.1` where each attempt re-paid the full prompt.

## [v3.14.1] — 2026-06-22

**Bump pibox v0.11.0 → v0.11.1 — tracks aicodebox v0.9.1 base; schema-mode retry prompt now carries the original task.**

Upstream pibox v0.11.1 pulls in an aicodebox v0.9.1 bug fix that improves schema-mode retry success rates on the `/pibox-zai/openai/v1/chat/completions` route. PiAdapter contract unchanged. Wire shape unchanged. No code, config, or doc changes on the aigate side beyond the image tag.

### What v0.11.1 fixes

The schema-mode retry helper has been running with `no_continue=True` (fresh session, no history — prevents the model from doubling down on its bad answer) since the schema validation feature shipped. But the retry prompt the helper built only carried `bad output + parse error + schema`. The **original task was missing** from each retry body.

For schemas where correction depends on task context (large enum picks, allowed-values lists, domain identifiers), the retry agent had near-zero chance of correcting — it would either re-pick blindly or fall back to prose. Schema-set callers saw repeated 422 / schema-exhaustion failures on prompts that the base model would have answered correctly given the original task.

v0.11.1 re-states the original task in each retry body, sectioned for clarity:

```
- Original task ───
- Your previous (invalid) response ───
- Parse / validation error ───
- Required schema ───
```

Net effect: retries succeed more often, so cumulative token usage on retrying schema runs should DROP even though each individual retry prompt is slightly longer (it now carries the original task too).

### aigate-side

`tests/test_pibox.sh` doesn't exercise the schema retry path (no `x-aicodebox-json-schema` header, no `response_format` body field), so the test suite stays as-is.

### Files

- `docker-compose.yml` — `psyb0t/pibox:v0.11.0` → `:v0.11.1`.

### Live-verified

- `psyb0t/pibox:v0.11.1` recreated, healthy.
- `tests/test_pibox.sh` — 7/7 green.

### Caveats

- `psyb0t/pibox:v0.11.1` and the underlying `psyb0t/aicodebox:v0.9.1` may not be published on Docker Hub at the moment this tag is cut. Fresh `docker compose up` against a clone with no local images will pull-404 until upstream publishes — or operators need to build locally from `github.com/psyb0t/docker-pibox@v0.11.1`.

## [v3.14.0] — 2026-06-21

**New service `flickies` — self-hosted video toolkit (sibling of audiolla / talkies). Lipsync via LatentSync 1.5 + Wav2Lip, face restore via GFPGAN v1.4, ffmpeg ops (trim / concat / transcode / scale / mux_audio / extract_audio / thumbnail_grid), ffprobe info. CPU + CUDA variants. 11 MCP tools.**

Pinned at `psyb0t/flickies:v0.2.0` (CPU) and `psyb0t/flickies:v0.2.0-cuda`. Mirrors the audiolla integration shape exactly — same wire format (JSON body on every endpoint, raw bytes only at `PUT /v1/files/{path}`, `output_path` xor `output_url` for any tool that produces a video), same hot-swap eviction + idle unload, same `/data` bind mount layout for shared model cache between CPU and CUDA variants.

### New service surface

- `POST /flickies/v1/video/lipsync` — engines: `latentsync-1.5` (Apache-2.0, CUDA-only, ~8 GB VRAM, default on CUDA), `wav2lip` / `wav2lip-gan` (LRS2 non-commercial — gated on `FLICKIES_ENABLE_NONCOMMERCIAL=1`).
- `POST /flickies/v1/video/restore` — engine: `gfpgan` (GFPGAN v1.4, Apache-2.0, CUDA-only). Chains after Wav2Lip to fix the soft 96×96 mouth crop, or stand-alone on any video.
- `POST /flickies/v1/video/trim`, `concat`, `transcode` (incl. gif + fps + codec change), `scale`, `mux_audio`, `extract_audio`, `thumbnail_grid` — ffmpeg ops, CPU-only.
- `POST /flickies/v1/video/info` — ffprobe metadata (duration, codec, fps, dimensions, bitrate).
- `GET /flickies/v1/engines` — engines + load state + license posture; `POST /flickies/v1/engines/{slug}` triggers explicit eviction.
- `PUT /flickies/v1/files/{path}` — stage raw video / audio bytes; `GET /flickies/v1/files/{path}` — fetch the result a tool wrote there.
- `POST /flickies/v1/mcp/` — 11 MCP tools: `list_engines, info, lipsync, restore, transcode, trim, concat, scale, mux_audio, extract_audio, thumbnail_grid`. Surfaced in LiteLLM's aggregated `/mcp/` as `flickies-*` (CPU) and `flickies_cuda-*` (CUDA).
- Tested ceiling per upstream: RTX 3060 12 GB — fits LatentSync 1.5 with headroom; Wav2Lip + GFPGAN chain peaks at ~5 GB. GFPGAN + LatentSync 1.5 are CUDA-only — the CPU image refuses to load them. CPU image runs all ffmpeg ops + slow Wav2Lip-CPU.

### Config

- Profile flags `FLICKIES=1` / `FLICKIES_CUDA=1` toggle the variants (same shape as `AUDIOLLA=1` / `AUDIOLLA_CUDA=1`).
- `FLICKIES_AUTH_TOKEN` (defaults to `AIGATE_TOKEN`) — bearer for `/flickies/*`.
- `FLICKIES_ENABLED_ENGINES` — comma-separated engine slug allow-list (empty = all).
- `FLICKIES_PREFETCH_ALL=1` — pre-pull every available engine at boot (respects `cuda_only` + non-commercial gates); drops first-call latency on LatentSync from ~2.5 min to <200 ms.
- `FLICKIES_IDLE_UNLOAD_SECS` (default 600) — idle TTL before resident engines are unloaded.
- `FLICKIES_MAX_UPLOAD_BYTES` (default 500 MB) — upload cap; nginx route's `client_max_body_size` set from the same env var.
- `FLICKIES_LOG_FILE` (default `/data/logs/flickies.log`) — rotating JSON log file (50 MB × 5 backups). stderr carries the same lines.
- `FLICKIES_ENABLE_NONCOMMERCIAL=1` — LRS2 opt-in for Wav2Lip / Wav2Lip-GAN. Same gate pattern as audiolla's `AUDIOLLA_ENABLE_NONCOMMERCIAL` for matchering / MusicGen.
- `FLICKIES_OFFLINE=1` — disable auto-download; operator stages HF snapshots under `${DATA_DIR_FLICKIES}/hf/hub/models--*/` manually.
- `RATELIMIT_FLICKIES[_BURST]` / `RATELIMIT_FLICKIES_CUDA[_BURST]` (default `30r/m`, burst `20`) — nginx rate-limit zones.
- `TIMEOUT_FLICKIES` (default `24h`) — nginx proxy timeout; lipsync / restore on multi-minute clips can run for several minutes.
- `DATA_DIR_FLICKIES` (default `${DATA_DIR}/flickies`) — bind-mounted as `/data` in both containers (shared between CPU + CUDA, so the second variant to boot reuses the first's downloads with zero re-fetch).

### Files

- `docker-compose.yml` — new `flickies` + `flickies-cuda` service blocks, new `/flickies/` + `/flickies-cuda/` nginx routes, new `flickies` + `flickies_cuda` rate-limit zones, `FLICKIES_AUTH_TOKEN` passthrough on the `litellm` service so LiteLLM's `os.environ/FLICKIES_AUTH_TOKEN` MCP auth resolution works.
- `Makefile` — `FLICKIES=1` / `FLICKIES_CUDA=1` profile autodetect; `flickies` + `flickies-cuda` added to `COMPOSE_PROFILES` macro.
- `.env.example` — `FLICKIES=` / `FLICKIES_CUDA=` flags + every tunable (auth, device, engines, prefetch, idle-unload, upload cap, rate limit, fetch policy, log file, noncommercial gate, webhook secret), plus `RATELIMIT_FLICKIES[_CUDA][_BURST]`, `TIMEOUT_FLICKIES`, `DATA_DIR_FLICKIES`.
- `recommend-limits.sh` — `flag_flickies` / `flag_flickies_cuda` parsed from `.env`; included in the "Enabled:" summary line.
- `litellm/build-config.py` — `flickies` + `flickies-cuda` MCP fragment auto-discovery.
- `litellm/config/mcp/flickies.yaml` + `litellm/config/mcp/flickies-cuda.yaml` — MCP registrations, bearer auth, `Host: 127.0.0.1:8000` static-header override (FastMCP's DNS-rebinding protection rejects `Host: flickies:8000` otherwise, returning 421).
- `docs/services/flickies.md` — full service page (endpoint table, env-var reference, lipsync + restore + ffmpeg curl recipes).
- `docs/services/README.md`, `docs/README.md` — index entries.
- `docs/mcp-tools.md` — flickies MCP section (11 tools + per-tool table).
- `README.md` — Tools-and-capabilities bullet, services-table row, ASCII routing diagram (routes block + MCP-servers block), `.data/` directory table, profile-flag enable table.
- `.gitignore` + `.data/flickies/.gitkeep` — keep the empty data dir in the tree but ignore weight cache contents.
- `tests/test_flickies.sh` — 4 assertions per variant (healthz_open, requires_auth, engines_list, mcp_tools_present). Total 8 tests; reuses the audiolla CPU/CUDA gating pattern.

### Other ASCII-diagram fix

- README routing diagram's "MCP servers" block now lists `piston (via mcp_tools)` as a callout pointing at the `execute_code` tool it powers — previously piston was only mentioned in the `mcp_tools` line itself. Piston still doesn't run its own MCP server (upstream `engineer-man/piston` exposes only REST); the `execute_code` MCP tool wrapping it lives inside the `mcp_tools` aggregator service. The diagram now makes that relationship visible to anyone scanning the ASCII for "where does piston show up in MCP".

### Live-verified

- Both `psyb0t/flickies:v0.2.0` + `:v0.2.0-cuda` running, both healthy.
- `/flickies/healthz` + `/flickies-cuda/healthz` → 200.
- `/flickies/v1/engines` + `/flickies-cuda/v1/engines` → wav2lip, wav2lip-gan, latentsync-1.5 (cuda_only), gfpgan.
- `/flickies/v1/mcp/` + `/flickies-cuda/v1/mcp/` → 11 tools each.
- Aggregated `/mcp/` → 22 flickies tools surfaced (`flickies-*` + `flickies_cuda-*`).
- `tests/test_flickies.sh` → 8/8 pass.

### Caveats

- `psyb0t/flickies:v0.2.0` and `:v0.2.0-cuda` may not be on Docker Hub at the moment this tag is cut. Fresh `docker compose up` against a clone with no local images will pull-404 until upstream publishes — or operators need to build locally from `github.com/psyb0t/docker-flickies@v0.2.0`.

## [v3.13.0] — 2026-06-21

**Fix sd.cpp image-gen flakiness — resource_manager now blocking-pre-loads sd.cpp models inside the pre-call hook so LiteLLM never dispatches an image-gen call against a cold or mid-loading backend.**

### The bug

`/v1/images/generations` against `local-sdcpp-{cuda,cpu}-*` routes was intermittently returning HTTP 200 with empty `data` instead of an image. Symptom: ~10s response time per call (suggesting the backend was trying), no error in the response body.

Root cause was a three-stage amplification:

1. **sd.cpp wrapper** uses `TryLockModel` on every `POST /v1/images/generations`. If the model isn't already loaded, the first call holds the lock for ~5-20 s while loading (varies by model — sdxl-turbo ~55 s cold; sd-turbo ~24 s; sdxl-lightning ~55 s). Any concurrent call within that window returns 503 `another load or generation in progress`.
2. **LiteLLM router** responds to a 503 by retrying internally (`num_retries: 3`) and walking the per-model fallback chain (every sd.cpp model has 4-5 fallback targets — `sdxl-turbo → sdxl-lightning → sd-turbo → hf-flux-schnell → openai-dall-e-3`). Every retry hits the same lock. One external call → ~15-30 backend hits, all 503.
3. **LiteLLM image-gen fallback exhaustion** returns HTTP 200 with empty `data` instead of propagating the 503. (Chat-completion fallback exhaustion correctly returns 5xx; image-gen masquerades as success — upstream LiteLLM bug.)

Verified live: 4/5 sequential calls across mixed sd.cpp models returned empty data before the fix.

### The fix

`litellm/callbacks/resource_manager.py` — added `_preload_sdcpp()` helper + `_sdcpp_key_for()` model-alias translator, wired into `async_pre_call_hook` immediately after the competing-group unload step. When the requested model belongs to `cuda-img` / `cpu-img`:

1. The hardware semaphore is already held (existing behavior — serializes against other CUDA/CPU work).
2. Competing groups have been unloaded (existing behavior).
3. **NEW:** `POST <sdcpp-base>/sdcpp/v1/load?model=<key>` is issued and blocked-waited on. This is sd.cpp's explicit blocking-load endpoint — it returns 200 once the model is in memory and idle, or 200 `already_loaded` if it was already there.
4. The pre-call hook returns to LiteLLM. LiteLLM dispatches the actual `POST /v1/images/generations`. Backend is fully warm. Attempt 1 succeeds. No 503 storm, no fallback amplification, no empty-data response.

`_preload_sdcpp` failures are LOGGED (not raised) so a missing model / corrupt weights / GPU OOM surfaces as a real backend error from the dispatched call instead of indefinitely blocking the request.

### Behavior changes

- `local-sdcpp-{cuda,cpu}-*` requests now reliably return image data even on cold start / cross-model swap. Cold-load latency is now charged to the pre-call hook rather than to LiteLLM router's internal retry loop, so the elapsed wall-clock per external call is essentially unchanged.
- No-op (~ms) when the requested model is already loaded — `/sdcpp/v1/load` short-circuits with `already_loaded: true`.
- Other model groups (chat / embed / talkies / vllm / llamacpp / predictalot) — UNCHANGED. The pre-warm step only fires for `cuda-img` / `cpu-img`.
- New URL constants `_SDCPP_CUDA_URL` / `_SDCPP_CPU_URL` introduced for the unload + load endpoints (existing unload calls re-routed through the constants — no functional change).

### Verified live

- 5/5 sequential cold/warm/swap calls across `sd-turbo` / `sdxl-turbo` / `sdxl-lightning` return valid b64-encoded PNG data.
- pre-call log line `[resource_manager] sdcpp preloaded model=<key>` confirms the new step fires every cuda-img / cpu-img request.

### Known residual

- High-concurrency parallel calls (5+ simultaneous external requests against different sd.cpp models) can still flake — LiteLLM router's internal parallel retry path partially bypasses the proxy pre_call hook and can race the model-swap window. Beyond the realistic user workload (1-2 req/min for ad-hoc image gen) so deferred.
- Cosmetic: `_release_sem` fires 30+ times per call from multiple LiteLLM log events (latent — semaphore is idempotently released after first call; no functional impact).

### Files

- `litellm/callbacks/resource_manager.py` — new `_preload_sdcpp()` + `_sdcpp_key_for()` helpers; wired into `async_pre_call_hook` after the competing-group unload step.
- `docs/resource-management.md` — new "sd.cpp pre-load (image generation only)" section + step (4) added to the per-request flow.
- `README.md` — Resource Management section gains a "sd.cpp pre-load" paragraph between competing-group unload and auto-load on demand.

## [v3.12.6] — 2026-06-19

**Bump pibox v0.10.0 → v0.11.0 — tracks aicodebox v0.9.0; new OpenAI-standard `response_format` body field on `/openai/v1/chat/completions`.**

Upstream pibox v0.11.0 pulls in aicodebox v0.9.0, which wires the OpenAI-standard `response_format` body field into `/openai/v1/chat/completions`. Stock OAI SDKs (LangChain, openai-python, LlamaIndex) can now drive schema enforcement without the proprietary `x-aicodebox-json-schema` header. PiAdapter zero code changes — v0.9.0 was route-only.

### New surface

`/pibox-zai/openai/v1/chat/completions` and the LiteLLM-aggregated `pibox-zai-*` model aliases now accept `response_format` in the request body:

| `response_format.type` | Behavior |
|---|---|
| `text` | No schema (default, unchanged) |
| `json_object` | Permissive `{"type":"object"}` constraint — forces parseable JSON without restricting shape |
| `json_schema` | Uses `response_format.json_schema.schema` (OpenAI structured-outputs shape) as the schema |

Failure semantics + canonical re-serialized JSON content shape identical to the existing header path (`x-aicodebox-json-schema`). Body wins on conflict; the proprietary header stays supported as fallback.

### Breaking

**Breaking.** `/pibox-zai/openai/v1/chat/completions` with `response_format={"type":"json_object"}` now returns **200 with schema-validated JSON content** — was **400** in v0.10.0 and earlier (the rejection was the v0.10.0 happy-path test surface). Callers using the 400 as a control-flow signal must migrate — either accept the 200 + JSON content (the intended new behavior) or omit `response_format` entirely.

Routes through the LiteLLM-aggregated `/v1/models` listing are unaffected — model aliases stay the same.

### aigate-side

`tests/test_pibox.sh` doesn't exercise `response_format` on `/openai/v1/chat/completions`, so the test suite stays as-is. No code, config, or doc changes — pibox is a passthrough proxy and aigate documents talkies' `response_format` (ASR/TTS) but not pibox's chat-completions `response_format` (so nothing to sync).

### Files

- `docker-compose.yml` — `psyb0t/pibox:v0.10.0` → `:v0.11.0`.

### Live-verified

- `psyb0t/pibox:v0.11.0` present locally; `aigate-pibox-zai-1` recreated, healthy.
- `tests/test_pibox.sh` — 7/7 green.

### Caveats

- `psyb0t/pibox:v0.11.0` and the underlying `psyb0t/aicodebox:v0.9.0` may not be published on Docker Hub at this tag's cut moment. Fresh `docker compose up` from a clean clone will hit 404 until upstream publishes — or operators need locally-built images.

## [v3.12.5] — 2026-06-19

**Bump pibox v0.9.0 → v0.10.0 — tracks aicodebox v0.8.3 base; PiAdapter logging brought to reconstruction-grade; single-source versioning fix; test flake fix.**

Upstream pibox v0.10.0 pulls in two aicodebox patches — v0.8.2 (reconstruction-grade logging on the schema-mode path) and v0.8.3 (single-source versioning via `pyproject.toml` + `importlib.metadata`, eliminating the long-running `__version__ = "0.1.0"` drift bug) — and brings the PiAdapter layer's own logging from zero to spec. Wire-level contract unchanged.

### What v0.10.0 brings

- **PiAdapter logging.** Previously zero logging calls. Now: decode errors, provider errors, schema bolt-on, build_argv decisions, and a `parse_output` summary line per call (text_len, session_id, lines, decode_errors, usage_keys, provider_error). Security-aware — never logs tokens / secrets / full prompts / full schemas; only schema keys + truncated samples. Mirrors the level/format discipline from `~/.claude/rules/06-logging.md`.
- **aicodebox v0.8.2 schema-mode logging.** `parse_json_response`, `run_with_json_retry`, `oai.chat_completions`, header parse helpers — all logged at reconstruction-grade. Schema retries and failure modes are now observable end-to-end.
- **Single-source versioning (aicodebox v0.8.3).** `pyproject.toml` is THE version. `__init__.py` reads via `importlib.metadata`. Makefile derives the docker tag from pyproject and tags both `:v0.10.0` AND `:latest` per build. Eliminates the version-drift bug that had `__version__` stuck at `"0.1.0"` across every release since v0.1.0 itself.
- **Base image bump:** `psyb0t/aicodebox:v0.8.1` → `:v0.8.3` (tag pin — upstream notes digest pending registry push).
- **PiAdapter functional contract unchanged.** No wire-level changes to `/run` / OAI / MCP / files-API. Upstream 46/46 tests green.

### aigate-side

- `docker-compose.yml` — `psyb0t/pibox:v0.9.0` → `:v0.10.0`.
- `tests/test_pibox.sh:test_pibox_zai_chat` — swapped test model from `pibox-zai-glm-4.5-air` to `pibox-zai-glm-4.7`. Reason: z.ai's `glm-4.5-air` returns empty `content` ~80% of the time on the echo prompt (`"Reply with exactly: PIBOXPONG7742"`) — a model-side weakness in z.ai's smallest model, NOT a pibox bug. Surfaced because v0.10.0's new PiAdapter logging added `parse_output text_len=0` lines that made the failure mode visible (pre-v0.10.0, the empty completions went through silently and we just got lucky on test runs). `glm-4.7` follows the echo instruction reliably (5/5 in measurement). Comment added to the test documenting the rationale.

### Files

- `docker-compose.yml` — image tag bump.
- `tests/test_pibox.sh` — test model swap + rationale comment.

### Live-verified

- `psyb0t/pibox:v0.10.0` present locally; `aigate-pibox-zai-1` recreated, healthy.
- `tests/test_pibox.sh` — 7/7 green in isolation. Sequential reruns occasionally trip on z.ai upstream rate-limit / latency flakes (unrelated to pibox or aigate).

### Caveats

- `psyb0t/pibox:v0.10.0` and the underlying `psyb0t/aicodebox:v0.8.3` may not be published on Docker Hub at the moment this tag is cut. Operators pulling fresh and running `docker compose up` will hit a 404 until upstream publishes — or need to use locally-built images.

## [v3.12.4] — 2026-06-18

**Bump pibox v0.8.0 → v0.9.0 — tracks aicodebox v0.8.1 base; schema validation actually validates on `/openai/v1/chat/completions` + per-attempt usage breakdown.**

Upstream pibox shipped v0.9.0 the same day, bumping its aicodebox base from v0.7.0 to v0.8.1. Two meaningful surface changes propagate through `/pibox-zai/` (and through the LiteLLM `pibox-zai-*` aliases that route to it).

### What v0.9.0 brings

- **`/pibox-zai/openai/v1/chat/completions` schema validation actually validates now.** v0.7.0 plumbed the `x-aicodebox-json-schema` header into RunSpec but the route never read `result.parsed`, so schema-set callers got 200 OK on malformed JSON. v0.9.0 fixes that:
  - Success → `message.content` is canonical re-serialized JSON (no fences).
  - Schema exhaustion → 422.
  - Agent crash → 500.
  - `stream:true + schema header` → 400 (the two are incompatible).
- **Per-attempt breakdown on `/pibox-zai/run`** (`.attempts`) and on the OAI envelope (`.aicodebox_attempts` vendor extension). The top-level `.usage` is now summed across attempts so callers billing on total tokens see every retry counted. Useful for `caller-can-bill-per-attempt` and for debugging which retry failed which way.
- **Base image pinned by digest.** pibox v0.9.0's Dockerfile + Makefile pin `psyb0t/aicodebox:v0.8.1@sha256:3a234d49d348b3182897c781be6b364e6b5d17784c4b70ac12df132e066d6dac` to guard against tag-rebuild drift (`:latest` and `:v0.8.1` currently resolve to different image IDs on Docker Hub).

### Breaking — `/pibox-zai/openai/v1/models` response shape

**Breaking.** Upstream aicodebox v0.8.x renamed the `owned_by` field on `/openai/v1/models` entries from the adapter name (`"pi"`) to `"aicodebox"`. Old callers that filtered models by `owned_by == "pi"` (the old aicodebox idiom) will see zero matches against pibox v0.9.0. Migration: filter by `owned_by == "aicodebox"`, or by model `id` directly (e.g. `glm-4.7`).

Routes through the LiteLLM-aggregated `/v1/models` listing are unaffected — that endpoint surfaces the per-model `pibox-zai-glm-*` aliases regardless of what `owned_by` upstream stamps each entry with.

### aigate-side

- `tests/test_pibox.sh:test_pibox_zai_openai_models` — assertion rewritten to check `"owned_by":"aicodebox"` + presence of `"glm-4.7"` instead of the old `"pi"` adapter substring. Header comment updated to document the aicodebox v0.8.x rename so future-readers don't trip on it.
- No code, config, or other doc changes — pibox is a passthrough proxy.

### Files

- `docker-compose.yml` — `psyb0t/pibox:v0.8.0` → `:v0.9.0`.
- `tests/test_pibox.sh` — `test_pibox_zai_openai_models` updated for the `owned_by` rename.

### Live-verified

- `psyb0t/pibox:v0.9.0` pulled from Docker Hub. `aigate-pibox-zai-1` recreated, healthy.
- `tests/test_pibox.sh` — 7/7 green.

## [v3.12.3] — 2026-06-18

**Bump audiolla v1.0.7 → v1.0.10 — bundles three upstream patches (v1.0.8 / v1.0.9 / v1.0.10). All bug fixes; no API removals.**

> Heads-up: as of this release tag, `psyb0t/audiolla:v1.0.10` and `:v1.0.10-cuda` may not yet be published on Docker Hub. Operators pulling fresh from main + running `docker compose up` will need to wait until upstream publishes — or use locally-built images.

### v1.0.8 — UVR phantom-output root cause + remix stems arg

`/v1/audio/restore/uvr-{dereverb,deecho,denoise}` + `/v1/audio/noise-reduce/uvr-denoise` were returning `"model produced no output files"` regardless of input — a 3-layer config bug, not a model issue:

1. `audio-separator` snapshots `output_dir` into its per-architecture `model_instance` config at `load_model()` time. Mutating `sep.output_dir = tmpdir` AFTER load only updates the outer wrapper. The inner MDXC / VR / Demucs separator kept its original `output_dir` (= `os.getcwd()` = `/app/`, root-owned inside the container). pydub's ffmpeg export then failed with EACCES; audio-separator caught the exception and reported the would-have-been path in `output_files` as if successful; audiolla's "filter to files that actually exist on disk" check then dropped everything → "no output files".
2. `output_single_stem=self._primary_stem` in the `Separator(...)` call was filtering against the MODEL's `primary_stem_name` (e.g. "Vocals"), not against engines.json's `primary_stem` (e.g. "No Reverb"). Names never matched → library wrote zero stems.
3. Model's near-silent stem dropper + test helper accepting "no output files" as graceful skip masked layers 1 and 2 on synthetic fixtures.

Fix: drop `output_single_stem=` from the `Separator(...)` call (audiolla picks the right stem post-hoc via `_find_stem_file` substring match); propagate `sep.model_instance.output_dir = tmpdir` alongside `sep.output_dir = tmpdir` before each `separate()` call. Both `_separate_sync` and `_restore_sync_with_sep` paths updated. Plus a heavy-reverb test fixture + strict UVR output assertions.

Also: `/v1/audio/remix` was throwing `TypeError` (missing `stems` arg to `separate()`) — masked pre-v1.0.7 by FastAPI's plain-text 500. Fixed.

### v1.0.9 — remix single-stem-solo

Surfaced by v1.0.8 finally letting separation reach the mix step. Request that triggered:

```
POST /v1/audio/remix
{"engine":"htdemucs","stem_mix":{"vocals":1.0,"drums":0.0,"bass":0.0,"other":0.0}}
```

Solos vocals — drops every other stem. After gain filtering only ONE mix input survived. Downstream `mix_audio()` rejected with `"mix_audio requires at least 2 inputs"`.

Fix:
- New `audio.apply_gain_db(raw, filename, gain_db, output_format)` helper — single-stream ffmpeg `volume=` pass. Mirrors `mix_audio`'s output_format handling + codec selection.
- `server.py` remix handler short-circuits to `apply_gain_db` when `len(mix_inputs) == 1`. Two-stem-and-up path unchanged.

Regression test `test_remix_single_stem_solo` exercises end-to-end (htdemucs separation + single-stem bounce) and asserts response is JSON, detail does NOT contain `"requires at least 2"`.

### v1.0.10 — visualize/volume + metadata persist + catalog routes

Three concrete bugs from real user reports + a catalog/route consistency check:

- **`/v1/audio/visualize/video/volume`** — ffmpeg's `showvolume` filter rejects `s=WxH`; needs `w=W:h=H` as separate options. Added per-filter `size_arg_style` (`"s"` / `"wh"` / None) to the `_VISUALIZE_FILTERS` table and branched the filter-spec assembly. Regression: `test_visualize_volume_mp4`.
- **`/v1/audio/metadata` write mode** — now persists tagged audio to disk when `output_path` / `output_url` is supplied. `AudioMetadataRequest` gains the `BaseAudioOutputRequest` mixin; handler delegates to `write_output()` for the standard `{path|url, size, tags, persisted: true}` descriptor. Additive — without an output target the response is the unchanged shape (tags at top level) but flagged `persisted=false`. Regressions: `test_metadata_write_with_output_path_persists`, `test_metadata_write_without_output_marks_persisted_false`.
- **`/v1/catalog` paths corrected** — `/v1/audio/batch` → `/v1/batch` and `/v1/audio/diarize` → `/v1/audio/diarize/{engine}` (catalog was reporting wrong paths). New consistency test `test_catalog_paths_match_actual_routes` walks every `(method, path)` in the catalog and asserts each resolves against the FastAPI OpenAPI spec — guards against future drift.

Out-of-scope note: occasional plain-text 5xx reports are NOT audiolla's — v1.0.7's `@app.exception_handler(Exception)` wraps every uncaught exception in `{"detail": ...}`. Plain-text 5xx that still escapes comes from the layer above (nginx 502/504, container kill mid-request, kernel OOM).

### aigate-side

`tests/test_audiolla.sh` doesn't exercise `/v1/audio/restore/*`, `/v1/audio/noise-reduce/*`, `/v1/audio/remix`, `/v1/audio/visualize/*`, `/v1/audio/metadata`, or `/v1/catalog`, so the test suite stays as-is. No code, config, or doc changes on the aigate side beyond the image tag.

### Files

- `docker-compose.yml` — `psyb0t/audiolla:v1.0.7` → `:v1.0.10`, `psyb0t/audiolla:v1.0.7-cuda` → `:v1.0.10-cuda`.

### Live-verified

- `psyb0t/audiolla:v1.0.10` + `:v1.0.10-cuda` present locally; both containers recreated, both healthy.
- `tests/test_audiolla.sh` — 14/14 green (CPU + CUDA).

## [v3.12.2] — 2026-06-17

**Bump audiolla v1.0.6 → v1.0.7 — field aliases + master mode auto-detect + preset/pipeline JSON migration + global JSON 500 envelope.**

Upstream tagged the release as "UX + bug-fix. No API contract removed." Every change is additive (new accepted field name, optional field made optional) or a strict-superset relaxation (handler accepts more shapes than before). Most of it is invisible to aigate as a proxy — we surface whatever shape clients send.

### Upstream v1.0.7 changes

- **Field-name compatibility aliases.** `/v1/audio/fade` accepts `fade_in_sec` / `fade_out_sec` (consistent with the rest of the API's `_sec` suffix on numeric fields — `_sec` wins when both supplied). `/v1/audio/eq` band dict accepts `frequency` (alias of `freq`) and `q` (alias of `width_hz`). `/v1/audio/similar` accepts `file_path_b` / `file_url_b` (the "compare two files" reading) as aliases for `reference_file_path` / `reference_file_url`.
- **`/v1/audio/master` mode auto-detect.** `mode` is now optional — inferred from request fields: `reference_path` / `reference_url` set → `mode=reference`; `preset` set → `mode=chain`; neither → 400 with a helpful detail. Schema docstring also clarifies the master endpoint's `preset` (transparent / loud) is a different namespace from the workflow presets listed at `GET /v1/presets`.
- **`POST /v1/presets/{name}` + `POST /v1/pipeline` JSON-body migration.** Both endpoints were still using `Form()` / `File()` — missed by the v1.0.0 spec-first refactor. Now use JSON body with new `PresetRunRequest` + `PipelineRunRequest` schemas; pipeline steps are now a typed `list[{op, params?}]` array instead of a JSON-string blob. **Strict shape change for callers using the old Form/File contract on these two endpoints** — but everyone else's `POST /v1/audio/*` endpoints have been JSON since v1.0.0, so this is converging on the documented spec.
- **Global JSON 500 envelope.** Previously, uncaught non-HTTPException errors returned FastAPI's default plain-text `Internal Server Error` body, which broke downstream clients that parse `response.json()` on every error. A new `@app.exception_handler(Exception)` logs the failure via `audiolla.request` (with traceback) and returns `500 {"detail": "<ExceptionClass>: <message>"}`.
- **Remix linear-gain shorthand.** `/v1/audio/remix` accepts `{stem: 0..1}` (linear gain shorthand) as well as the canonical `{stem: {gain_db, mute}}`. Additive.
- **UVR phantom-output diagnostic.** WARNING log now lists actual tmpdir contents alongside the library's claimed output filenames — easier root-causing when UVR claims an output file that was never written.

### aigate-side

`tests/test_audiolla.sh` doesn't exercise `/v1/audio/{fade,eq,similar,master,remix}`, `/v1/presets/*`, or `/v1/pipeline`, so the test suite stays as-is. No code, config, or doc changes on the aigate side beyond the image tag.

### Files

- `docker-compose.yml` — `psyb0t/audiolla:v1.0.6` → `:v1.0.7`, `psyb0t/audiolla:v1.0.6-cuda` → `:v1.0.7-cuda`.

### Live-verified

- `psyb0t/audiolla:v1.0.7` (sha256:3ea5b7e7…) + `:v1.0.7-cuda` (sha256:dce75632…) pulled.
- aigate-audiolla-1 + aigate-audiolla-cuda-1 recreated, both healthy.
- `tests/test_audiolla.sh` — 14/14 green (CPU + CUDA).

## [v3.12.1] — 2026-06-17

**Bump audiolla v1.0.5 → v1.0.6 — two upstream bug fixes.**

Upstream `psyb0t/audiolla` cut v1.0.5 (no API changes — pytest test infra refresh, engine logging coverage across 25/25 engines, latent bug fixes for UVR `_STEM_RE` regex, UVR phantom-output filter, DeepFilterNet PATH requirement, `Dockerfile.cuda` missing `COPY presets`, pyannote test `num_speakers == 0` accept) followed by v1.0.6 (two bug fixes surfaced by downstream consumers).

### Upstream v1.0.6 fixes

- **`/v1/audio/info`** — was reporting `"ffprobe failed: unknown error"` because the underlying `ffprobe` call used `-v quiet` which muted real stderr too. Now surfaces the actual ffprobe stderr so a caller passing a bad file gets a useful error.
- **`/v1/audio/trim`** — `end_sec` is now optional; omitting it trims to source end. Wire-shape relaxation — old callers still work (passing `end_sec` continues to work the same way); new callers can omit.

No code, config, or behavior changes on the aigate side beyond the image tag.

### Files

- `docker-compose.yml` — `psyb0t/audiolla:v1.0.5` → `:v1.0.6`, `psyb0t/audiolla:v1.0.5-cuda` → `:v1.0.6-cuda`.

### Live-verified

- Both `psyb0t/audiolla:v1.0.6` and `:v1.0.6-cuda` pulled, containers recreated, both healthy.
- `tests/test_audiolla.sh` — 14/14 green (covers `/v1/audio/info` which received the ffprobe-error fix; doesn't exercise `/v1/audio/trim`, so no test rewrite needed for the relaxed wire shape).

## [v3.12.0] — 2026-06-14

**Bump predictalot to v1.0.1 — adds tabular ML, renames FM URL prefix (breaking for direct REST callers).**

Upstream `psyb0t/predictalot` cut its v1.0.0 API-stabilization release followed by a v1.0.1 docs-only patch the same day. aigate ships v1.0.1 directly: it (a) introduces a second model family — supervised tabular ML — alongside the existing foundation time-series stack, (b) layers per-call escape hatches on the FM side, and (c) reorganises the FM URL prefix under `/v1/timeseries/`. v1.0.1 itself is docs-only over v1.0.0 (no source changes, no behavior change — upstream restructured the README into `docs/{timeseries,tabular,mcp,configuration,architecture,accuracy,errors}.md`); we point our links at the new tree. We bump the image, rewrite tests + docs for the new prefix, and propagate the surface description through the MCP fragments.

### Breaking — direct REST callers only

- Every FM forecast / ensemble / models endpoint moves from `/v1/<type>/…` to `/v1/timeseries/<type>/…` upstream. **No redirect compatibility layer ships** in v1.0.0 — old paths return 404. Migration mapping:
  - `/predictalot/v1/univariate/forecast` → `/predictalot/v1/timeseries/univariate/forecast`
  - `/predictalot/v1/multivariate/forecast` → `/predictalot/v1/timeseries/multivariate/forecast`
  - `/predictalot/v1/covariates/past/forecast` → `/predictalot/v1/timeseries/covariates/past/forecast`
  - `/predictalot/v1/covariates/future/forecast` → `/predictalot/v1/timeseries/covariates/future/forecast`
  - `/predictalot/v1/covariates/forecast` → `/predictalot/v1/timeseries/covariates/forecast`
  - `/predictalot/v1/samples/forecast` → `/predictalot/v1/timeseries/samples/forecast`
  - `…/forecast/ensemble` and `…/models` move identically.
- **MCP callers are unaffected** — tool names (`predictalot-forecast_<type>_<model>`, `predictalot-list_<type>_models`, etc.) did not change. Only direct REST callers need to rewrite URLs.

### Added — predictalot v1.0.0 tabular surface

- **`/v1/tabular/*`** — supervised ML over caller-engineered features (engineered indicators, signals, embeddings — predictalot itself does not synthesise features; it fits backends to whatever the caller hands in).
- 9 backends: `lightgbm`, `xgboost`, `hist-gbt`, `random-forest`, `logistic`, `mlp`, `svm-rbf`, `knn`, `naive-bayes`.
- 3 modes each: `direction` (classification), `value` (regression), `quantile`.
- Train + persist + forecast surface — `POST /v1/tabular/train`, `POST /v1/tabular/forecast`, `POST /v1/tabular/forecast/ensemble`, `GET /v1/tabular/backends`, `GET /v1/tabular/models`, `DELETE /v1/tabular/models/{id}`.
- 3 meta-learners — `POST /v1/tabular/train/calibrated` (Platt / isotonic on a held-out time-ordered tail), `POST /v1/tabular/train/stacking` (K-fold OOF + meta-learner), `POST /v1/tabular/train/diversified` (greedy low-correlation candidate selection). Each with a matching `/forecast/<meta>` endpoint.
- Tier-2 cross-backend config: `categoricalFeatures`, `monotonicConstraints`, `classWeight`, `sampleWeight`, `earlyStoppingRounds` / `validationFraction`. Each backend uses what applies and ignores the rest.
- Lazy-loaded — `predictalot.models` imports without pulling in the heavy ML wheels.
- **REST-only in v1.0.0** — upstream has not (yet) registered tabular endpoints as MCP tools. Callers reach the tabular family via direct REST through `/predictalot/v1/tabular/*` only. The 26-tool FM MCP surface is unchanged.

### Added — predictalot v1.0.0 FM escape hatches

- `ForecastConfig.extra` / `SamplesForecastConfig.extra` — per-call dict forwarded to the backend `predict_*` adapter for backend-specific kwargs that don't fit a cross-cutting schema. Backends drop keys they don't understand (forward-compat).
- Ensemble `memberOverrides: {slug → partial-config}` on every FM ensemble request. Each member's override shadows the matching key in the global `config` for that member only — different ensemble members can run with different `contextLength`, `extra`, etc. in a single call. Unknown slugs are silently ignored.

### Files

- `docker-compose.yml` — `psyb0t/predictalot:v0.2.1` → `:v1.0.1`, `psyb0t/predictalot:v0.2.1-cuda` → `:v1.0.1-cuda`.
- `tests/test_predictalot.sh` — all REST paths rewritten from `/v1/<type>/` to `/v1/timeseries/<type>/` (14 occurrences). Header comment block updated to document the new prefix + the existence of the tabular family.
- `README.md` — services-table predictalot row rewritten to call out v1.0.0 + tabular ML. Tools-and-capabilities bullet rewritten too. Curl example bumped to the new prefix.
- `docs/services/predictalot.md` — full surface description rewritten to cover both families + the v0.2.x → v1.0.0 breaking-change call-out. Curl example bumped.
- `docs/testing.md` — predictalot test description updated for the new prefix.
- `litellm/config/mcp/predictalot.yaml` + `predictalot-cuda.yaml` — descriptions appended with a note that the v1.0.0 tabular family is REST-only (not yet MCP-wrapped upstream) so an LLM consulting the MCP catalog knows to use REST for tabular work.

### Live-verified

Both `psyb0t/predictalot:v1.0.1` and `:v1.0.1-cuda` pulled (each ~identical bytes to its `v1.0.0` predecessor — image rebuilt for the tag, no source changes). Containers restarted, `tests/test_predictalot.sh` re-run against the new prefix — 16/16 green (CPU + CUDA). Live REST sanity: old `/v1/univariate/models` → 404, new `/v1/timeseries/univariate/models` → 200 with 5 FM models, `/v1/tabular/backends` → 200 with 9 supervised backends listing `direction`/`value`/`quantile` supportedModes.

---

### Also in this release — merged talkies voices endpoint + proxq filter tightening

Unrelated to predictalot, also bundled into v3.12.0:

#### New endpoint — `GET /v1/audio/voices`

LiteLLM's OpenAI-standard surface only covers `/v1/audio/{transcriptions,speech}`; the upstream talkies API exposes a (non-standard) `GET /v1/audio/voices` voice-catalog listing that LiteLLM does NOT route — so before this release the catalog was only reachable inside the talkies container. Now mcp aggregates CPU + CUDA upstreams, annotates each voice with the matching LiteLLM model alias(es), and surfaces the merged list at the public `/v1/audio/voices` route.

- **`mcp/server.py`** — new `@mcp.custom_route("/v1/audio/voices")` handler. Probes `TALKIES_URL` and `TALKIES_CUDA_URL` (whichever are set — gracefully tolerates either being unconfigured or unreachable; errors are surfaced under an optional top-level `errors` field on the response without failing the call). Builds an `upstream_model → [LiteLLM aliases]` map via `GET /v1/model/info` so each voice ships with the model alias slug a caller plugs into the `model` field on `/v1/audio/speech`. Sort order: kokoro family first, then qwen3-tts, then any others — predictable for clients.
- **`docker-compose.yml`** — `mcp` service gains `TALKIES_URL: ${MCP_TALKIES_URL:-http://talkies:8000}` and `TALKIES_CUDA_URL: ${MCP_TALKIES_CUDA_URL:-http://talkies-cuda:8000}`. Nginx gains a `location = /v1/audio/voices` block proxying to `mcp:8000` **before** the LiteLLM catch-all, so the route reaches mcp directly (with the existing api-zone rate limit, same shape as other passthroughs).

Response shape:

```json
{
  "voices": [
    {
      "voice": "af_alloy",
      "upstream_model": "kokoro-82m",
      "model_aliases": ["local-talkies-cuda-kokoro-tts", "local-talkies-kokoro-tts"],
      "default": false
    },
    {
      "voice": "kevin-the-fuckin-dorkster/kevin-the-fuckin-dorkster",
      "upstream_model": "qwen3-tts-0.6b",
      "model_aliases": ["local-talkies-cuda-qwen3-tts"],
      "default": false
    }
  ]
}
```

A voice that exists on both CPU and CUDA (kokoro family) appears once with **both** aliases in `model_aliases` so the client can pick CPU vs CUDA freely. Voices that only exist on one side (qwen3-tts family, CUDA-only) only carry the relevant CUDA aliases. Default with both talkies CPU + CUDA enabled: **130 voices**.

#### proxq pathFilter tightened — listing endpoints no longer queued

`proxq`'s `pathFilter.patterns` whitelist had `^/v1/audio` as a catch-all — which correctly queued `/v1/audio/{speech,transcriptions,translations}` (inference, slow, queue-friendly) but **also** queued the new `/v1/audio/voices` listing (which is a cheap GET that should be instant). A caller hitting `/q/v1/audio/voices` would receive a `jobId` and have to poll. Narrowed the whitelist to the three explicit inference paths so `/q/v1/audio/voices` falls through to direct pass-through (eventual 404 from LiteLLM — caller should use `/v1/audio/voices` directly):

```
- "^/v1/audio/speech"
- "^/v1/audio/transcriptions"
- "^/v1/audio/translations"
```

#### Verified live

- `GET /v1/audio/voices` (no `/q/` prefix) — **200** with 130-voice merged payload.
- `POST /q/v1/audio/speech` — **200** with `jobId` (still queued correctly).
- `GET /q/v1/audio/voices` — pass-through (no longer queued).

## [v3.11.2] — 2026-06-14

README routing-diagram follow-up to v3.11.1 — three more gaps in the ASCII routing diagram that v3.11.1 didn't catch.

- **Nginx routes block** — no `/piston/` line. Added between `/mailbox/` and `/`.
- **MCP servers block** — `mcp_tools` was listed as exposing `generate_image + generate_tts + search_web` only. The `execute_code` tool (introduced in v3.11.0, gated on `PISTON_URL` being set) is also in `mcp_tools`; appended it + extended the auto-enable trigger to mention piston.
- **LiteLLM providers block** — the llamacpp wrappers (`LLAMACPP=1` / `LLAMACPP_CUDA=1`) — which serve GGUF + vision-VLM weights, notably Surya OCR 2 — were missing. Added two rows between vLLM CUDA and claudebox.

No code, config, or behavior changes.

## [v3.11.1] — 2026-06-14

README-only follow-up — three stale spots missed in the v3.11.0 piston ship.

- **Tools and capabilities bullet list** — piston was missing from the bullets at the top of the README. Added a "Sandboxed code execution" bullet between the agentic-coding-agents entry and the object-storage entry, calling out the nsjail isolation, the Python+Node default, the `PISTON_LANGUAGES` knob for adding more, and the REST + MCP `execute_code` surfaces.
- **Services table piston row** — still mentioned a `piston-pull` sidecar that was dropped in v3.11.0 (pre-bake at build time replaced it) and listed `Python / Node / Bash / Deno / Go / Rust / TypeScript` as the default install when the actual default is just Python + Node. Row rewritten: correct default lang set, pre-bake-at-build-time rationale + the `aigate-internal`-only network model, the build-then-redeploy flow for adding languages, the upstream pkgs staleness note, and the Authorization-header-strip detail.
- **Security section** — top-level Security subsection at line 40 still carried the prior "All containers run with `no-new-privileges`" claim that the lower Network-isolation section had already qualified. Rewrote to match: application containers carry the flag; piston (privileged for nsjail) and tailscale (NET_ADMIN for tun) are the two genuine carve-outs.

## [v3.11.0] — 2026-06-14

New service `piston` (sandboxed multi-language code execution) + a whole-package security/correctness pass triggered by a brutal review across every line of code, every doc, every config. 11 concrete defects found and fixed; 7 broken doc links repaired; supply-chain audit completed.

### New service: piston

[`engineer-man/piston`](https://github.com/engineer-man/piston) — sandboxed multi-language code execution. Unlocks "the LLM writes code, the LLM runs it" workflows for any function-calling model in aigate's catalog. nsjail-based per-execution isolation, hard wall-clock + memory + output caps, network disabled inside sandboxes by default.

**Pre-bake architecture.** Languages are installed at IMAGE BUILD TIME, not runtime. The `piston/Dockerfile` spawns the upstream piston API server during build, POSTs `/api/v2/packages` once per `(language, version)` from `PISTON_LANGUAGES`, then bakes the result into the image. In exchange the runtime container lives on `aigate-internal` ONLY (no outbound network — a popped neighbour container in `aigate-public` can't reach `piston:2000` directly to spawn arbitrary code execution). Adding a language = bump `PISTON_LANGUAGES`, rebuild, redeploy.

Default language set is intentionally minimal: `python=3.12.0,node=20.11.1`. Other languages exist in piston's pkgs index but most are stuck at 2021-2023 versions (Go 1.16, Rust 1.68, Java 15, Ruby 3.0, Swift 5.3). Add via `PISTON_LANGUAGES` if you actually need them; the trade-off is documented in `.env.example`.

**Isolation model.**

```
host
└── piston container (privileged: true) ← needs caps to set up nsjail
    └── nsjail subprocess per execution ← THIS is where the sandbox is
        ├── new user namespace (code runs as uid 65534)
        ├── chroot to minimal language runtime only
        ├── new pid + mount + uts + ipc + net namespaces
        ├── seccomp filters blocking dangerous syscalls
        ├── cgroups: cpu, memory, pids, wall-clock all hard-capped
        └── no /proc, no /sys, no host paths visible
```

`privileged: true` is what piston needs to set up nsjail — not what isolates the code itself. The sandboxing happens in the nsjail subprocess. For aigate's threat model (trusted operator + bearer-auth-gated public endpoint + sandboxed code from LLM agents) this is acceptable. For stronger isolation: dedicated VM or Firecracker-microVM-based execution.

**Auth.** Upstream piston has NO built-in auth. The `/piston/` nginx route gates with `if ($http_authorization != "Bearer ${AIGATE_TOKEN}") { return 401 }`. New `RATELIMIT_PISTON=30r/m` zone + `TIMEOUT_PISTON=2m`. Client `Authorization` header is stripped before the proxy hop (`proxy_set_header Authorization ""`) so `AIGATE_TOKEN` never reaches the piston process.

**MCP tool — `mcp_tools-execute_code`.** Function-callable from any LLM in LiteLLM's catalog via `/mcp/`. Signature: `execute_code(language, source, stdin?, args?) → {language, version, stdout, stderr, exit_code, signal, cpu_time_ms, wall_time_ms, memory_bytes, compile_stderr?, compile_exit_code?}`. The tool resolves the requested `language` against `/api/v2/runtimes` dynamically and dispatches `POST /api/v2/execute`. If the language isn't installed, the error response includes the actual installed list so the LLM can pick again — no hardcoded language list in the tool description (the prior draft lied when default ≠ pre-baked set).

**Tests — 8 cases, all green live.**

- `test_piston_route_requires_auth` — both missing-header AND wrong-token cases return 401 (prior version only tested missing header, would have let a broken nginx `if` regression slip through)
- `test_piston_runtimes_listed` — python + node present in `/api/v2/runtimes`
- `test_piston_python_execute` / `test_piston_node_execute`
- `test_piston_sandbox_no_network` — sandboxed `urllib.urlopen()` fails with NXDOMAIN (verifies `PISTON_DISABLE_NETWORKING` is actually effective at the nsjail layer)
- `test_piston_mcp_tool_registered` / `test_piston_mcp_tool_call`
- `test_piston_e2e_groq_drives_execute_code` — full agentic loop: ask `groq-llama-3.3-70b` to compute SHA-256 of `"aigate-piston-2026"` with the `execute_code` tool in `tools[]`. Verifies (1) LLM emits a `tool_call` with Python source, (2) MCP dispatches to piston, (3) sandbox runs the code, (4) returned hex matches expected `38a24fbf70116be5d8ee0e0cdc66e524472ae9ad99ffa317e44f5b1ecb809121` byte-for-byte.

### Security hardening (brutal-review fallout)

After spawning a full architecture-security review across the whole package, 9 of 12 findings were verified and fixed (2 rejected with documented reasoning, 1 design-by-intent kept but documented).

- **SSRF guard on llamacpp `image_url` fetches.** The wrapper lives on `aigate-internal` and can hostname-reach every other service. Before this fix, a caller authenticated to LiteLLM could pass `image_url.url=http://postgres:5432` (or any internal hostname / loopback / link-local / reserved address) and the wrapper would TCP-connect and base64-encode whatever came back. Now: shared `_net.py` helper resolves the URL's host before issuing the GET and refuses any address in `is_private`, `is_loopback`, `is_link_local`, `is_multicast`, `is_reserved`, or `is_unspecified` ranges. Applied at BOTH call sites — the wrapper's default `image_url` path AND the Surya OCR 2 handler's separate PDF fetch path. Override via `LLAMACPP_WRAP_ALLOW_PRIVATE_IMAGE_URLS=true` for dev/loopback-only deployments.
- **`no-new-privileges:true` added to claudebox, pibox-zai, ollama, ollama-cuda.** README's old claim "all containers run with no-new-privileges:true" was materially false — claudebox and pibox-zai (the two containers that expose shell execution) lacked the flag. Now: all four set it. README is qualified to call out the two genuine exceptions (`piston` needs `privileged:true` for nsjail; `tailscale` needs `NET_ADMIN` for the userspace tun device).
- **Authorization header stripped before piston proxy hop.** `proxy_set_header Authorization "";` inside the `/piston/` nginx block so `AIGATE_TOKEN` never lands in any future piston request log.
- **`resource_manager` cancel-path semaphore release.** If `asyncio.gather(*_UNLOAD_FNS, return_exceptions=True)` is cancelled by an outer cancellation while the hardware semaphore is held, `return_exceptions=True` does NOT suppress the gather's own `CancelledError`. Without explicit handling, the semaphore would stay acquired until LiteLLM restarted. Added `try/except BaseException` wrapping the unload phase: on cancel, release the semaphore via the contextvar path before re-raising. Belt-and-braces against the LiteLLM `async_log_failure_event` hook not always firing on the cancelled-mid-pre-call path.
- **`resource_manager` talkies unload lists synced to provider YAML.** `_TALKIES_CPU_MODELS` was 4 entries vs talkies.yaml's 6 — `nemotron-3.5-asr-0.6b` and `kokoro-82m-nvidia` were silently NOT being evicted under RAM pressure. `_TALKIES_CUDA_MODELS` was 8 vs 14 — same problem extended across the qwen3-tts family (`-0.6b-custom`, `-1.7b`, `-1.7b-custom`, `-1.7b-design`, plus `nemotron-3.5-asr-0.6b` and `kokoro-82m-nvidia`). Both lists now match the provider YAML byte-for-byte.

### Bug fixes

- **`litellm/config/fallbacks.json` — 20+ dead `local-speaches-*` refs + 4 dead `local-qwen3-cuda-tts` refs.** Speaches was migrated to talkies releases ago; the qwen3 alias was renamed to `local-talkies-cuda-qwen3-tts-*`. All fallback chains rewritten to reference live talkies slugs (`local-talkies-whisper-large-v3{,-turbo}`, `local-talkies-{cuda-,}whisper-large-v3{,-turbo}`, `local-talkies-kokoro-tts`, `local-talkies-kokoro-82m-nvidia`, `local-talkies-cuda-qwen3-tts-0.6b/1.7b`). Previously broken fallback legs (silent no-ops) now route to real models.
- **`mcp/server.py` — `search_web` `num_results` unbounded.** A caller could pass `num_results=100000` and slice that many entries off whatever SearXNG returned. Now capped at `max(1, min(num_results, 100))`. No behavior change for normal usage.
- **`mcp/server.py` — `execute_code` description.** Old description hardcoded `python, javascript (node), bash, deno, go, rust, typescript` as "currently available" but default install is python + node only — LLMs reading the description would generate tool calls for languages that don't exist. Description now omits the language list entirely and points the LLM at the runtime error response (which includes the actual installed list) when a wrong language is picked.

### Docs

- **README.md** — Piper / Speaches references (5 places) removed. Provider list updated to current set (Ollama + talkies + vllm-wrap + llamacpp-wrap + sdcpp + audiolla + predictalot). "No new privileges" claim qualified for piston + tailscale carve-outs. Talkies pre-download note updated.
- **`docs/services/piston.md`** — new full service page (quick start, default language set + how to customize with the staleness audit per language, isolation model with threat table, per-execution config knobs, service-level config, nginx route config, REST endpoint reference, MCP tool signature, upstream digest bump procedure).
- **`docs/services/README.md`** — new "Agent execution tooling" section with piston.
- **`docs/README.md`** — top-level "Start here" navigation mentions piston.
- **`docs/services/resource-management.md` → `docs/resource-management.md`** — moved out of `services/` because it's cross-cutting LiteLLM callback logic, not a service.
- **`docs/services-reference.md` + `docs/usage.md` — deleted.** Previously these were redirect stubs after the v3.10.0 docs reorg. Stubs that say "moved" are not docs; every inbound link was rewritten in v3.10.0 anyway.
- **7 broken relative links in `docs/services/*.md` repaired** — `mcp-tools.md` → `../mcp-tools.md` (5 service files), `../.env.example` → `../../.env.example` (audiolla + predictalot), two self-referencing `<svc>.md#configuration` collapsed to bare `#configuration` anchors.

### Files

- `CHANGELOG.md` — this entry.
- `README.md` — service overview + security claim qualification + provider list update.
- `Makefile` — `PISTON=1` profile autodetect block.
- `.env.example` — `PISTON=`, `PISTON_LANGUAGES=python=3.12.0,node=20.11.1` + every piston tunable + the isolation/threat trade-off documentation.
- `docker-compose.yml` — new `piston` service block + new `/piston/` nginx location block + new `RATELIMIT_PISTON` zone + `mcp` service gains `PISTON_URL` + `no-new-privileges:true` added to claudebox, pibox-zai, ollama, ollama-cuda + `proxy_set_header Authorization ""` in `/piston/`.
- `piston/Dockerfile` + `piston/prebake-install.sh` (new) — build-time language pre-bake.
- `mcp/server.py` — new `execute_code` MCP tool gated on `PISTON_URL` + `search_web` num_results cap + `execute_code` description no longer lies.
- `llamacpp/src/llamacpp_wrap/_net.py` (new) — shared SSRF guard helper.
- `llamacpp/src/llamacpp_wrap/server.py` — `_fetch_as_data_url` calls the SSRF guard.
- `llamacpp/src/llamacpp_wrap/handlers/surya.py` — `_maybe_pdf_bytes` calls the SSRF guard before the HTTP PDF fetch.
- `litellm/callbacks/resource_manager.py` — talkies CPU+CUDA unload lists synced to provider YAML + try/except BaseException wrapping the pre_call unload phase to release the semaphore on cancellation.
- `litellm/config/fallbacks.json` — stale `local-speaches-*` / `local-qwen3-cuda-tts` entries rewritten to talkies equivalents.
- `tests/test_piston.sh` (new) — 8 test cases including the LLM-driven SHA-256 e2e.
- `docs/services/piston.md` (new), `docs/services/README.md`, `docs/README.md`, `docs/services/{audiolla,claudebox,librechat,mailbox,mcp,predictalot,searxng,telethon}.md`, `docs/mcp-tools.md` — broken-link repair + content tweaks.
- `docs/services/resource-management.md` → `docs/resource-management.md` — moved (not a service).
- `docs/services-reference.md`, `docs/usage.md` — deleted (stale redirect stubs).
- `.gitignore` — `BRUTAL_REVIEW.md` + `COUNTER_REVIEW.md` added to the dev-doc ignore list.

## [v3.10.0] — 2026-06-13

llamacpp wrapper grows two coupled features for Surya OCR 2: **server-side PDF input** (so clients don't have to per-page-rasterize) and an **auto `--ctx-size` resolver** (so the server uses the model's full 256K trained context instead of being pinned to a hand-tuned 16K). Both work through a new **per-model handler architecture** so future GGUFs (text LLMs, audio VLMs, document models with different stitching rules) can plug in their own orchestration without polluting the general wrapper path.

### Per-model handler architecture

Models opt in by setting `"handler": "<name>"` in their `models.{cpu,cuda}.json` entry. Handlers are Python classes implementing the `Handler` protocol from `llamacpp/src/llamacpp_wrap/handlers/base.py`:

```python
class Handler(Protocol):
    async def handle(
        self,
        *,
        request: Request,
        payload: dict,
        forward: Callable[[dict], Awaitable[Response]],
    ) -> Response | None:
        """Return a Response to short-circuit, or None to fall through
        to the default one-shot proxy path."""
```

The handler receives the inbound request + parsed OpenAI chat completions payload + a `forward(payload)` callable that runs a single `llama-server` round-trip with whatever payload it's given. Handlers can call `forward` 0..N times — once per chunk for modality-aware orchestrators (PDF pagination, audio chunking, etc.).

Registry lives in `handlers/__init__.py` and exposes `get(name) → Handler | None`. Unknown handler names fail at config-load time via the validation in `config.py`. Models without a `handler` field fall through to the default one-shot proxy — every existing or future GGUF model not interested in custom orchestration sees zero behaviour change.

### Surya PDF handler (`handlers/surya.py`)

First handler implementation. Detects PDF input in the OpenAI chat completions payload, rasterizes each page server-side, loops the chat completion per page, and stitches the per-page responses back keyed by Surya's prompt mode.

**PDF detection** — a content item is treated as a PDF when:

- its `image_url.url` is a `data:application/pdf;base64,...` URL, OR
- its `image_url.url` is an `http(s)://...` URL whose fetched body comes back with `Content-Type: application/pdf` (or `.pdf` extension fallback).

**DPI knob** — per-request `dpi_rescale_to` field on the OpenAI body (set via `extra_body` on official SDK clients):

| Value | Behaviour |
|---|---|
| `96` (default) | Cap at 96 DPI. Renders at `min(96, native_dpi)` per page — only downscales, never upscales. |
| `N > 0` | Cap at N DPI. Renders at `min(N, native_dpi)` per page. |
| `-1` | Skip rescaling. Render at the page's native DPI (vector-only pages still fall back to 96). |

`native_dpi` per page is the max DPI of any embedded raster image on that page, probed via `pdfimages -list`. Vector-only pages fall back to 96 DPI so `-1` and the default both produce safe + fast renders on those. Hard cap: 600 DPI. Out-of-range → HTTP 400.

**Prompt-mode detection** — handler matches the user's text content against the 4 trained-in Surya prompts to decide how to stitch:

- **Block OCR** — rejected with HTTP 400 (single-image only; crop client-side first).
- **Full-page OCR** — per-page HTML concatenated, each wrapped in `<div data-page="N">...</div>`.
- **Layout detection** — per-page JSON arrays merged, every entry gains a `"page": N` field.
- **Table recognition** — same as layout.
- **Unknown mode** — plaintext concat with `<!-- page N -->` separators.

**Failure isolation** — one page erroring does NOT abort the whole request. The stitched response gets a `page_errors: [{page, error}, ...]` field so the client can retry just the failed pages.

**Response extra fields** — every PDF response gets `x_surya_pages` (count) and `x_surya_mode` (block / page / layout / table / unknown) at the top level.

### Auto `--ctx-size` resolver

The previous Surya pin was `--ctx-size 16384`. Surya OCR 2 is a Qwen3.5-text hybrid Mamba+attention model whose `config.json` declares `max_position_embeddings=262144` (256K trained context) — but with only 6 full-attention layers (every 4th of 24, `full_attention_interval=4`) and very narrow KV heads (`num_key_value_heads: 2`, `head_dim: 256`). Per-token KV cost works out to **~12 KiB**. On an RTX-class card with even 10 GB free, the full 256K trained context fits with room to spare. Pinning to 16K was leaving the model badly under-utilised and risking truncation on big PDFs from the new server-side PDF handler.

Model entries can now pass the literal string `"auto"` instead of an integer to `--ctx-size`:

```jsonc
"llama_server_args": [
  "--ctx-size", "auto",
  "--parallel", "4",
  "--n-gpu-layers", "999"
]
```

At every model spawn (cold boot, sibling-eviction swap, post-idle-TTL reload) the supervisor:

1. **Probes free memory** — `nvidia-smi --query-gpu=memory.free` on CUDA, `MemAvailable` from `/proc/meminfo` on CPU.
2. **Subtracts** the model's declared weights footprint + a safety margin (CUDA-graph alloc, batch buffers, Mamba-SSM state, mmproj scratch).
3. **Divides** the remaining headroom by the per-token KV cache cost.
4. **Caps** at the model's trained max (`max_ctx_size` per-model field).
5. **Floors** at `LLAMACPP_WRAP_CTX_FLOOR` (default 16384).
6. **Rounds down** to the nearest multiple of 1024.

Logs every choice at INFO level:

```
ctx-size auto math: free=10.19 GiB, weights=2.00 GiB, safety=1.00 GiB,
                    kv_per_tok=12288 B → headroom for 628053 tokens;
                    model_max=262144, floor=16384, chosen=262144
ctx-size auto → 262144 (model_id=datalab-to/surya-ocr-2-gguf)
spawning: /app/llama-server -m ... --ctx-size 262144 --parallel 4 ...
```

For Surya on the live aigate stack (sharing the GPU with talkies-cuda + sdcpp-cuda etc.) the resolver picks the **full 262144 trained max** on the first call — verified live.

New per-model fields (all optional):

| Field | Default | Surya pin | Description |
|---|---|---|---|
| `max_ctx_size` | 16384 | 262144 | Trained ceiling — going past wastes memory without benefit. |
| `kv_bytes_per_token` | 16384 (16 KiB) | 12288 | Per-token KV cost. For hybrid Mamba+attention models count only full-attention layers. **Surya math**: 6 full-attn × 2 KV heads × 256 head_dim × 2 (K+V) × 2 B fp16 = 12288 B/token. |
| `weights_estimate_bytes` | sum of GGUF + mmproj on-disk size | 2 GiB | Total memory consumed by weights when loaded. Padding above on-disk size accounts for CUDA-side alignment + scratch. |

New env knobs (operator overrides on the wrapper container):

| Variable | Default | Description |
|---|---|---|
| `LLAMACPP_WRAP_CTX_FLOOR` | `16384` | Smallest ctx the resolver will ever pick. |
| `LLAMACPP_WRAP_CTX_SAFETY_MARGIN_BYTES` | `1073741824` (1 GiB) | Subtracted from probed free memory before dividing by KV cost. Bump on shared GPUs; trim on dedicated cards. |

Failure modes (all explicit, all logged):

- **No `nvidia-smi` / no `/proc/meminfo`** → falls back to `min(max_ctx_size, max(floor*2, floor))`.
- **`nvidia-smi` returns unparseable output / times out** → same.
- **Probed free memory is below weights + safety budget** → falls back to `floor`; spawn proceeds, llama-server fails loudly at load if even that won't fit.
- **Bad `kv_bytes_per_token` on the model entry (zero / negative)** → falls back to the conservative 16 KiB/token estimate.

### Wrapper image + config changes

- `llamacpp/Dockerfile.{cpu,cuda}` — `poppler-utils` added to apt install (`pdftoppm` + `pdfimages` + `pdfinfo`).
- `llamacpp/models.{cpu,cuda}.json` — Surya entry now has `"handler": "surya"`, `"max_ctx_size": 262144`, `"kv_bytes_per_token": 12288`, `"weights_estimate_bytes": 2147483648`. The `--ctx-size 16384` arg changed to `--ctx-size auto`.
- `llamacpp/src/llamacpp_wrap/config.py` — registry validation accepts `handler`, `max_ctx_size`, `kv_bytes_per_token`, `weights_estimate_bytes` (all optional, type-checked).
- `llamacpp/src/llamacpp_wrap/server.py` — `_handle_json_request` looks up the handler after `SUPERVISOR.ensure()` and short-circuits via `handler.handle(...)` if one exists. New helper `_proxy_one_payload` is what's handed to the handler as the `forward` callable.
- `llamacpp/src/llamacpp_wrap/supervisor.py` — `_resolve_auto_ctx_size()` runs over `llama_server_args` before `cmd` is built; `_compute_ctx_size()` does the math; `_probe_free_cuda_vram_bytes()` + `_probe_free_ram_bytes()` + `_gguf_size_on_disk()` are the probes. New env knobs read via `_ctx_floor()` + `_ctx_safety_margin_bytes()`.
- `llamacpp/src/llamacpp_wrap/handlers/{__init__,base,surya}.py` — new module tree, ~500 LOC total.

### Tests — 12 → 23 cases

`tests/test_llamacpp.sh` grew 11 new test functions (5 PDF + 1 auto-ctx, per variant where applicable). 6 PDF tests on CUDA all verified passing. The auto-ctx test asserts the resolver log line landed + the chosen value is ≥ floor + a multiple of 1024.

New fixture: `tests/.fixtures/doc-multipage.pdf` — A4, 3 pages, each with a unique known line. 1.8 KB.

### Docs

- `docs/services/llamacpp.md` — two new sections + one table-row update:
  - **PDF input — server-side handling** — detection rules, `dpi_rescale_to` knob, 3 worked curl examples, the client-side pre-rasterization path (still supported), and the per-model handler architecture (how to add a handler for another document model).
  - **Auto-sizing `--ctx-size` to available memory** — the resolver math, 3 per-model fields, the 2 env knobs (per-variant via the same `LLAMACPP_*` / `LLAMACPP_CUDA_*` pattern as other tunables), fallback behaviour, spawn-time log format.
  - The "Which mode for which job" table — **Multi-page PDF** row now mentions the server-side path FIRST (drop a PDF in `image_url.url`), with client-side pre-rasterization listed as the fallback for fine-grained control.
- `README.md` — llamacpp CUDA row mentions both the server-side PDF support and the `dpi_rescale_to` knob.
- `docs/providers.md` — both `local-llamacpp-surya-ocr-2` and `local-llamacpp-cuda-surya-ocr-2` alias rows now mention PDF input, `dpi_rescale_to`, the 256K trained context, and auto-ctx-size.
- `docs/services/README.md` — services-index blurb for llamacpp gained the PDF + auto-ctx-size summary.
- `.env.example` — documents `LLAMACPP_CTX_FLOOR` + `LLAMACPP_CTX_SAFETY_MARGIN_BYTES` (CPU) and `LLAMACPP_CUDA_CTX_FLOOR` + `LLAMACPP_CUDA_CTX_SAFETY_MARGIN_BYTES` (CUDA).
- `docker-compose.yml` — both `llamacpp` and `llamacpp-cuda` service blocks gained the env wiring `LLAMACPP_WRAP_CTX_FLOOR: ${LLAMACPP{,_CUDA}_CTX_FLOOR:-}` and the safety-margin twin, so operator overrides in `.env` actually reach the wrapper process inside the container.

## [v3.9.2] — 2026-06-13

Docs reorganisation. Two monolithic files were growing unmanageable — `docs/services-reference.md` had hit ~960 lines (18 service sections in one file) and `docs/usage.md` ~780 lines (15 task-keyed sections, each duplicating context the reference file already had). Every new feature was widening both files in parallel. Split into per-feature pages under `docs/services/`.

No production code changes. Pure documentation restructure.

### New structure

- [`docs/README.md`](docs/README.md) — top-level docs index ("start here" + "by service" + "by topic" navigation).
- [`docs/services/README.md`](docs/services/README.md) — services index, organised by purpose (local inference / cloud gateway / storage / UIs / comms / network / cross-cutting).
- [`docs/services/<name>.md`](docs/services/) — **one file per service**, combining what used to be split between `services-reference.md` (deep reference: endpoints, models, config, internals) and `usage.md` (curl recipes, examples) into a single page. 18 files total:

  | Service | New page |
  |---|---|
  | LiteLLM gateway | [`services/litellm.md`](docs/services/litellm.md) |
  | LibreChat | [`services/librechat.md`](docs/services/librechat.md) |
  | Claudebox + pibox-zai agentic coding | [`services/claudebox.md`](docs/services/claudebox.md) |
  | MCP tools (media gen + search) | [`services/mcp.md`](docs/services/mcp.md) |
  | hybrids3 | [`services/hybrids3.md`](docs/services/hybrids3.md) |
  | browser | [`services/browser.md`](docs/services/browser.md) |
  | searxng | [`services/searxng.md`](docs/services/searxng.md) |
  | sd.cpp | [`services/sdcpp.md`](docs/services/sdcpp.md) |
  | vllm / vllm-cuda | [`services/vllm.md`](docs/services/vllm.md) |
  | llamacpp / llamacpp-cuda — Surya OCR 2 + future GGUF VLMs | [`services/llamacpp.md`](docs/services/llamacpp.md) |
  | talkies / talkies-cuda — ASR + TTS | [`services/talkies.md`](docs/services/talkies.md) |
  | audiolla / audiolla-cuda — audio production | [`services/audiolla.md`](docs/services/audiolla.md) |
  | predictalot | [`services/predictalot.md`](docs/services/predictalot.md) |
  | mailbox — IMAP + SMTP gateway | [`services/mailbox.md`](docs/services/mailbox.md) |
  | telethon — Telegram REST + MCP | [`services/telethon.md`](docs/services/telethon.md) |
  | cloudflared | [`services/cloudflared.md`](docs/services/cloudflared.md) |
  | tailscale | [`services/tailscale.md`](docs/services/tailscale.md) |
  | Resource management (cross-cutting) | [`services/resource-management.md`](docs/services/resource-management.md) |

### Old files now redirect

Both `docs/services-reference.md` and `docs/usage.md` were trimmed to a single table mapping each old section to its new home under `docs/services/`. Existing inbound links to those two files keep working via the redirects; deep links to specific section anchors (`#cloudflared-optional` etc.) need to migrate to the per-service file.

### README + providers.md link updates

- `README.md` — every link that pointed at `docs/services-reference.md#<section>` or `docs/usage.md#<section>` was rewritten to point at the corresponding `docs/services/<name>.md`.
- `docs/providers.md` — the Surya OCR alias row's "see [docs/usage.md#document-ocr-surya-2-via-llamacpp]" pointer rewritten to point at `docs/services/llamacpp.md`.

### Out of scope (intentional)

- `docs/providers.md`, `docs/testing.md`, `docs/mcp-tools.md` were already focused single-purpose files — left in place at the top level.
- Historical CHANGELOG entries that mention old paths (`docs/services-reference.md` etc.) are NOT rewritten — they document what happened at the time of each past release.

## [v3.9.1] — 2026-06-13

Follow-up to v3.9.0 — exercises and documents the two Surya OCR 2 modes the original release shipped but did not test (layout detection + table recognition), drops the test runner's PDF DPI to Surya's training-time default, and adds full Surya usage docs across README + `docs/services-reference.md` + `docs/usage.md` + `docs/providers.md`.

No production code changes — the `llamacpp/` wrapper, model registries, compose services, LiteLLM provider configs, and resource_manager wiring are byte-identical to v3.9.0. Pure tests + docs work.

### Tests — 8 → 12 cases (covers all 4 Surya prompt modes now)

- `tests/test_llamacpp.sh` — added 4 new test cases (2 per variant): `layout` (asserts non-empty JSON array of `{label, ...}` objects, surfaces the first label) and `table_rec` (asserts ≥1 `Row` + ≥1 `Col` label entry in the JSON response).
- New `_llamacpp_ocr_call` `task=block|page|layout|table_rec` dispatcher selects the right verbatim Surya prompt string per task — adding a future 5th mode is a one-line case-statement extension.
- All four trained-in upstream prompts are now exercised at test time:
  - block OCR — `OCR this block image to HTML.`
  - full-page OCR — `OCR this image to HTML. Each block is a div with data-label and data-bbox (x0 y0 x1 y1, normalized 0-1000).`
  - layout detection — `Output the layout of this image as JSON. Each entry is a dict with "label", "bbox", and "count" fields. Bbox is x0 y0 x1 y1, normalized 0-1000.`
  - table recognition — `Output the table rows then columns as JSON. Each entry is a dict with "label" ("Row" or "Col") and "bbox" (x0 y0 x1 y1, normalized 0-1000).`

### New fixture — `tests/.fixtures/table.pdf`

A4, 3-row × 3-col bordered table (City / Country / Population). 1.4 KB. Generated reproducibly via fpdf2 — see `_llamacpp_test_table_rec` for the rasterization + assertion logic.

### PDF rasterization DPI — 200 → 96

The v3.9.0 test runner rasterized PDFs at 200 DPI via `pdftoppm -r 200`. The vision encoder's token count scales ~quadratically with image area, so 200 DPI produces ~3940 prompt tokens per A4 page versus ~1100 at 96 DPI — and CPU encode time blew up to ~7+ min per page accordingly. 96 DPI is Surya's training-time default; lowering to it gave a ~4× speedup with **no quality loss** on the synthetic fixtures (`pdf_ocr` still asserts `quick brown fox`; `layout` still surfaces a valid label; `table_rec` still finds Row + Col labels). Going below 96 DPI starts breaking small text recognition — keep `-r 96` as the floor.

### Throughput — what to actually expect, measured

Measured end-to-end through LiteLLM → wrapper → `llama-server` on the actual test fixtures (single RTX-class GPU + 4-core CPU container):

| Task | CUDA | CPU |
|---|---|---|
| Captcha OCR (400×120) | ~3 s | ~24 s |
| URL-fetched captcha (hybrids3 → wrapper fetch) | ~3 s | ~24 s |
| Full-page OCR (A4 @ 96 DPI, ~1100 tokens) | ~6-12 s | ~2-3 min |
| Layout detection (A4 @ 96 DPI) | ~5-10 s | ~2 min |
| Table recognition (table PDF @ 96 DPI) | ~3-6 s | ~2 min |

CPU is fine for batch / overnight document processing and for small images (captchas, signature crops, single-line clips). Interactive A4-page work needs CUDA.

### Docs — full Surya usage section across 4 files

- `README.md` — service-overview rows for both llamacpp variants now mention the **4 trained-in prompts** and the **per-hardware performance reality** ("~3 s CUDA / ~24 s CPU" for small images; "~6-12 s CUDA / ~2-3 min CPU" for A4 pages).
- `docs/services-reference.md` — full new "llamacpp / llamacpp-cuda" section after the vllm section. Includes:
  - "Default model — Surya OCR 2" with a 4-row table of the verbatim training-time prompts and their output shapes (block OCR / full-page OCR / layout detection / table recognition).
  - "Image input — data URLs OR http(s)" — documents the wrapper's URL-fetch path, the 32 MB / 30 s safety bounds, redirect follow behaviour, and the data: pass-through.
  - "Throughput — what to expect" with per-hardware (CUDA + CPU) per-task wall-clock tables and a "DPI sweet spot" subsection.
  - "Configuration" with every `LLAMACPP_*` / `LLAMACPP_CUDA_*` tunable.
  - "Adding a new model" 4-step recipe (edit JSON → bring stack up → LiteLLM provider entry → resource_manager group if needed).
- `docs/usage.md` — full new "Document OCR (Surya 2 via llamacpp)" section after the embeddings examples. Includes **4 worked curl examples** — one per Surya prompt mode — with the exact JSON / HTML output shape inline. Plus a "which slug should I pick" picker table, a PDF rasterization recipe at 96 DPI, and a pointer to the upstream `surya-ocr` Python lib as an alternative orchestration layer.
- `docs/providers.md` — 2 new tables (CPU + CUDA) with the 4 prompt strings spelled out inline on the model row.

## [v3.9.0] — 2026-06-13

New service: **`llamacpp` / `llamacpp-cuda`** — a supervised `llama-server` wrapper that mirrors the `vllm-wrap` lifecycle surface (`/v1/chat/completions`, `/v1/completions`, `/v1/embeddings`, `/api/ps`, `DELETE /api/ps/{model_id}`, `POST /unload`) but serves GGUF weights and **supports vision models via `mmproj`**. First model shipped: **Surya OCR 2** (`datalab-to/surya-ocr-2-gguf`), Qwen3-VL-style ~650M-param document model — does OCR / layout / table-recognition through one VLM.

Why a second backend (vs just adding to `vllm-wrap`): vllm-CPU's vision-VLM support is weak, and even on GPU the Surya GGUF is the upstream-blessed inference target. llama.cpp does Qwen3-VL-class models cleanly on both CPU and GPU.

### What's new

- **Two wrapper services** — `llamacpp` (CPU, `LLAMACPP=1`) and `llamacpp-cuda` (NVIDIA, `LLAMACPP_CUDA=1`). Base images pinned by digest: `ghcr.io/ggml-org/llama.cpp:server@sha256:7d02b045...` and `:server-cuda@sha256:841b199a...` (upstream build `b9603`, rev `ba1df050f3dc78...`). Lazy load on first request, idle TTL unload, single-resident-model-at-a-time enforced by a Python supervisor (~750 LOC, mirrors `vllm-wrap` 1-for-1).
- **`llamacpp-pull` sidecar** — runs once per stack-up, downloads every HF repo referenced by `llamacpp/models.{cpu,cuda}.json` (union) via `huggingface-cli download --local-dir` so weights live on disk in the flat `models/<org>/<repo>/<files>` layout (real files, no blobs/snapshots dedup — other services can bind-mount the same store and load weights directly). The wrapper containers `depends_on: condition: service_completed_successfully`. The wrapper itself runs with `HF_HUB_OFFLINE=1` so it never touches the network at runtime.
- **First model: Surya OCR 2** (`datalab-to/surya-ocr-2-gguf`, revision `6a3a4c30e5e74...`). Pulls the main GGUF + the vision projector (`surya-2-mmproj.gguf`) + tokenizer/chat-template/config files. CPU registry pins `--n-gpu-layers 0`; CUDA registry pins `--n-gpu-layers 999`.
- **HTTP-URL → data-URL rewriting in the wrapper proxy.** `llama-server`'s `mtmd` vision pipeline accepts `data:` URLs only — it does NOT fetch `http(s)://` URLs from the OpenAI `image_url.url` field. The wrapper transparently fetches any `http(s)://` URL, base64-encodes the body, and rewrites the field in place before forwarding. 32 MB cap per image, 30 s fetch timeout, follow_redirects on. Pure data URLs and anything else pass through untouched.

### LiteLLM wiring

- New provider files:
  - `litellm/config/providers/llamacpp.yaml` → `local-llamacpp-surya-ocr-2` (chat mode)
  - `litellm/config/providers/llamacpp-cuda.yaml` → `local-llamacpp-cuda-surya-ocr-2` (chat mode)
- `litellm/build-config.py` — new active-provider entries `("llamacpp", ...)` and `("llamacpp-cuda", ...)`.
- `litellm/callbacks/resource_manager.py` — two new resource groups, `cpu-llamacpp` and `cuda-llamacpp`. Prefix matching is order-sensitive (CUDA prefix checked before CPU since `local-llamacpp-cuda-` is a strict superset of `local-llamacpp-`). Sibling eviction now covers the new groups — when something else needs the GPU (LLM / image gen / TTS / ASR / vllm-cuda chat), llamacpp-cuda gets `DELETE /api/ps/surya-ocr-2` first.

### Wire-up + ops

- `docker-compose.yml` — 3 new service blocks. Shape mirrors `vllm` / `vllm-cuda` / `vllm-pull` exactly (same env-var pattern, same healthcheck, same volume layout, same network membership). New env vars: `LLAMACPP_WRAP_*` (inside containers) and operator-facing `LLAMACPP_*` / `LLAMACPP_CUDA_*` (TTL / sweeper interval / load timeout / request timeout / log level / preload). New data-dir override: `DATA_DIR_LLAMACPP` (defaults to `${DATA_DIR}/llamacpp`).
- `Makefile` — `LLAMACPP=1` / `LLAMACPP_CUDA=1` profile autodetect blocks added next to the `VLLM=` / `VLLM_CUDA=` ones.
- `.env.example` — full new section documenting both flags + every tuning knob + `DATA_DIR_LLAMACPP` with the "flat HF-repo layout shared between CPU + CUDA variants" rationale.

### Tests

- `tests/test_llamacpp.sh` — 8 new test cases (4 per variant): `models_list`, `captcha_ocr` (data: URL path), `pdf_ocr` (PDF rasterized via `pdftoppm`, full-page prompt), `url_captcha` (full hybrids3 upload → presign → URL fetch by wrapper → cleanup lifecycle). All 8 verified passing end-to-end through the LiteLLM router → wrapper supervisor → `llama-server` → GGUF VLM path.
- Two new fixtures:
  - `tests/.fixtures/captcha.png` — 400×120 PNG with the literal text `AIGATE2026` rendered with mild captcha-style distortion (per-glyph jitter, sparse speckle, two light line-strokes). 18 KB.
  - `tests/.fixtures/doc.pdf` — A4, 2 lines of known prose (`The quick brown fox jumps over the lazy dog.` + `Surya OCR fixture line two: 0123456789.`). 1 KB.
- **Surya prompts are training-time contracts** — the test passes the exact upstream strings (`OCR this block image to HTML.` for crops; `OCR this image to HTML. Each block is a div with data-label and data-bbox (x0 y0 x1 y1, normalized 0-1000).` for full pages). Paraphrasing flips the output mode (the model emits a layout-JSON instead of OCR-HTML when given a generic "transcribe this" prompt).

## [v3.8.1] — 2026-06-09

Docs-only sync for v3.8.0. No behaviour change, no image-pin change, no LiteLLM config change. The v3.8.0 commit shipped the actual code change (audiolla v1.0.5, talkies v0.9.0, nine new LiteLLM model entries) but left the prose docs pinned to the older talkies versions / older model lists. This release pulls the docs forward.

### Files

- `README.md`: services overview table — talkies CPU row updated from `psyb0t/talkies:v0.3.0` (3 Whisper variants + canary-180m + kokoro) to `psyb0t/talkies:v0.9.0` (6 models — adds `nemotron-3.5-asr-0.6b` and `kokoro-82m-nvidia`, drops the long-removed `distil-whisper-large-v3`). Talkies CUDA row updated from `v0.3.0-cuda` to `v0.9.0-cuda` (14 models — adds the full Qwen3-TTS line: Base 0.6B + Base 1.7B + CustomVoice 0.6B + CustomVoice 1.7B + VoiceDesign 1.7B).
- `docs/providers.md`: talkies CPU + CUDA tables grow rows for every new model. CPU gains `local-talkies-nemotron-3.5-asr-0.6b` + `local-talkies-kokoro-82m-nvidia`. CUDA gains `local-talkies-cuda-nemotron-3.5-asr-0.6b`, `local-talkies-cuda-kokoro-82m-nvidia`, and the four Qwen3-TTS mode slugs (Base 1.7B, CustomVoice 0.6B, CustomVoice 1.7B + emotion, VoiceDesign 1.7B). Header lines updated from `v0.3.0` to `v0.9.0`.
- `docs/services-reference.md`: talkies section header updated from `v0.4.0 / v0.4.0-cuda` to `v0.9.0 / v0.9.0-cuda`. "6 models / 14 models" counts now stated explicitly. Model bullet list reorganised — CPU bullets gain nemotron-3.5-asr + kokoro-82m-nvidia; CUDA bullets reorganised into a "Qwen3-TTS family" sub-section that documents how `voice` and `instructions` semantics shift per mode, plus PCM streaming + per-request sampling controls.
- `docs/usage.md`: Transcription model list gains `local-talkies-nemotron-3.5-asr-0.6b` (CPU + CUDA). Text-to-speech section grows three new curl examples (Kokoro ONNX, Qwen3-TTS CustomVoice + emotion, Qwen3-TTS VoiceDesign) and the TTS model bullet list is reorganised into Kokoro / Qwen3-TTS families with per-mode `voice` + `instructions` semantics. Sampling-controls and PCM-streaming knobs are now mentioned in this doc too.
- `docs/testing.md`: model-count assertion line updated — "CPU: 4 ASR + Kokoro; CUDA: 7 ASR + Kokoro" → "CPU: 4 ASR + 2 Kokoro = 6 models; CUDA: 7 ASR + 2 Kokoro + 5 Qwen3-TTS = 14 models".
- `.env.example`: `TALKIES=` / `TALKIES_CUDA=` doc comments rewritten to describe the new model set (nemotron, kokoro-82m-nvidia, full Qwen3-TTS line with per-mode notes). New optional knob `TALKIES_QWEN3_STREAM_CHUNK_SIZE` (default `8`) documented for PCM streaming chunk size.

## [v3.8.0] — 2026-06-09

Bump audiolla **v1.0.3 → v1.0.5** (both CPU and CUDA) and talkies **v0.5.0 → v0.9.0** (both CPU and CUDA). Both jumps add user-visible engines on the upstream side, so the LiteLLM provider configs grow nine new model entries (no MCP-side changes — talkies is non-MCP).

### audiolla v1.0.3 → v1.0.5

Patch-level — no API changes. Both upstream releases are pure additive / bugfix:

- **v1.0.4** — `/v1/audio/enhance/deepfilter` no longer 400s on the first call after boot. The `is_deepfilter_engine` predicate AND'd `hasattr(engine, '_df_state')`, but `_df_state` is set lazily inside `_load_sync` on first inference, so the handler rejected the request before the engine could load. Predicate now checks only the public `enhance` method. Plus a structured-logging rewrite — single `audiolla.logging.configure()` init path, line-delimited JSON, `LOG_LEVEL` env var, `X-Request-Id` correlation both directions, per-request summary level-scaled to status code (DEBUG `/healthz`, INFO 2xx/3xx, WARN 4xx, ERROR 5xx).
- **v1.0.5** — UVR `_STEM_RE` regex updated for the newer `audio-separator` filename format, plus a phantom-output filter (model reports files it never wrote — pre-fix the wrapper returned "model produced no output files" even when separation succeeded). DeepFilterNet runtime needs `git` on PATH. `Dockerfile.cuda` was missing `COPY presets`. Pyannote test now accepts `num_speakers == 0` on synthetic input. 25/25 engines now log inference start / done with size + duration_ms + warn / exception on every raise. Replaces 71 bash `e2e_*.sh` with 83 pytest files (479 functions); CUDA suite 470 passed, 9 skipped.

### talkies v0.5.0 → v0.9.0

Four minor versions, all wire-compatible with v0.5.0 — no breaking changes. New engines:

- **v0.6.0** — New TTS slug `kokoro-82m-nvidia` (NVIDIA's TensorRT-friendly ONNX export of Kokoro-82M, Apache-2.0). Same 40-voice catalog, same wire shape, served via ONNXRuntime against the ONNX export + espeak-ng G2P. No PyTorch on the inference hot path. Plus `instructions` field for Qwen3-TTS — passed through to `faster-qwen3-tts` as `instruct`. Voices without a sibling `.txt` transcript now fall back to x-vector-only mode (with a warning) instead of returning 400. Integration test harness self-spawns its own `--rm --gpus all` container per test file.
- **v0.7.0** — PCM streaming for Qwen3-TTS. `response_format="pcm"` against a `qwen3_tts` model now streams the raw PCM body via HTTP/1.1 chunked transfer-encoding instead of buffering the full utterance. First-audio latency drops from ~3-8 s to ~200-700 ms. New env var `TALKIES_QWEN3_STREAM_CHUNK_SIZE` (default 8) controls codec-steps-per-chunk. Plus a supply-chain bump-on-mutation Makefile workflow (`pkg-*` targets call `scripts/bump_exclude_newer.sh` before any uv operation).
- **v0.8.0** — Full Qwen3-TTS mode coverage. Four new model slugs covering all three upstream operational modes:

  | Slug | Mode | `voice` semantics | `instructions` semantics |
  |---|---|---|---|
  | `qwen3-tts-1.7b` | Base 1.7B voice cloning | reference-WAV path | (unused) |
  | `qwen3-tts-0.6b-custom` | CustomVoice 0.6B | 9 preset speakers (Vivian / Serena / Uncle_Fu / Dylan / Eric / Ryan / Aiden / Ono_Anna / Sohee) | (unused) |
  | `qwen3-tts-1.7b-custom` | CustomVoice 1.7B + emotion | same 9 preset speakers | emotion string ("happy" / "sad" / …) |
  | `qwen3-tts-1.7b-design` | VoiceDesign 1.7B | sentinel `"design"` | natural-language description ("a young energetic female voice") |

  Mode is implicit in the model slug; the OpenAI wire format stays pure. Per-request sampling controls as OpenAI extras (`temperature`, `top_k`, `top_p`, `repetition_penalty`, `max_new_tokens`, `do_sample`, `language`) via `extra_body` on official OpenAI SDKs; out-of-range returns 422.
- **v0.9.0** — New multilingual ASR via `mudler/parakeet.cpp` (C++17 / ggml). First slug shipped: `nemotron-3.5-asr-0.6b` (NVIDIA Nemotron-3.5-ASR-Streaming-0.6B, OpenMDW-1.1, 40+ locales, WER-0 against NeMo). Runs CPU-only in both images at this stage; returns per-word timestamps + confidence and synthesises Whisper-style segments via silence-gap grouping so `verbose_json` matches OpenAI's shape. Plus a latent v0.8.0 GPU drain barrier bugfix — sibling eviction returned before async CUDA dealloc finished, so the next backend's load could race the still-freeing pool and OOM on a tight GPU.

### Files

- `docker-compose.yml`: image pins bumped — `psyb0t/audiolla:v1.0.3` → `v1.0.5`, `v1.0.3-cuda` → `v1.0.5-cuda`, `psyb0t/talkies:v0.5.0` → `v0.9.0`, `v0.5.0-cuda` → `v0.9.0-cuda`. Comment line above each talkies block updated to match.
- `litellm/config/providers/talkies.yaml`: two new entries.
  - `local-talkies-nemotron-3.5-asr-0.6b` (audio_transcription)
  - `local-talkies-kokoro-82m-nvidia` (audio_speech)
- `litellm/config/providers/talkies-cuda.yaml`: seven new entries.
  - `local-talkies-cuda-nemotron-3.5-asr-0.6b` (audio_transcription)
  - `local-talkies-cuda-kokoro-82m-nvidia` (audio_speech — ONNXRuntime variant of kokoro-82m)
  - `local-talkies-cuda-qwen3-tts-1.7b` (audio_speech — Base mode)
  - `local-talkies-cuda-qwen3-tts-0.6b-custom` (audio_speech — CustomVoice 9-preset)
  - `local-talkies-cuda-qwen3-tts-1.7b-custom` (audio_speech — CustomVoice + emotion)
  - `local-talkies-cuda-qwen3-tts-1.7b-design` (audio_speech — VoiceDesign)
  - The pre-existing `local-talkies-cuda-qwen3-tts` (= `qwen3-tts-0.6b`) is preserved unchanged for backward compatibility.

### End-to-end smoke-test against the live aigate stack

All four containers came up healthy on the new pins. The new model entries were verified through the LiteLLM-routed HTTP endpoints (not direct container ports) so the full request path — LiteLLM router → talkies backend → engine — is exercised:

| Model | Endpoint | Result |
|---|---|---|
| `local-talkies-whisper-large-v3-turbo` (existing, regression check) | `/v1/audio/transcriptions` | 200 — "You are just a line of code." |
| `local-talkies-nemotron-3.5-asr-0.6b` (NEW) | `/v1/audio/transcriptions` | 200 — same text + word-level timestamps + `verbose_json` shape |
| `local-talkies-cuda-nemotron-3.5-asr-0.6b` (NEW) | `/v1/audio/transcriptions` | 200 — same |
| `local-talkies-kokoro-tts` (existing, regression check) | `/v1/audio/speech` | 200, 120 KB WAV |
| `local-talkies-kokoro-82m-nvidia` (NEW) | `/v1/audio/speech` | 200, 101 KB WAV |
| `local-talkies-cuda-kokoro-82m-nvidia` (NEW) | `/v1/audio/speech` | 200, 114 KB WAV |
| `local-talkies-cuda-qwen3-tts-1.7b` (NEW Base) | `/v1/audio/speech` voice=`alloy` | 200, 100 KB WAV |
| `local-talkies-cuda-qwen3-tts-0.6b-custom` (NEW) | `/v1/audio/speech` voice=`Vivian` | 200, 54 KB WAV |
| `local-talkies-cuda-qwen3-tts-1.7b-custom` (NEW) | `/v1/audio/speech` voice=`Vivian` instructions=`happy` | 200, 96 KB WAV |
| `local-talkies-cuda-qwen3-tts-1.7b-design` (NEW) | `/v1/audio/speech` voice=`design` instructions=`a young energetic female voice` | 200, 65 KB WAV |

### One first-boot snag worth knowing about

When the CPU `talkies` container does its first prefetch of `kokoro-82m-nvidia`, the HF CDN connection can hang in `CLOSE_WAIT` partway through the 21-file snapshot — leaving the on-disk dir half-populated (large `.onnx` file present, smaller files like `voices.txt` / `phone-zh.fst` / `.gitattributes` missing). On the next container start, the entrypoint sees the non-empty dir, prints `cached: kokoro-82m-nvidia`, and moves on — but the model load then fails at runtime with `503 no voices found in /data/models/kokoro-82m-nvidia/voices.txt — snapshot may not have been prefetched`. Fix: `docker exec --user root aigate-talkies-1 rm -rf /data/models/kokoro-82m-nvidia` and restart the service; the retry pulled all 21 files in 11 s.

## [v3.7.1] — 2026-06-08

Bump audiolla v1.0.1 → **v1.0.3**. Upstream shipped two patch releases that fix the exact issues that surfaced while smoke-testing v3.7.0's text-to-audio generators against the live aigate stack:

- **v1.0.2** — `HF_HUB_OFFLINE` default flipped to `0`. The previous image baked it to `1`, which refused even the lazy-download path used by every audio engine that pulls weights from the Hub on first request (`audioldm2`, `stable-audio-open`, `musicgen-*`, `riffusion`, `ast-tag`, `clap-embed`, `pyannote`). Every generation request 500'd with `OSError: model is not cached locally and an error occurred while trying to fetch metadata from the Hub`. Strict-offline deployments now opt back in via `-e HF_HUB_OFFLINE=1`.
- **v1.0.3** — Entrypoint mirrors `HUGGINGFACE_TOKEN ↔ HF_TOKEN`. `huggingface_hub` (the library underneath `diffusers` / `transformers`) reads `HF_TOKEN` as canonical — older audiolla docs (and aigate's compose env block) only set `HUGGINGFACE_TOKEN`, so gated repos got an anonymous request and 401'd even when the operator's token was authorised. Either env name is now sufficient.

Both bugs had been worked around manually in a draft v3.7.1 (compose-side env overrides `HF_HUB_OFFLINE=0` and `HF_TOKEN: ${HF_TOKEN:-}`). That draft is now superseded — upstream merged the same fixes, so the aigate-side overrides are deleted and the compose env block reverts to just `HUGGINGFACE_TOKEN: ${HF_TOKEN:-}`.

Verified end-to-end against the live aigate stack post-bump — all three generation engines from v3.7.0 work with no aigate-side workarounds:

| Engine | First-call time | Output |
|---|---|---|
| `audioldm2` (CC-BY 4.0, ungated) | 182 s (incl. ~3 GB download) | 4 s WAV, 128 KB |
| `musicgen-small` (CC-BY-NC, ungated on HF, gated on `AUDIOLLA_ENABLE_NONCOMMERCIAL=1`) | 86 s (incl. download) | 4 s WAV, 256 KB |
| `stable-audio-open` (Stability Community Licence, HF-gated) | 270 s (incl. ~6 GB download, after operator accepted the licence at huggingface.co) | 4 s WAV, 706 KB |

Files:

- `docker-compose.yml`: pinned images bumped on both audiolla services — `psyb0t/audiolla:v1.0.1` → `psyb0t/audiolla:v1.0.3` and `v1.0.1-cuda` → `v1.0.3-cuda`. Deleted the two draft-v3.7.1 env overrides on both services (`HF_HUB_OFFLINE: ${AUDIOLLA_HF_HUB_OFFLINE:-0}` and `HF_TOKEN: ${HF_TOKEN:-}`) — now redundant with upstream's defaults.

## [v3.7.0] — 2026-06-08

Bump audiolla v0.23.1 → **v1.0.1** (both CPU and CUDA). Upstream jumped straight to a 1.0 stability commitment with a fully breaking REST contract; every v0.23.x client breaks. Aigate-side this means rewriting the smoke tests and the docs/usage snippets, updating the MCP descriptions LiteLLM hands to LLM agents, and adding one new env var to gate the CC-BY-NC MusicGen weights.

### What v1.0.1 changed upstream

- **JSON body on every audio endpoint.** Multipart `Form()`/`File()` dropped. The single remaining bytes-on-the-wire entry point is `PUT /v1/files/{path}`.
- Input is `file_path` (FILES_DIR-relative, after staging) XOR `file_url` (server-side fetch, governed by `AUDIOLLA_FETCH_MODE`).
- Audio-producing tools require `output_path` (server stages under `FILES_DIR` — caller fetches via `GET /v1/files/<path>`) XOR `output_url` (server PUTs to a presigned URL). The pre-1.0 `*_base64` response fields are gone everywhere.
- **5 new CUDA-only text-to-audio generation engines** under `POST /v1/audio/generate/{engine}`: `stable-audio-open` (Stability Community Licence), `musicgen-small` / `musicgen-medium` (CC-BY-NC, gated), `riffusion` (CreativeML OpenRAIL-M), `audioldm2` (CC-BY 4.0 — commercial-safe, no gate).
- `openapi.yaml` is now the canonical contract; Pydantic models regenerate via `make generate`.
- 73 → 90 documented routes. Tool count grew from 81 to ~85+.

### Files

- `docker-compose.yml`: pinned image bumped on both audiolla services — `psyb0t/audiolla:v0.23.1` → `psyb0t/audiolla:v1.0.1` and the CUDA variant `v0.23.1-cuda` → `v1.0.1-cuda`. Added `AUDIOLLA_ENABLE_NONCOMMERCIAL: ${AUDIOLLA_ENABLE_NONCOMMERCIAL:-}` to both env blocks — off by default; flipping it to `1` lets the CUDA container load the MusicGen weights (matches the matchering / GPL v3 opt-in pattern).
- `tests/test_audiolla.sh`: `_audiolla_test_info_live` and `_audiolla_test_analyze_live` rewritten for the new contract. New `_audiolla_stage_fixture` helper PUTs `tests/.fixtures/audio.mp3` to a per-test path under `aigate-test/` (so the CPU and CUDA passes don't collide), then POSTs a JSON body with `{"file_path":"…"}`. The `-F "file=@…"` multipart calls are gone.
- `docs/usage.md`: audiolla section rewritten to show the v1.0 PUT-then-POST flow + `output_path` requirement, with a worked example that stages a file, runs `chords` (analysis), runs `separate` (audio-producing — needs `output_paths` per stem), and then downloads a stem from `GET /v1/files/<path>`.
- `litellm/config/mcp/audiolla.yaml`: description rewritten to call out the v1.0.1 JSON-everywhere contract, the input rules (`file_path` xor `file_url`), the output rules (`output_path` xor `output_url`), the dropped `*_base64` fields, and the five new `generate_<engine>` tools (with the licence notes). Same allowed-host workaround for FastMCP DNS rebinding stays in place.
- `litellm/config/mcp/audiolla-cuda.yaml`: description now points the agent at the CUDA fragment when it specifically wants the generation engines (only available on the GPU variant); references the CPU fragment for the full per-tool list.
- `.env.example`: documented `AUDIOLLA_ENABLE_NONCOMMERCIAL` knob, with licence-source pointer and which engines are gated vs free.
- `README.md`, `docs/services-reference.md`: bullet points updated to mention the text-to-audio generation engines and the v1.0+ JSON contract; the "Audio output modes" line replaced with the `output_path xor output_url` requirement.

### Things to know before flipping AUDIOLLA_ENABLE_NONCOMMERCIAL=1

MusicGen weights are CC-BY-NC 4.0 — non-commercial only. The engine code ships in the image but refuses to load the model unless the operator opts in. AudioLDM 2 is CC-BY 4.0 (commercial-safe, no opt-in). Stable Audio Open is Stability's Community Licence. Riffusion is CreativeML OpenRAIL-M. Read each one before shipping audio generated by it into a product.

## [v3.6.0] — 2026-06-08

Pass-through for pibox-zai's per-request agent knobs over the OpenAI-compatible endpoint, plus a Makefile fix for the v3.4.0 profile autodetect.

### Bump: pibox-zai → v0.8.0 (full `x-aicodebox-*` header surface)

Upstream `psyb0t/pibox:v0.8.0` rides on aicodebox v0.7.0, which exposes every RunSpec knob as an `x-aicodebox-*` header on `/openai/v1/chat/completions`. Previously only 3 of the 9 were reachable from the OpenAI surface; the other 6 required dropping to `POST /run` and bypassing LiteLLM. Now an OpenAI-SDK caller can pass any of them via `extra_headers`:

| Header | Effect |
|---|---|
| `x-aicodebox-workspace` | workspace subdir under `/workspace` (alt: `x-claude-workspace`) |
| `x-aicodebox-continue` | `1`/`true`/`yes` → resume previous session; absent → fresh (alt: `x-claude-continue`) |
| `x-aicodebox-append-system-prompt` | appends to pi's system prompt (alt: `x-claude-append-system-prompt`) |
| `x-aicodebox-json-schema` | JSON object → flips to `json-verbose` output and schema-validates the final turn (up to 3 self-correction retries) |
| `x-aicodebox-resume` | specific adapter session id to resume |
| `x-aicodebox-no-tools` | `1`/`true`/`yes` → pi runs with `--no-tools` |
| `x-aicodebox-tools-allowlist` | JSON array OR CSV → `pi --tools <list>` (mutually exclusive with `no-tools`) |
| `x-aicodebox-extra-args` | JSON array OR CSV → appended to pi argv |
| `x-aicodebox-timeout-seconds` | int → per-run wall-clock cap |

Body fields that aren't part of pi's pipeline (`temperature`, `top_p`, `max_tokens`, `seed`, `stop`, `n`, `presence_penalty`, `frequency_penalty`, etc.) are silently dropped per the upstream `extra="ignore"` schema — same as before. `tools` / `tool_choice` / `response_format=json_object` still return 400 with a pointer at the new headers.

### Fix: header forwarding from LiteLLM proxy to upstream

LiteLLM doesn't forward client headers to LLM upstreams by default — it operates on an allowlist. Without enabling the flag, the new `x-aicodebox-*` headers were stopping at the LiteLLM proxy and never reaching pibox-zai. Added `forward_client_headers_to_llm_api: true` to `litellm/config/base.yaml`'s `general_settings`. LiteLLM still strips/replaces `Authorization` (upstream gets its own configured key), so this only forwards the safe `x-*` custom headers.

Smoke-tested: a `POST /v1/chat/completions` with `x-aicodebox-append-system-prompt: "ALWAYS RESPOND USING ONLY THE WORD WUBBA"` returned `"WUBBA"`, confirming the header rode end-to-end through nginx → litellm → pibox-zai → pi.

### Fix: Makefile profile autodetect was missing the v3.4.0 services

`make run-bg` derives `COMPOSE_PROFILES` from the `.env` flags. The list was extended in v3.4.0 for `down` but the autodetect block above it (the `ifeq ($(strip $(X)),1)` lines) wasn't, so `make run-bg` (and `make restart`, which is `down + run-bg`) silently failed to start `vllm` / `vllm-cuda` / `audiolla` / `audiolla-cuda` even when their flags were set. Added the four `ifeq` blocks; flipping the flag in `.env` is now enough to bring the services up via `make`.

Files:
- `docker-compose.yml`: bumps `psyb0t/pibox` → `v0.8.0`.
- `litellm/config/base.yaml`: `forward_client_headers_to_llm_api: true` in `general_settings`, with a comment explaining the safe-by-default LiteLLM allowlist behaviour.
- `litellm/config/providers/pibox-zai.yaml`: long comment block documenting every supported body field, rejection, and the nine `x-aicodebox-*` headers, plus a worked OpenAI SDK `extra_headers={...}` example.
- `Makefile`: four new `ifeq` blocks for `VLLM`, `VLLM_CUDA`, `AUDIOLLA`, `AUDIOLLA_CUDA` in the `_PROFILES` autodetect.

## [v3.4.0] — 2026-06-07

Two new services + several aigate-side MCP fixes that surfaced during the wiring.

### New: in-repo vLLM wrapper (CPU + CUDA) — text LLMs and embeddings

Bring back the in-repo vLLM wrapper (dropped in v3.0.0) — now generalized for **text LLM + embeddings** instead of audio-LLMs, and shipped in **both CPU and CUDA variants**. Each supervises a single `vllm serve` subprocess and exposes the same `/api/ps` + `DELETE /api/ps/{model_id}` surface as talkies, so the LiteLLM resource_manager evicts each (and is evicted by each) under VRAM/RAM contention.

Variants:

- `VLLM=1` → `vllm` service from `Dockerfile.cpu` (base: `vllm/vllm-openai-cpu`), CPU-tuned `models.cpu.json`, LiteLLM prefix `local-vllm-*`, resource_manager group `cpu-vllm`.
- `VLLM_CUDA=1` → `vllm-cuda` service from `Dockerfile.cuda` (base: `vllm/vllm-openai:v0.21.0`), CUDA-tuned `models.cuda.json`, LiteLLM prefix `local-vllm-cuda-*`, resource_manager group `cuda-vllm`.
- Both can be enabled simultaneously. They share `${DATA_DIR_VLLM}/models/<org>/<repo>/` (populated once by `vllm-pull`) so no duplicate downloads.

Default models:

- `nomic-embed-v2` — `nomic-ai/nomic-embed-text-v2-moe` (MoE, 305M active, embeddings, 8192 ctx)
- `qwen3-0.6b` — `Qwen/Qwen3-0.6B` (chat + completions, 16384 ctx)

Weights live under `${DATA_DIR_VLLM}/models/<org>/<repo>/<files>` in the flat HF-repo layout (no `blobs/`/`snapshots/` dedup). The pull container populates this via `huggingface-cli download <repo> --local-dir <path>` so other services that bind-mount the same dir can load the same files directly. The supervisor passes the local path to `vllm serve` (not the HF repo string) and the wrapper runs `HF_HUB_OFFLINE=1`.

Endpoints proxied to the supervised subprocess: `/v1/chat/completions`, `/v1/completions`, `/v1/embeddings`. Audio-only endpoints (`/v1/audio/transcriptions`) are gone — talkies covers ASR.

Add more models by editing `vllm/models.json`. Each entry maps a slug to `{repo, vllm_args, endpoints}`; endpoints must be a subset of `{"chat", "completions", "embeddings"}`.

Files:

- `vllm/` — restored from `909e29a` and generalized:
  - `vllm/src/vllm_wrap/server.py` — dropped `/v1/audio/transcriptions`, dropped the multipart body rewriter (audio-only `verbose_json→json` normalization), added `/v1/embeddings` + `/v1/completions`. Single JSON-only proxy path.
  - `vllm/src/vllm_wrap/config.py` — endpoint validator now allows `{"chat", "completions", "embeddings"}`; added `VLLM_WRAP_DEVICE` (`cpu`/`cuda`) and `VLLM_WRAP_MODELS_DIR` (default `${DATA_DIR}/models`).
  - `vllm/src/vllm_wrap/supervisor.py` — resolves `repo` to a local path (`MODELS_DIR/<repo>`) and passes that to `vllm serve`; appends `--device <DEVICE>` when set.
  - `vllm/models.cuda.json` — CUDA-tuned `vllm_args` (Nomic embed v2 + Qwen3-0.6B).
  - `vllm/models.cpu.json` — CPU-tuned `vllm_args` (no `--gpu-memory-utilization`, smaller Qwen3 context).
  - `vllm/Dockerfile.cuda` — base `vllm/vllm-openai:v0.21.0`, copies `models.cuda.json`.
  - `vllm/Dockerfile.cpu` — base `vllm/vllm-openai-cpu:latest-x86_64`, copies `models.cpu.json`, sets `VLLM_WRAP_DEVICE=cpu`, `VLLM_CPU_KVCACHE_SPACE=4`.
  - `vllm/pyproject.toml` — bumped to 0.2.0, dropped `python-multipart`, updated description/keywords.
- `docker-compose.yml` — added `vllm` (CPU), `vllm-cuda`, and shared `vllm-pull` (profiles `[vllm, vllm-cuda]`). Pull container does `huggingface-cli download <repo> --local-dir /data/models/<repo>` for each model in the flat HF-repo layout (no blobs/snapshots dedup) so other services bind-mounting the same dir can reuse the weights.
- `litellm/build-config.py` — registers `vllm` (when `VLLM=1`) and `vllm-cuda` (when `VLLM_CUDA=1`) in `active_providers`.
- `litellm/config/providers/vllm.yaml` — CPU aliases `local-vllm-nomic-embed-v2` + `local-vllm-qwen3-0.6b`.
- `litellm/config/providers/vllm-cuda.yaml` — CUDA aliases `local-vllm-cuda-nomic-embed-v2` + `local-vllm-cuda-qwen3-0.6b`.
- `tests/test_vllm.sh` — wrapper introspection (`/healthz`, `/v1/models`, `/api/ps`, `POST /unload`, `DELETE /api/ps/{id}`) plus live LiteLLM-routed tests for chat + embeddings, parameterised on upstream host and alias so both CPU and CUDA variants are covered. Auto-picked up by `test.sh`; each test skips when its variant is disabled.
- `litellm/callbacks/resource_manager.py` — added `cpu-vllm` (CPU prefix `local-vllm-`) and `cuda-vllm` (CUDA prefix `local-vllm-cuda-`) groups. Both use the existing `DELETE /api/ps/{model_id}` unload pattern.
- `recommend-limits.sh` — tracks `VLLM=1` and `VLLM_CUDA=1`, shows both in the enabled-services line.
- `.env.example` — `VLLM=`/`VLLM_CUDA=` flags in Core; `VLLM_*` and `VLLM_CUDA_*` tuning vars (MODEL_TTL, SWEEPER_INTERVAL, LOAD_TIMEOUT, REQUEST_TIMEOUT, LOG_LEVEL, PRELOAD, PREFETCH) plus `VLLM_CPU_KVCACHE_SPACE` and `DATA_DIR_VLLM`.
- `tests/test_litellm.sh` — `EXPECTED_MODELS` extends with the CPU aliases when `VLLM=1` and the CUDA aliases when `VLLM_CUDA=1`.
- `docs/providers.md`, `docs/services-reference.md`, `docs/usage.md`, `README.md` — document both services side-by-side, the shared model store, model list, endpoint surface, tuning vars, embeddings curl example, and resource_manager groups.

### New: audiolla (CPU + CUDA) — self-hosted audio-production REST + MCP

Adds **audiolla** at `/audiolla/` (upstream: [psyb0t/docker-audiolla](https://github.com/psyb0t/docker-audiolla) v0.23.1). Self-hosted **audio-production** stack: stem separation (Demucs / UVR), restoration (UVR de-reverb / de-echo / de-noise), mastering (matchering + pedalboard chains), MIR analysis (librosa), DSP transforms (sox + ffmpeg), loudness normalization, speech enhancement (DeepFilterNet), VAD (silero), diarization (pyannote), CLAP embeddings + zero-shot classification, AudioSet tagging (AST), audio→MIDI (basic-pitch), MIDI compose / inspect / transform / render via fluidsynth. Curated YAML workflow presets (`master-for-spotify`, `podcast-cleanup`, `vocal-cleanup`) and ad-hoc op-chain pipelines run server-side — intermediates stay in memory between steps. Async jobs + webhooks for long-running work.

Audio output modes (per audio-producing tool): default base64, `output_path` (stages under `${DATA_DIR_AUDIOLLA}/files`), `output_url` (PUT to a presigned URL).

Wired the same way as predictalot (direct nginx route, not via LiteLLM, MCP aggregated into `/mcp/`). CPU and CUDA variants run **side-by-side** on distinct routes and aliases — `/audiolla/` → CPU, `/audiolla-cuda/` → GPU. Enable independently via `AUDIOLLA=1` and/or `AUDIOLLA_CUDA=1`. CUDA needs `nvidia-container-toolkit` and is significantly faster on Demucs, UVR, pyannote, basic-pitch, DeepFilterNet, CLAP. Both share `${DATA_DIR_AUDIOLLA}` for the weight cache, so the second variant to boot reuses the first's downloads with zero re-fetch.

Also trimmed the long predictalot endpoint matrix in the in-repo docs — the upstream README is now the canonical source of truth for both services.

- `docker-compose.yml`: new `audiolla` service (profile `["audiolla"]`, image `psyb0t/audiolla:v0.23.1`) and `audiolla-cuda` (profile `["audiolla-cuda"]`, image `psyb0t/audiolla:v0.23.1-cuda`, NVIDIA GPU reservation). Each binds its own compose-service-name alias (`audiolla` vs `audiolla-cuda`). Both bind-mount `${DATA_DIR_AUDIOLLA}` to `/data`. `AUDIOLLA_AUTH_TOKEN` defaults to `AIGATE_TOKEN` (master-auth chain). Nginx exposes both via parallel `location /audiolla/` and `location /audiolla-cuda/` blocks, each with its own rate-limit zone (`audiolla` / `audiolla_cuda`), `client_max_body_size = AUDIOLLA_MAX_UPLOAD_BYTES`, and `TIMEOUT_AUDIOLLA`-controlled proxy timeouts.
- `litellm/config/mcp/audiolla.yaml` + `litellm/config/mcp/audiolla-cuda.yaml`: two MCP fragments pointing at `http://audiolla:8000/v1/mcp/` and `http://audiolla-cuda:8000/v1/mcp/` respectively, each with bearer auth and a `static_headers: Host: "127.0.0.1:8000"` to satisfy FastMCP's DNS-rebinding-protection allowlist (Host header would otherwise be the compose service name and FastMCP returns 421). Description on the CPU fragment covers the full 80+ tool surface including workflow primitives (`list_presets`, `describe_preset`, `list_ops`, `run_preset`, `run_pipeline_tool`) and the three output modes; the CUDA fragment points back at the CPU description and clarifies it's the forced-GPU path.
- `litellm/build-config.py`: registers `audiolla` in `active_mcp_servers` when `AUDIOLLA=1` and `audiolla-cuda` when `AUDIOLLA_CUDA=1` (independent flags so both surfaces can be aggregated simultaneously).
- `recommend-limits.sh`: tracks both `AUDIOLLA=1` and `AUDIOLLA_CUDA=1`.
- `.env.example`: `AUDIOLLA=` + `AUDIOLLA_CUDA=` flags in Core; `AUDIOLLA_*` tuning vars (auth, device, enabled engines, preload, engine TTL, sweeper, upload cap, server-side URL fetch policy, job TTL + concurrency); `DATA_DIR_AUDIOLLA`; per-route `RATELIMIT_AUDIOLLA[_BURST]` and `RATELIMIT_AUDIOLLA_CUDA[_BURST]`; shared `TIMEOUT_AUDIOLLA`.
- `README.md`, `docs/services-reference.md`, `docs/usage.md`: minimal sections — what it is, where the endpoint lives, auth, a small smoke-test, and a link to the upstream README for the full API. Trimmed predictalot to the same minimal shape.
- `tests/test_audiolla.sh`: parameterised helpers (route prefix + tag) run the full suite — open-healthz, unauthenticated-rejection on `/v1/engines`, engines listing (asserts `htdemucs` + `librosa-analyze`), `/v1/catalog` discovery, two live ops against `tests/.fixtures/audio.mp3` (`/v1/audio/info` ffprobe, `/v1/audio/analyze` librosa), and a direct `/v1/mcp/` `tools/list` assertion (≥ 20 tools, spot-checks `separate`/`analyze`/`chords`) — separately against `/audiolla/` (gated on `AUDIOLLA=1`) and `/audiolla-cuda/` (gated on `AUDIOLLA_CUDA=1`).
- `.research_files/docker-audiolla/`: upstream repo clone (for reference; gitignored).

### Fix: aigate-side MCP wiring made `/mcp/` actually aggregate downstream services

Two bugs surfaced while wiring audiolla and would have been silently breaking predictalot for as long as `os.environ/` token references existed in the MCP fragments — `/mcp/` was missing every downstream-token-protected MCP server (predictalot, audiolla):

- `os.environ/AUDIOLLA_AUTH_TOKEN` and `os.environ/PREDICTALOT_AUTH_TOKEN` in LiteLLM MCP fragments resolve against the **LiteLLM** container's environment, not the downstream service's. `.env` only carries `AIGATE_TOKEN` (the master), so LiteLLM was sending an empty bearer to each MCP server → 401 → LiteLLM `Task cancelled while listing tools from {server}`. Fixed by re-exporting the same `${X_AUTH_TOKEN:-${AIGATE_TOKEN:-fallback}}` chain in the `litellm:` env block for both `PREDICTALOT_AUTH_TOKEN` and `AUDIOLLA_AUTH_TOKEN`.
- FastMCP's DNS-rebinding protection rejects requests whose `Host` header isn't in its allowlist (default `localhost` / `127.0.0.1`). LiteLLM was sending `Host: audiolla:8000` → 421 Misdirected Request → cancelled. Fixed in `litellm/config/mcp/audiolla.yaml` via `static_headers: Host: "127.0.0.1:8000"`. The request is already inside `aigate-internal` so there's no actual rebinding risk.
- Bumped `LITELLM_MCP_TOOL_LISTING_TIMEOUT` (default 30s) → 120s, `LITELLM_MCP_CLIENT_TIMEOUT` → 120s in the `litellm:` env block. Audiolla's 81-tool listing is on the edge of the default; tighter caps were silently dropping it.

After these fixes, `/mcp/` aggregates the full set — including 81 audiolla tools and the 26 predictalot tools — under the expected `<server>-<tool>` namespaced names.

### Restored: predictalot CUDA (side-by-side with CPU)

Brings back the predictalot CUDA variant (dropped in v3.2.0 due to a shared-alias conflict) using the same side-by-side pattern as audiolla. CPU on `/predictalot/` (alias `predictalot`), CUDA on `/predictalot-cuda/` (alias `predictalot-cuda`). Both share `${DATA_DIR_PREDICTALOT}/models` so the second variant to boot reuses the first's HF snapshots. CUDA needs `nvidia-container-toolkit`.

- `docker-compose.yml`: new `predictalot-cuda` service (profile `["predictalot-cuda"]`, image `psyb0t/predictalot:v0.2.1-cuda`, NVIDIA GPU reservation). Mounts `${DATA_DIR_PREDICTALOT}/models` so weights are shared with the CPU container. Nginx exposes both via parallel `location /predictalot/` and `location /predictalot-cuda/` blocks, each with its own `limit_req` zone (`predictalot` / `predictalot_cuda`) and `TIMEOUT_PREDICTALOT`-controlled proxy timeouts.
- `litellm/config/mcp/predictalot-cuda.yaml`: new MCP fragment pointing at `http://predictalot-cuda:8080/mcp` with bearer auth. Description points back at the CPU fragment for the full per-tool list.
- `litellm/build-config.py`: `predictalot` and `predictalot-cuda` are now two independent MCP registrations (gated on `PREDICTALOT=1` and `PREDICTALOT_CUDA=1` respectively) so the aggregator surfaces both as `predictalot-*` and `predictalot_cuda-*` tools when both variants are on.

### Fix: MCP server YAML keys must follow SEP-986

`litellm/config/mcp/audiolla-cuda.yaml` was shipped in v3.4.0 with the YAML key `audiolla-cuda:`. LiteLLM v1.80.18+ enforces SEP-986 on MCP server names — names cannot contain `-`. With both audiolla variants on, the proxy refused to start: `Exception: Server name cannot contain '-'. Use an alternative character instead Found: audiolla-cuda`. Renamed the inside-YAML keys to use underscores (`audiolla_cuda`, `predictalot_cuda`) while keeping the on-disk filenames with dashes so `build-config.py`'s `<server-name>.yaml` lookup still works. Tool prefixes in the aggregated `/mcp/` are now consistently `<server_with_underscores>-<tool>` as LiteLLM expected from the start.

### Fix: predictalot MCP fragment was missing the same wiring audiolla got

The audiolla v3.4.0 work fixed three things in its MCP fragment that the long-standing `litellm/config/mcp/predictalot.yaml` was silently missing too — so predictalot's MCP tools never actually surfaced in the aggregated `/mcp/`. This release backports the same fixes to `predictalot.yaml` (and applies them to the new `predictalot-cuda.yaml` from the start):

- **Trailing slash on the URL.** FastMCP mounts the streamable-HTTP transport at `/mcp/` (with the slash) and returns 307 to `/mcp/` for the unsigned form. LiteLLM's MCP client doesn't follow that redirect — it just hangs and cancels. Both `predictalot.yaml` and `predictalot-cuda.yaml` now use `http://<host>:8080/mcp/`.
- **`static_headers: Host: "127.0.0.1:8080"`.** Same DNS-rebinding-protection fix as audiolla — without the override LiteLLM sends `Host: predictalot[-cuda]:8080` and FastMCP returns 421.

After both fixes, `/mcp/` cleanly surfaces 26 `predictalot-*` tools (and another 26 `predictalot_cuda-*` when both variants are on).

### Fix: container healthchecks for predictalot / vllm / vllm-cuda

- **predictalot** healthcheck used `wget`, which isn't in `psyb0t/predictalot:v0.2.1`. Switched to a `python3 -c` urllib probe (same pattern as audiolla in v3.4.0). Without this, the container always showed `unhealthy` even when `/healthz` returned 200.
- **vllm** + **vllm-cuda** healthchecks used bare `python`, which isn't on the `vllm/vllm-openai*` base images (they have `python3` only). Switched both to `python3`. Same symptom — container running fine, healthcheck reporting `unhealthy`, which prevented `depends_on: condition: service_healthy` parents (nginx + litellm) from accepting them as dependencies.
- `.env.example`: `PREDICTALOT_CUDA=` flag in Core; per-route `RATELIMIT_PREDICTALOT_CUDA[_BURST]` knobs.
- `README.md`, `docs/services-reference.md`: side-by-side endpoint table and updated route diagram.
- `tests/test_predictalot.sh`: parameterised helpers (route prefix + mcp namespace) — 8 CPU tests + 8 CUDA tests, each gated on its own flag.

### Other

- `.gitignore`: added `.data/vllm/` + `.data/audiolla/` to the allowlist (with `.gitkeep`) so the empty bind-mount target dirs are tracked.
- Empty `.gitkeep` files committed under both new data dirs.
- `Makefile`: `down` target's `COMPOSE_PROFILES` list extended with `vllm`, `vllm-cuda`, `audiolla`, `audiolla-cuda` so `make down` (and `make restart`, which is `down + run-bg`) actually tears down the new services. `predictalot-cuda` was already in the list from before v3.2.0 (no change needed).

## [v3.3.0] — 2026-06-03

Bump hybrids3: v0.1.0 → v0.2.0. Adds presigned **PUT** URLs (existing presign endpoint now accepts `?method=PUT`). Backwards compatible — default is still GET.

- `docker-compose.yml`: bump `psyb0t/hybrids3` → `v0.2.0`.
- `docs/services-reference.md`: presign section documents the new `?method=PUT` query param and the boto3 `put_object` form. Notes that the method is bound into the SigV4 canonical request (GET-signed URLs can't PUT, vice versa), and that PUT on public buckets still requires a signed URL.

## [v3.2.0] — 2026-05-31

Drop `predictalot-cuda` service. CPU is fast enough and the two variants shared the same network alias (`predictalot`), making simultaneous use broken by design. CPU-only keeps it simple.

- `docker-compose.yml`: removed `predictalot-cuda` service block entirely.
- `.env.example`: removed `PREDICTALOT_CUDA=` line.
- `docs/services-reference.md`: updated section heading to drop CUDA mention.

## [v3.1.0] — 2026-05-31

Unified auth token + talkies network fix. Backwards compatible — existing `.env` files keep working unchanged.

### New: `AIGATE_TOKEN` master auth

Single bearer token now authenticates against every aigate-owned service. Set `AIGATE_TOKEN` in `.env` and it becomes the default for:

- `LITELLM_MASTER_KEY` (LiteLLM `/v1/*`)
- `CLAUDEBOX_API_TOKEN` (`/claudebox/*`)
- `PIBOX_ZAI_API_TOKEN` (`/pibox-zai/*` + its MCP)
- `PREDICTALOT_AUTH_TOKEN` (`/predictalot/*` + MCP, CPU + CUDA both)
- `MCP_TOOLS_AUTH_TOKEN` (`/mcp/*`)
- `STEALTHY_AUTO_BROWSE_AUTH_TOKEN` (`/stealthy-auto-browse/*`)
- `TELETHON_AUTH_KEY` (`/telethon/*`)
- `HYBRIDS3_MASTER_KEY` (S3 master)

Per-service tokens still override when set explicitly (chain pattern: `${SERVICE_TOKEN:-${AIGATE_TOKEN:-<literal-fallback>}}`). Upstream provider credentials (Anthropic OAuth, z.ai, Groq, OpenAI, etc.) are untouched — they're not aigate auth.

`mailbox` is not wired into this — its auth lives in the `MAILBOX_CONFIG` yaml file on the host, outside compose's interpolation scope.

### Fix: talkies couldn't reach HuggingFace

`talkies` / `talkies-cuda` were attached only to `aigate-internal` (which has `internal: true` → no upstream traffic). The talkies entrypoint prefetches enabled models from HuggingFace on boot — the DNS resolution failed and both containers crash-looped. Added `aigate-public` to both (matches the pattern already used by `ollama` / `ollama-cuda` / `sdcpp` / `sdcpp-cuda` / `predictalot` for the same reason).

### Cleanup: dead `TALKIES_PREFETCH` env var

`TALKIES_PREFETCH` / `TALKIES_CUDA_PREFETCH` were carried over from the old in-repo talkies design and never read by the upstream `psyb0t/talkies` image — the v0.5.0 entrypoint unconditionally prefetches all enabled models on boot (controlled by `TALKIES_ENABLED_MODELS`, not `_PREFETCH`). Stripped from `docker-compose.yml`, `.env.example`, and `docs/services-reference.md`. `TALKIES_PRELOAD` (lazy-load list read by the server at startup) is still honored and stays.

### Files changed

- `.env.example` — added `AIGATE_TOKEN` block in Core section; commented per-service tokens to mark them as overrides; dropped dead `TALKIES_PREFETCH` / `TALKIES_CUDA_PREFETCH` lines.
- `docker-compose.yml` — chained per-service token defaults through `AIGATE_TOKEN`; added `aigate-public` to `talkies` + `talkies-cuda`; stripped dead `TALKIES_PREFETCH` env passthrough on both talkies services.
- `docs/services-reference.md` — dropped the `TALKIES_PREFETCH` row from the tuning table.

## [v3.0.0] — 2026-05-29

**Breaking: removed in-repo `talkies/`, `asr-canary/`, `vllm/`, and `qwen3-cuda-tts/` source trees. All transcription + TTS now goes through the external [`psyb0t/talkies`](https://github.com/psyb0t/docker-talkies) image (pinned to `v0.5.0` / `v0.5.0-cuda`). One container exposes both `POST /v1/audio/transcriptions` (whisper + canary + parakeet) and `POST /v1/audio/speech` (Kokoro-82M; Qwen3-TTS-0.6B voice cloning on CUDA).**

### Env-var migration

| Old | New |
|---|---|
| `SPEACHES` / `SPEACHES_CUDA` | `TALKIES` / `TALKIES_CUDA` |
| `ASR_CANARY` / `ASR_CANARY_CUDA` | `TALKIES` / `TALKIES_CUDA` |
| `VLLM_CUDA` | removed (no replacement — run vllm-the-library separately if you need audio-input chat) |
| `QWEN_TTS_CUDA` | folded into `TALKIES_CUDA` (Qwen3-TTS bundles into the talkies-cuda image) |

### LiteLLM alias migration

| Old | New |
|---|---|
| `local-speaches-*` / `local-speaches-cuda-*` | `local-talkies-*` / `local-talkies-cuda-*` |
| `local-asr-canary-*` / `local-asr-canary-cuda-*` | `local-talkies-*` / `local-talkies-cuda-*` |
| `local-vllm-cuda-*` | removed |
| `local-qwen3-cuda-tts` | `local-talkies-cuda-qwen3-tts` |
| `local-speaches-kokoro-tts` | `local-talkies-kokoro-tts` (+ `-cuda-` variant) |

`distil-whisper-large-v3` is dropped from the talkies model set as English-only redundancy — use `whisper-large-v3-turbo` instead (multilingual, similar speed).

### Data-dir migration

`.data/speaches/`, `.data/asr-canary/`, `.data/vllm/`, `.data/qwen3-tts/` → `.data/talkies/` (single bind mount → `/data` inside the container; `hf/hub/models--*/` for the HF cache, `custom-voices/<name>.wav` for Qwen3-TTS reference voices).

### Voice cloning (CUDA only)

Drop a `<name>.wav` (10-30s clean speech) into `${DATA_DIR_TALKIES}/custom-voices/` on the host and use `voice=<name>` on `/v1/audio/speech`. Three sample voices (`alloy`, `echo`, `fable`) baked into the image. Nested paths supported (`voice=clients/acme/jane` → `${DATA_DIR_TALKIES}/custom-voices/clients/acme/jane.wav`). 17 languages: en, zh, ja, ko, fr, de, es, it, pt, ru, vi, th, id, ar, tr, pl, nl.

### Other in-repo cleanup

- `litellm/callbacks/resource_manager.py` — group set trimmed to `cuda-llm`, `cuda-img`, `cuda-stt-talkies`, `cpu-llm`, `cpu-img`, `cpu-stt-talkies`. Unload functions for speaches / asr-canary / vllm / qwen3-cuda-tts removed; per-group unloads parallelized via `asyncio.gather`. Talkies upstream model list covers all 12 v0.5.0 slugs (whisper × 2, parakeet, canary × 3, Kokoro, Qwen3-TTS).
- `recommend-limits.sh` — flag + allocation set rewritten to match the new service inventory.
- nginx inference-path timeouts (`TIMEOUT_API` / `TIMEOUT_CLAUDEBOX` / `TIMEOUT_LIBRECHAT` / `TIMEOUT_PREDICTALOT`) bumped to `24h` default — long CPU transcriptions and long-context completions no longer killed by a 600s read timeout. Non-inference paths (admin, telethon, searxng, mailbox, proxq, browser) kept their original short timeouts.
- `litellm.request_timeout` bumped to `86400` in `base.yaml`, with per-request injection via `resource_manager.async_pre_call_hook` so LiteLLM's hardcoded 600s default no longer fires.
- `.gitignore` rewritten to cover Python bytecode (`__pycache__/`, `*.pyc`), virtualenvs, IDE config, OS junk, and root-level scratch artifacts (probe scripts, downloaded test fixtures). `.data/talkies/` + `.data/talkies/custom-voices/` added to the data-dir allowlist; `.data/speaches/` removed.

## [v2.9.0] — 2026-05-26

**`asr-canary` now returns OpenAI Whisper-shape `verbose_json` with segment + word timestamps for the multitask Canary models, plus `srt` / `vtt` subtitle formats.**

Previously the wrapper accepted `response_format=verbose_json` for OpenAI compatibility but returned plain `{"text": …}` regardless — clients that depended on Whisper's `segments[]` / `words[]` arrays couldn't read timing data. This fixes that for the two backends that NeMo can timestamp: `canary-180m-flash` and `canary-1b-flash` (both `EncDecMultiTaskModel`). The SALM-based `canary-qwen-2.5b` is a chat LM under the hood and has no timestamp head — `verbose_json` requests still succeed but the `segments` / `words` arrays come back empty.

Response shape matches OpenAI exactly so existing whisper-family clients work with no changes:

```json
{
  "task": "transcribe",
  "language": "en",
  "duration": 2.43,
  "text": "You are just a line of code",
  "segments": [
    {"id": 0, "seek": 0, "start": 0.0, "end": 1.68,
     "text": "You are just a line of code",
     "tokens": [], "temperature": 0.0,
     "avg_logprob": null, "compression_ratio": null, "no_speech_prob": null}
  ],
  "words": [
    {"word": "You",  "start": 0.0,  "end": 0.08},
    {"word": "are",  "start": 0.4,  "end": 0.48},
    {"word": "just", "start": 0.56, "end": 0.64},
    {"word": "a",    "start": 0.8,  "end": 0.88},
    {"word": "line", "start": 0.96, "end": 1.04},
    {"word": "of",   "start": 1.2,  "end": 1.28},
    {"word": "code", "start": 1.36, "end": 1.68}
  ]
}
```

Whisper-only fields (`avg_logprob`, `no_speech_prob`, `compression_ratio`, `tokens`) are null-filled rather than omitted so clients reading them don't crash. `temperature` is hardcoded to `0.0` (Canary is greedy-decoded).

`srt` and `vtt` formats are built from the segments and returned as `text/plain` / `text/vtt` respectively. If the backend produces no segments (SALM, or an empty audio file), the wrapper falls back to a single segment spanning the full audio duration so the subtitle output is still valid.

Implementation notes:

- The wrapper takes an extra round through NeMo's `transcribe(timestamps=True)` only when the response format actually needs timing data (`verbose_json` / `srt` / `vtt`). Plain `json` / `text` paths skip the timestamp pass and stay fast.
- LiteLLM proxies repeated form fields to single values — a client sending `timestamp_granularities[]=segment&timestamp_granularities[]=word` through the LiteLLM proxy arrives at the wrapper as just `['word']`. To dodge this footgun the wrapper always emits both segments and words regardless of `timestamp_granularities[]` selection. Clients that read only one are unaffected; the other field is essentially free for us since NeMo computes both in the same pass.
- Audio duration is computed from the 16 kHz mono WAV the wrapper preprocesses the upload into (Python stdlib `wave`), so the `duration` field is always populated.

Two new live e2e tests (`test_asr_canary_transcribe_verbose_json`, `test_asr_canary_transcribe_srt`) exercise the new formats end-to-end through the LiteLLM proxy. asr-canary suite: 8/8 green.

## [v2.8.0] — 2026-05-25

**Add `vllm` — in-repo vLLM audio-LLM supervisor exposing transcribe + chat aliases for Qwen3-ASR + Voxtral.**

vllm-the-library serves two audio-LLMs that don't fit speaches' faster-whisper / parakeet stack: `Qwen/Qwen3-ASR-1.7B` and `mistralai/Voxtral-Mini-3B-2507`. Both are multilingual ASR AND accept chat-completions with audio input parts. vllm's own `serve` CLI gives us the OpenAI-compatible endpoints; what's missing is lifecycle: only one model fits in VRAM at a time, vLLM doesn't have a built-in eviction protocol, and the LiteLLM CUDA resource manager needs a speaches-shaped `/api/ps` surface to drive evictions. So we wrap it.

The service is named `vllm` (not `asr-vllm`) — Voxtral is a general audio-LLM (not pure ASR), and the same supervisor pattern can host additional vllm models in the future without renaming.

New microservice at `aigate/vllm/` (Python 3.12, FastAPI, base image `vllm/vllm-openai:v0.21.0` — minimum supporting both models):

- Single supervised `vllm serve` subprocess on `127.0.0.1:${VLLM_WRAP_SUBPROCESS_PORT}` (default 18000). Switching models = `SIGTERM` + drain (≤30s) + `SIGKILL` fallback, then spawn the new subprocess. `asyncio.Lock` serializes spawn/kill; `asyncio.Event` gates the kill path on in-flight request drain.
- Proxies `/v1/audio/transcriptions` (multipart) and `/v1/chat/completions` (JSON, streaming SSE supported) through httpx. Multipart `model` field is extracted via byte-regex to avoid double-reading `Request.body`.
- Each model gets two LiteLLM aliases — `local-vllm-cuda-<id>-transcribe` (mode `audio_transcription`) and `local-vllm-cuda-<id>-chat` (mode `chat`). Both proxy to the same upstream model_id, so switching endpoints is free; only switching models restarts vllm.
- Speaches-compatible `/api/ps` + `DELETE /api/ps/{model_id}` + `POST /unload`. The LiteLLM resource manager treats the entire service as one CUDA group (`cuda-vllm`) — a single eviction kills the resident subprocess, freeing VRAM for any competing CUDA job (LLM / image-gen / TTS / other STT).
- Background sweeper kills idle subprocess after `VLLM_WRAP_MODEL_TTL` seconds (default 600). Weights stay on disk; next request cold-starts vllm (~30–90s including weight load).
- Python module is named `vllm_wrap` (not `vllm`) to avoid colliding with vllm-the-library in the same Python environment. Wrapper env vars use `VLLM_WRAP_*` prefix for the same reason (vllm reserves `VLLM_PORT`, `VLLM_HOST_IP`, `VLLM_LOGGING_LEVEL`, etc.). User-facing `.env` flags stay aigate-flavored: `VLLM_CUDA=1`, `VLLM_CUDA_MODEL_TTL`, etc.

Wiring:

- `docker-compose.yml`: new `vllm-cuda` service (profile `vllm-cuda`, builds `aigate/vllm/Dockerfile.cuda`, NVIDIA GPU, `mem_limit: 12g`, `aigate-internal` only). New `vllm-cuda-pull` sidecar on `aigate-public` runs `huggingface-cli download` for both repos at startup; main container depends on pull completion via `service_completed_successfully`. Shared HF cache at `${DATA_DIR_VLLM:-${DATA_DIR}/vllm}:/data`.
- `litellm/config/providers/vllm-cuda.yaml`: four aliases — `*-transcribe` (mode `audio_transcription`) + `*-chat` (mode `chat`) for each of the two models.
- `litellm/build-config.py`: `vllm-cuda` registered as activatable provider; `VLLM_CUDA` counts as an MCP-trigger flag (auto-enables the `mcp_tools` server).
- `litellm/callbacks/resource_manager.py`: new `cuda-vllm` group + `_unload_vllm_cuda()` that issues `DELETE /api/ps/{model_id}` for every registered model_id. The vllm service does its own intra-service eviction (only one subprocess can exist), so the group treats the whole service as one eviction unit.
- `Makefile`: `VLLM_CUDA=1` → `vllm-cuda` profile, counts as MCP trigger, included in `make down` profile list, listed in `make help`.
- `.env.example`: new `VLLM_CUDA` flag, `DATA_DIR_VLLM`, and the full tuning surface — `VLLM_CUDA_MODEL_TTL` (default 600), `_SWEEPER_INTERVAL` (60), `_LOAD_TIMEOUT` (600), `_REQUEST_TIMEOUT` (300), `_LOG_LEVEL` (INFO), `_PRELOAD`, `_PREFETCH`.
- `README.md`: stack diagram lists vllm CUDA; services-overview table has a new row; data directories table mentions `.data/vllm/`; new transcription+audio-chat models section with the four aliases.
- `docs/providers.md`: new `vllm CUDA` provider section with alias → HF repo → mode table for all four aliases.
- `docs/services-reference.md`: new `vllm` service block with endpoints table, models-served table (~8 GB / ~10 GB VRAM each), behavior notes (single-subprocess invariant, lazy spawn, idle TTL, in-flight drain, resource-manager integration, two-aliases-per-model), and environment-variable table.
- `docs/usage.md`: transcription list extended with the two `-transcribe` aliases; new "Audio-input chat" subsection with curl example for `*-chat` aliases.
- `docs/testing.md`: new `vllm` row noting `/healthz`, `/v1/models`, `/api/ps`, `DELETE /api/ps/{model}`, `POST /unload` coverage, plus live transcribe + chat-audio e2e tests.
- `tests/test_vllm.sh`: five wrapper-level checks via `docker compose exec` into the internal-only `vllm-cuda` service (`/healthz`, `/v1/models`, `/api/ps`, `POST /unload`, `DELETE /api/ps/{unknown}` returns 200 or 404) plus four live e2e tests through the LiteLLM proxy — transcribe + chat-audio for both Qwen3-ASR and Voxtral with a real audio fixture.
- `tests/test_litellm.sh`: `EXPECTED_MODELS` gets all four `local-vllm-cuda-*` aliases under `VLLM_CUDA=1`.
- `.gitignore`: `vllm-repo/` added (research clone of vllm upstream, never committed).

## [v2.7.0] — 2026-05-25

**Add `asr-canary` — in-repo NeMo Canary STT microservice with CPU + CUDA variants.**

speaches' whisper / parakeet stack already covers most STT needs, but NVIDIA's Canary family is a different shape: Canary 180m-flash is the fastest English ASR ever published (~870× real-time on CPU), Canary 1b-flash adds EN↔DE/FR/ES translation, and Canary Qwen-2.5b is a hybrid SALM (speech-LLM) that emits punctuation/casing natively and can answer prompts about the audio. nemo_toolkit's `.transcribe()` / SALM `.generate()` APIs don't map onto faster-whisper, so we wrap them ourselves instead of trying to retrofit speaches.

New microservice at `aigate/asr-canary/` (Python 3.12, FastAPI, `nemo-toolkit[asr]==2.0.0`):

- OpenAI-compatible `/v1/audio/transcriptions` multipart upload (file + model + language + response_format). ffmpeg converts any container/codec to 16 kHz mono WAV before NeMo sees it.
- Speaches-compatible `/api/ps` resource-management surface — `GET /api/ps`, `DELETE /api/ps/{model_id}` (URL-encoded), `POST /unload` — so the LiteLLM CUDA/CPU resource manager evicts canary models from VRAM/RAM on competing-job arrival using the same `model_id.replace("/", "%2F")` path it already uses for speaches.
- Per-model `asyncio.Lock` serializes loads + transcribes. Background sweeper unloads any backend idle longer than `ASR_CANARY_MODEL_TTL` (default 600s). Weights stay on disk; next request warm-loads.
- Optional `ASR_CANARY_PRELOAD` (load into RAM/VRAM at boot) and `ASR_CANARY_PREFETCH` (HF snapshot at boot inside the main container) as comma-separated model_ids.

Wiring:

- `docker-compose.yml`: `asr-canary` (CPU, builds `aigate/asr-canary/Dockerfile`, profile `asr-canary`) + `asr-canary-cuda` (CUDA, builds `Dockerfile.cuda`, profile `asr-canary-cuda`). Both on `aigate-internal` only — main containers have no internet egress at runtime. Two pull sidecars (`asr-canary-pull`, `asr-canary-cuda-pull`) on `aigate-public` run `huggingface-cli download` at startup, mount the same `${DATA_DIR_ASR_CANARY:-${DATA_DIR}/asr-canary}:/data` (HF cache shared between CPU + CUDA — overlapping 180m-flash isn't re-downloaded). Speaches-pattern `depends_on: service_completed_successfully` makes the main containers boot after weights are on disk.
- `litellm/config/providers/asr-canary.yaml` + `asr-canary-cuda.yaml`: `local-asr-canary-180m-flash` (CPU); `local-asr-canary-cuda-180m-flash`, `local-asr-canary-cuda-1b-flash`, `local-asr-canary-cuda-qwen-2.5b` (CUDA). All `mode: audio_transcription`.
- `litellm/build-config.py`: `asr-canary` / `asr-canary-cuda` registered as activatable providers; `ASR_CANARY` / `ASR_CANARY_CUDA` count as MCP-trigger flags.
- `litellm/callbacks/resource_manager.py`: canary aliases registered as STT models. The single `cuda-stt` / `cpu-stt` group was **split** into `cuda-stt-speaches` + `cuda-stt-canary` (and CPU twins). speaches and asr-canary now compete as separate groups → each evicts the other on incoming jobs. Within each service the wrapper handles its own intra-service eviction. Speaches model lists also extended for the v2.6.0 additions (`whisper-large-v3-turbo`, `parakeet-tdt-0.6b-v3`) that were missed at the time.
- `litellm/callbacks/resource_manager.py`: monkey-patches `OpenAIWhisperAudioTranscriptionConfig.transform_audio_transcription_request` at module import to skip LiteLLM's unconditional `response_format` → `verbose_json` rewrite for parakeet-class models. Speaches' parakeet executor refuses `verbose_json`; the patch lets the client's chosen `response_format` (`json` / `text`) reach speaches untouched. Whisper/CT2 backends still get the original rewrite (they need `verbose_json` for duration extraction).
- **Dropped `local-speaches-crisper-whisper` / `local-speaches-cuda-crisper-whisper`.** The `nyrahealth/faster_CrisperWhisper` repo is the CT2 conversion but its HF model card declares no `library_name: ctranslate2` and no matching tag, so speaches' `passes_filter` rejects it with `404 Model … is not supported`. No alternate ctranslate2-tagged CrisperWhisper repo exists on HF. Removed from `litellm/config/providers/speaches{,-cuda}.yaml`, `litellm/callbacks/resource_manager.py` (groups + speaches model lists), `docker-compose.yml` pull job, `tests/test_litellm.sh`, `README.md`, `docs/usage.md`, `docs/providers.md`.
- `Makefile`: `ASR_CANARY=1` → `asr-canary` profile, `ASR_CANARY_CUDA=1` → `asr-canary-cuda` profile. Both count as MCP triggers (so `mcp` profile activates). `make down` includes both profiles in the kill list. `make help` lists both.
- `.env.example`: new `ASR_CANARY` / `ASR_CANARY_CUDA` flags, `DATA_DIR_ASR_CANARY` (shared CPU+CUDA dir, ~700MB CPU / ~14GB CUDA), and the full tuning surface (`ASR_CANARY_MODEL_TTL`, `ASR_CANARY_SWEEPER_INTERVAL`, `ASR_CANARY_MAX_UPLOAD_BYTES`, `ASR_CANARY_LOG_LEVEL`, `ASR_CANARY_PRELOAD`, `ASR_CANARY_PREFETCH` — each with a `_CUDA_` twin).
- `README.md`: ASCII stack diagram lists asr-canary CPU + CUDA; services-overview table has new rows; data directories table mentions the shared `.data/asr-canary/`; transcription-models tables (CPU + CUDA) have a section per variant.
- `docs/providers.md`: new `asr-canary CPU` + `asr-canary CUDA` provider sections with alias → HF repo → mode tables.
- `docs/services-reference.md`: new `asr-canary` service block with endpoint table, model list per variant, behavior notes (pre-pulled weights, lazy memory load, idle TTL, resource-manager integration, ffmpeg preprocessing), and environment-variable table.
- `docs/usage.md`: transcription-models list extended with the four new aliases.
- `docs/testing.md`: new asr-canary row noting `/healthz`, `/v1/models`, `/api/ps`, `DELETE /api/ps/{model}`, `POST /unload` coverage.
- `tests/test_asr_canary.sh`: exec-through-litellm into the internal-only `asr-canary` / `asr-canary-cuda` service (`docker compose exec litellm curl ...`) for the five endpoint checks above; CUDA variant additionally asserts 1b-flash + qwen-2.5b in `/v1/models`.
- `tests/test_litellm.sh`: `EXPECTED_MODELS` gets `local-asr-canary-180m-flash` under `ASR_CANARY=1` and three `local-asr-canary-cuda-*` aliases under `ASR_CANARY_CUDA=1`.

## [v2.6.0] — 2026-05-25

**Add three new local transcription model aliases on Speaches + make idle auto-unload explicit.**

Speaches already supports loading any HuggingFace model whose tags pass its registry filter (ctranslate2 + `automatic-speech-recognition` for whisper; `istupakov/parakeet-tdt-*` prefix for parakeet). Wiring three new ones as first-class LiteLLM aliases so callers can opt in by name without one-off `model=` overrides:

- `local-speaches-whisper-large-v3-turbo` → `deepdml/faster-whisper-large-v3-turbo-ct2`. The "turbo" Whisper from late 2024 — same architecture as large-v3 but with a 4-layer decoder instead of 32, ~8x faster decode at near-identical WER. CT2 weights, drop-in into the existing faster-whisper executor.
- `local-speaches-crisper-whisper` → `nyrahealth/faster_CrisperWhisper`. Whisper-medium fine-tuned for verbatim transcription that preserves disfluencies, fillers, repetitions, and pause timing instead of cleaning them up. Useful when downstream tooling needs the literal speech (transcript analysis, clinical notes, conversation mining).
- `local-speaches-parakeet-tdt-0.6b-v3` → `istupakov/parakeet-tdt-0.6b-v3-onnx`. Multilingual upgrade of v2 — covers 25 European languages (vs v2 being English-only). Same 0.6B params + NeMo TDT decoder, same ONNX path through speaches' parakeet executor.

All three exposed on both Speaches CPU (`local-speaches-*`) and Speaches CUDA (`local-speaches-cuda-*`). Existing `local-speaches-whisper-distil-large-v3` and `local-speaches-parakeet-tdt-0.6b` stay — these are additions, nothing removed.

Idle auto-unload made explicit instead of relying on speaches' default-300s:

- `docker-compose.yml`: `speaches` and `speaches-cuda` services now set `STT_MODEL_TTL` / `TTS_MODEL_TTL` via new env vars (`SPEACHES_STT_MODEL_TTL`, `SPEACHES_TTS_MODEL_TTL`, `SPEACHES_CUDA_STT_MODEL_TTL`, `SPEACHES_CUDA_TTS_MODEL_TTL`), default `600` (10 min). The LiteLLM resource manager still proactively unloads on competing-job arrival via `DELETE /api/ps/{model}`; the TTL is a secondary safety net for when no competing job ever arrives.
- `.env.example`: the four new TTL vars documented under "Speaches tuning".

Other files:
- `litellm/config/providers/speaches.yaml`, `speaches-cuda.yaml`: three new aliases each.
- `docker-compose.yml`: `speaches-pull` entrypoint extended to prefetch the three new HuggingFace repos (`deepdml/faster-whisper-large-v3-turbo-ct2`, `nyrahealth/faster_CrisperWhisper`, `istupakov/parakeet-tdt-0.6b-v3-onnx`). CUDA profile shares the same `.data/speaches/` cache — no separate CUDA pull job.
- `docs/providers.md`: Speaches CPU + CUDA tables extended with the three new rows each, plus a one-line note about the configurable TTL.
- `docs/usage.md`: transcription-models list extended with the new aliases.
- `README.md`: local transcription tables (CPU + CUDA) extended with the three new rows each.
- `tests/test_litellm.sh`: `EXPECTED_MODELS` lists for `SPEACHES=1` and `SPEACHES_CUDA=1` extended with the new aliases so the model-registration test asserts on them.

## [v2.5.0] — 2026-05-24

**Add OpenAI's new transcription models (`gpt-4o-transcribe` and `gpt-4o-mini-transcribe`) as LiteLLM aliases.**

OpenAI shipped two GPT-4o-based transcription models in March 2025 that share the `/v1/audio/transcriptions` endpoint with `whisper-1` but deliver lower WER (especially on accented/noisy/technical English) and support streaming partial chunks. Adding them as first-class aliases so they're usable from any LiteLLM caller without one-off `model=` overrides.

- `litellm/config/providers/openai.yaml`: add `openai-gpt-4o-transcribe` → `openai/gpt-4o-transcribe` and `openai-gpt-4o-mini-transcribe` → `openai/gpt-4o-mini-transcribe`. Both `mode: audio_transcription`. `openai-whisper` (whisper-1) untouched.
- `docs/providers.md`: append two rows to the OpenAI provider table.
- `docs/usage.md`: extend the transcription-models list with the new aliases.

Not yet wired into `fallbacks.json` — these are cloud/paid models, callers opt in by name. Output format note: gpt-4o-*-transcribe only support `json` / `text`. If you need `srt` / `vtt` / `verbose_json` (word-level timestamps), stick with `openai-whisper` or a Whisper local/Groq alias.

## [v2.4.0] — 2026-05-23

**Bump predictalot to v0.2.1 — type-routed API (breaking for callers) + auth on `/v1/<type>/models`.**

Breaking changes for any direct-HTTP or MCP caller of predictalot:

- HTTP: `/predictalot/v1/forecast` and `/predictalot/v1/models` no longer exist. Each forecast modality has its own URL family: `/v1/{univariate,multivariate,covariates/past,covariates/future,covariates,samples}/{forecast,forecast/ensemble,models}`. A model only appears under a type if it implements that modality. **All three sub-paths (`forecast`, `forecast/ensemble`, `models`) require the bearer token** — only `/healthz` is open.
- MCP: the 7-tool surface (`predictalot-forecast_<model>`, `predictalot-forecast_ensemble`, `predictalot-list_models`) is replaced by a 26-tool surface — `predictalot-forecast_<type>_<model>` (18 cells), `predictalot-forecast_<type>_ensemble` (6 per-type ensembles), `predictalot-list_<type>_models` (6 per-type listings). Tool argument shapes are unchanged for shared fields, but covariate variants add `past_covariates` / `future_covariates` kwargs and samples-type tools take `num_samples` instead of `quantile_levels`.

Migration: replace any `/v1/forecast` call with `/v1/univariate/forecast` (most common case — all five models support univariate). Replace `/v1/models` with `/v1/univariate/models` (or any per-type listing). For MCP, swap `forecast_<model>` for `forecast_univariate_<model>` and `list_models` for `list_univariate_models`.

What's new in v0.2.x:
- True multivariate forecasting (chronos-2 / moirai-2 / toto-1) — joint per-(series, channel) quantile predictions instead of per-channel univariate calls.
- Covariate-conditioned forecasting — past covariates (chronos-2, moirai-2), future covariates (chronos-2), and combined past + future (chronos-2).
- Raw-sample-path forecasting (toto-1, sundial-base-128m) for downstream Monte-Carlo workflows.
- Per-type ensembles — every type has its own `forecast/ensemble`, parallelizing only the members that actually implement that type.
- Unauthenticated `/healthz` liveness probe at root.
- v0.2.1 closes a v0.2.0 information-leak where unauthenticated callers could enumerate installed model slugs + load state + `lastUsedSecsAgo` via the per-type `/models` endpoints; all six `/v1/<type>/models` routes now require the bearer (when auth is configured).

Aigate-side updates:
- `docker-compose.yml`: bump `predictalot` → `psyb0t/predictalot:v0.2.1` and `predictalot-cuda` → `psyb0t/predictalot:v0.2.1-cuda`. Healthcheck switched from the removed `/v1/models` to the new `/healthz`.
- `tests/test_predictalot.sh`: rewritten to exercise the new surface — `/v1/univariate/models`, `/v1/multivariate/models` (verifies non-members excluded), `/v1/univariate/forecast` (chronos-2), `/v1/univariate/forecast/ensemble`, non-member-of-type rejection (timesfm-2.5 on `/v1/multivariate/forecast`), and the 26-tool MCP surface.
- Docs: `README.md`, `docs/usage.md`, `docs/services-reference.md`, `docs/mcp-tools.md`, `docs/testing.md`, and `litellm/config/mcp/predictalot.yaml` description rewritten for the type matrix.

## [v2.3.1] — 2026-05-22

**Revert ollama-cuda `OLLAMA_NUM_PARALLEL` default from 50 back to 1.**

v2.3.0 shipped `OLLAMA_NUM_PARALLEL=50` by default on `ollama-cuda`, with README + `.env.example` framing this as a knob tuned for parallel embedding throughput (qwen3-embed-0.6b). Reading ollama's scheduler after shipping showed `server/sched.go:414-417` hard-pins embedding models to `numParallel=1`:

```go
// Embedding models should always be loaded with parallel=1
if req.model.CheckCapabilities(model.CapabilityCompletion) != nil {
    numParallel = 1
}
```

The same file also force-pins `numParallel=1` for `mllama` / `qwen3vl(moe)` / `qwen35(moe)` / `qwen3next` / `lfm2(moe)` / `nemotron_h` architectures. So the 50 default only ever applied to plain chat models — and the documentation explicitly framing it as an embed-throughput knob was wrong.

For callers that actually want parallel embedding throughput in ollama: pass an array to `/api/embed` (or `input: [...]` on `/v1/embeddings`). The runner batches the array in a single forward pass — that's where the speedup lives, not in `NUM_PARALLEL`.

The `pibox` v0.3.1 → v0.7.0 bump that also shipped in v2.3.0 is unaffected and stays.

## [v2.3.0] — 2026-05-22

**Bump psyb0t/pibox v0.3.1 → v0.7.0 (fixes init-marker bug) + bump ollama-cuda NUM_PARALLEL default (reverted in v2.3.1).**

- `pibox-zai` (and `pibox` services in general) — bump `psyb0t/pibox:v0.3.1` → `v0.7.0`. v0.3.1's `init.d` bind-mounted a `.init-done` marker into the config volume, which froze `ANTHROPIC_BASE_URL` at the value seeded on first boot. After bumping `ANTHROPIC_BASE_URL` in `.env`, restarting the container did nothing — pi kept talking to whatever URL was burned in at first boot (in our case `api.anthropic.com` instead of z.ai). v0.3.2+ re-runs the baseurl setup on every boot. We jumped past 0.3.2 to 0.7.0 to pick up unrelated upstream fixes.
- ollama-cuda — `OLLAMA_NUM_PARALLEL` default bumped 1 → 50. Reverted in v2.3.1 — see that entry for the actual scheduler-pinning constraint that made this misleading.

## [v2.2.1] — 2026-05-21

**Docs sweep for v2.1 / v2.2 services. No code, no config schema, no behaviour changes.**

- `README.md` — intro capability list, resource-management section, usage curl examples, Logs-and-Debugging table, troubleshooting section, and the "Full usage guide" link blurb all now thread predictalot / mailbox / telethon / web-search mentions where the surrounding section was listing capabilities.
- `docs/usage.md` — four new sections backing the expanded README links: Web search (SearXNG MCP), Time-series forecasting (predictalot), Email gateway (mailbox), Telegram client (telethon). Each shows the direct REST surface plus pointers to the matching MCP tools and the deeper service reference.
- `docs/testing.md` — "What's Tested" extended with the new predictalot, mailbox, and telethon test suites (and the opt-in mailbox e2e gate).
- `litellm/config/mcp/mcp.yaml` — aggregator description for `mcp_tools` updated to list `search_web` alongside `generate_image` and `generate_tts` (it had been omitted since the SearXNG integration shipped).
- `.env.example` — `TELETHON_LOG_LEVEL` documented (was wired in `docker-compose.yml` but missing from the canonical env reference).

## [v2.2.0] — 2026-05-21

**Add mailbox — IMAP+SMTP gateway.**

- New service `mailbox` at `/mailbox/` via [psyb0t/docker-mailbox](https://github.com/psyb0t/docker-mailbox) `v0.3.0`. Stateless gateway across N email accounts driven by a single YAML config — unified inbox, per-account list/search/CRUD, SMTP send. No database; every read hits the upstream IMAP server live.
- Direct route only — not registered with LiteLLM (no chat/completion surface). `GET /mailbox/health` open; everything else gated on bearer token (`MAILBOX_AUTH_TOKEN`, which must also appear in the mailbox YAML's `auth.tokens:` list).
- MCP enabled by default and registered with LiteLLM's `/mcp/` aggregator. Flat tool set (`mailbox-mailboxes`, `mailbox-inbox`, `mailbox-list_messages`, `mailbox-get_message`, `mailbox-search`, `mailbox-send`, `mailbox-mark_seen`, `mailbox-move`, `mailbox-delete`, …) — every per-account tool takes `mailbox` as a parameter, so the catalog stays flat regardless of how many inboxes are configured.
- Config file holds plaintext IMAP/SMTP passwords + bearer tokens. `MAILBOX_CONFIG` is added to `Makefile`'s `check_file_vars` so the stack refuses to come up if the file isn't present. Template at `mailbox/config.example.yaml`; recommended host path `.data/mailbox/config.yaml` (auto-ignored under `.data/**`).
- New tests in `tests/test_mailbox.sh`: open `/health`, auth enforcement on `/mailboxes`, `/mailboxes` returns ≥1 account, and presence of mailbox MCP tools through the aggregator. All gated on `MAILBOX=1`.
- Nginx route `/mailbox/*` with `RATELIMIT_MAILBOX=60r/m` / `TIMEOUT_MAILBOX=120s` (IMAP fetches on large folders can be slow). New env vars documented in `.env.example`, `docs/services-reference.md`, `docs/mcp-tools.md`, and `README.md`.

## [v2.1.0] — 2026-05-21

**Add predictalot — foundation time-series forecasting.**

- New service `predictalot` (and `predictalot-cuda` GPU variant) at `/predictalot/` via [psyb0t/docker-predictalot](https://github.com/psyb0t/docker-predictalot) `v0.1.1`.
- Five univariate quantile forecasters behind one wire shape: `chronos-2` (Amazon), `timesfm-2.5` (Google), `moirai-2` (Salesforce), `toto-1` (Datadog), `sundial-base-128m` (Tsinghua) — plus `POST /v1/forecast/ensemble` for weighted-mean combinations.
- Direct route only — not registered with LiteLLM (no chat/completion surface). Bearer token auth via `PREDICTALOT_AUTH_TOKEN`.
- MCP enabled by default and registered with LiteLLM's `/mcp/` aggregator. Seven tools surfaced: `predictalot-forecast_{chronos_2,timesfm_2_5,moirai_2,toto_1,sundial_base_128m}`, `predictalot-forecast_ensemble`, `predictalot-list_models`.
- Models lazy-load on first request (HF snapshots to `.data/predictalot/models/`, ~1.4GB total) and auto-unload when idle (`PREDICTALOT_MODEL_IDLE_TIMEOUT=30m` default). CPU and CUDA variants share the same data dir, are mutually exclusive (both bind the `predictalot` network alias), and are gated on `PREDICTALOT=1` / `PREDICTALOT_CUDA=1` respectively.
- New tests in `tests/test_predictalot.sh`: `/v1/models` listing, auth enforcement, chronos-2 single forecast, unknown-model 404, and presence of all MCP tools through the aggregator. All gated on `PREDICTALOT=1` or `PREDICTALOT_CUDA=1`.
- Nginx route `/predictalot/*` with `RATELIMIT_PREDICTALOT=60r/m` / `TIMEOUT_PREDICTALOT=600s` (cold model loads can be slow). New env vars documented in `.env.example`, `docs/services-reference.md`, `docs/mcp-tools.md`, and `README.md`.

## [v2.0.0] — 2026-05-21

**BREAKING: replace `claudebox-zai` with `pibox-zai` (psyb0t/docker-pibox).**

Breaking changes for any caller hitting the removed surfaces:

- LiteLLM models `claudebox-zai-*` → `pibox-zai-glm-{4.5-air,4.7,5.1}`
- Nginx route `/claudebox-zai/*` → `/pibox-zai/*`
- Env vars `CLAUDEBOX_ZAI_*` → `PIBOX_ZAI_*`
- Data dir `.data/claudebox-zai/` → `.data/pibox-zai/`

Migration: rename env vars, move data dir (then `rm .data/pibox-zai/config/.init-done` so init.d re-seeds models.json), update model names in callers, update direct-route consumers.

Why:

- Swap the z.ai/GLM backend from a second `psyb0t/claudebox` instance to `psyb0t/pibox:v0.3.1` ([pi-coding-agent](https://github.com/earendil-works/pi-mono) wrapped in `aicodebox`). Pi speaks the Anthropic wire protocol natively — no Claude Code OAuth/license ceremony required.
- The `-zai` suffix names the upstream backend — future sibling services (e.g. `pibox-or`, `pibox-openai`) can run alongside, each pinned to its own provider.
- New endpoint surface vs. claudebox-zai: pibox uses `/healthz` (not `/health`), adds `/files/*` CRUD (PUT/GET/list/DELETE), exposes MCP at `/mcp/` (opt-in via `PIBOX_MCP_MODE=1`, on by default), and `/run` for native (non-OpenAI-compat) agent execution.
- LiteLLM model names updated: `pibox-zai-glm-4.5-air`, `pibox-zai-glm-4.7`, `pibox-zai-glm-5.1`. Fallback chains updated accordingly.
- Add `tests/test_pibox.sh` — 7 end-to-end tests covering reachability, direct API auth, file ops CRUD, model surfaces (pibox-native + via LiteLLM), chat completion through LiteLLM, and native `/run`. Tests gate on `PIBOX_ZAI=1` and auto-skip otherwise.
- `tests/test_claudebox.sh` stripped of pibox tests and gated on `CLAUDEBOX=1`.
- Provider docs, services reference, MCP tools doc, README, `.env.example`, `recommend-limits.sh`, security tests all updated to the new naming.

## [v1.6.3] — 2026-05-19

**Docs: correct free-tier rate-limit claims.**

- Cerebras: 5 RPM / 1M TPD on 4 models (verified against official docs).
- Mistral: free-tier limits not published — claim removed.
- Cross-verified Groq, OpenRouter, Hugging Face, Cohere claims against current provider documentation.

## [v1.6.2] — 2026-05-18

**Fix nginx prefix-stripping on variable-based `proxy_pass` routes.**

- nginx does not strip the location prefix when `proxy_pass` uses a variable (resolver-deferred upstreams). Added explicit `rewrite` rules to 5 routes: `/claudebox/`, `/claudebox-zai/`, `/stealthy-auto-browse/`, `/librechat/`, `/searxng/`.
- Drop dead `langfuse/.gitkeep` (langfuse service was never landed).

## [v1.6.1] — 2026-05-15

**Bump claudebox v1.13.1-minimal → v1.14.0-minimal: OpenAI-compat wrapper hardening.**

- Multi-turn workspace fix (workspace was lost on follow-up turns).
- SSRF guard on `/openai/v1/files`.
- `finish_reason` mapping (stop / length / tool_calls).
- 400 on unsupported request fields instead of silent ignore.
- `reasoning_effort` snake_case binding now propagates to the agent.

## [v1.6.0] — 2026-05-10

**Security patches + claudebox v1.13.1 + reasoning/vision models + Piper TTS.**

- **Security:** LiteLLM v1.83.5-nightly → v1.83.14-stable.patch.2 fixes CVE-2026-42208 (pre-auth SQL injection in API key verification, CVSS 9.3). Stable cosign-signed channel after the supply-chain incident on the v1.83.x line.
- **Security:** Redis 7.4.8-alpine → 7.4.9-alpine for RCE/UAF CVEs disclosed 2026-05-05. Applied to both `redis` and `stealthy-auto-browse-redis`.
- **Claudebox:** v1.9.0-minimal → v1.13.1-minimal (11 versions, mostly cron+telegram fixes irrelevant to aigate's API-only usage). v1.11.0 surfaces `opusplan` in `/openai/v1/models` — added `claudebox-opusplan` provider entry.
- **New local CUDA reasoning/vision models (4):** `local-ollama-cuda-phi4-reasoning-plus` (Phi-4 Reasoning Plus 14B+RL, ~11GB), `local-ollama-cuda-deepseek-r1-14b` (~9GB), `local-ollama-cuda-qwen3-30b-a3b` (Qwen3 30B MoE / 3B active, ~17GB), `local-ollama-cuda-qwen2.5vl-7b` (Qwen2.5-VL 7B vision, ~5GB). All added to `ollama-pull` for auto-download.
- **New local CPU Piper TTS models (17 across 16 languages):** fills the multilingual TTS gap. Multi-speaker: `en_US-libritts-high` (904 voices), `en_GB-vctk-medium` (109), `fr_FR-mls-medium`, `nl_NL-mls-medium`, `sv_SE-nst-medium`. Single-speaker: de/es/it/pl/pt-BR/ro/ru/tr/uk/vi/zh/ar. Served via the existing `speaches` container.
- **New fallback chains:** 5 chains added to `litellm/config/fallbacks.json` for the new reasoning + vision models.
- No env var or breaking changes.

## [v1.5.0] — 2026-05-08

**Tailscale support (L4 TCPForward) + rename internal docker networks `aigate-*`.**

- Add optional Tailscale container that publishes the aigate stack onto a tailnet via L4 TCPForward — no per-service TLS ceremony required, mesh VPN handles auth + encryption at the network layer.
- Rename docker networks `aicodebox-*` → `aigate-*` for clarity (the stack outgrew the original aicodebox-only naming).

## [v1.4.2] — 2026-04-29

**Bump claudebox to v1.9.0-minimal.**

- `psyb0t/claudebox:v1.8.0-minimal` → `v1.9.0-minimal` for both claudebox and claudebox-zai

## [v1.4.1] — 2026-04-29

**Upgrade Telethon to telethon-plus v0.2.0.**

- Switch image from `psyb0t/telethon:v0.1.1` to `psyb0t/telethon-plus:v0.2.0`
- Update repo links and login command in README and docs to point at docker-telethon-plus

## [v1.4.0] — 2026-04-29

**Add Telethon Telegram client service + MCP integration.**

- Add optional `TELETHON=1` service backed by `psyb0t/telethon-plus` — REST API at `/telethon/` and MCP server with 15 Telegram tools (send/read/edit/delete messages, dialogs, forward, files, group management)
- Add nginx `/telethon/` location block with rewrite rule to strip location prefix before proxying (fix: nginx does not strip prefix when `proxy_pass` uses a variable)
- Add `litellm/config/mcp/telethon.yaml` MCP config pointing at `http://telethon:8080/mcp`
- Add telethon to `litellm/build-config.py` active MCP servers
- Add `--force-recreate` to `make run`, `make run-bg`, `make restart` — baked-in Docker config blocks require full container recreate to pick up env changes
- Add `tests/test_telethon.sh` — health check via MCP `get_me`, tool count assertion, LLM-driven send/verify/delete test (model autonomously calls get_me, send_message, get_messages, delete_messages; post-run check confirms message actually gone)
- Update README, docs, `.env.example` with Telethon service details
- Bump claudebox and claudebox-zai to `v1.8.0-minimal`

## [v1.3.4] — 2026-04-28

**Docs cleanup: remove hardcoded counts.**

- Strip hardcoded service/model counts from README and docs — these go stale on every addition. Counts now sourced from `litellm/config/*` at build time.

## [v1.3.3] — 2026-04-28

**Fix nginx startup crash on disabled optional services.**

- nginx crashed with `host not found in upstream` when `CLAUDEBOX`, `HYBRIDS3`, `LIBRECHAT`, `SEARXNG`, or `BROWSER` were disabled. Fixed by adding Docker DNS resolver (`resolver 127.0.0.11`) and switching all optional upstreams to variable-based `proxy_pass` (defers hostname resolution to request time).

## [v1.3.2] — 2026-04-29

**Fix nginx crash when optional services are disabled; always force-recreate.**

- nginx was crash-looping with `host not found in upstream` when optional services (claudebox, hybrids3, searxng, etc.) were not running — fixed by adding Docker DNS resolver (`resolver 127.0.0.11`) and switching all optional upstreams to variable-based `proxy_pass` (defers hostname resolution to request time)
- `make run` / `make run-bg` / `make restart` now pass `--force-recreate` so env var changes always take effect (Docker config blocks are baked in at deploy time)
- Remove remaining hardcoded counts from README and docs

## [v1.3.1] — 2026-04-25

**Remove Langfuse v3 observability stack.**

- Langfuse v3's event pipeline requires S3 ListObjectsV2, and the JS AWS SDK v3 signs the canonical URI differently than HybridS3 expects when the endpoint URL contains a path prefix (`/storage`). PUTs succeed but LIST operations fail auth verification, making the entire trace pipeline non-functional.
- Remove langfuse-db-init, langfuse-clickhouse, langfuse, langfuse-worker services from docker-compose.yml
- Remove nginx `/langfuse` location block and rate limit zone
- Remove `LANGFUSE=1` profile detection from Makefile
- Remove langfuse from `litellm/build-config.py` active_callbacks
- Delete `litellm/config/callbacks/langfuse.yaml`
- Remove all LANGFUSE env vars from `.env.example`
- Remove langfuse-clickhouse data dir entries from `.gitignore`
- Update README and docs to remove all Langfuse references

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

## [v1.1.1] — 2026-04-25

**proxq v0.9.0, raise rate limit, 30m upstream timeout.**

- Bump proxq to v0.9.0 — fixes timeout config not being applied to the HTTP client.
- Raise nginx proxq rate limit 120r/m → 600r/m for higher-throughput workloads.
- `PROXQ_UPSTREAM_TIMEOUT` default 10m → 30m to accommodate long-running model calls.

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

## [v1.0.1] — 2026-04-24

**OS memory reserve + CPU resource-manager-aware scaling.**

- Reserve 2 GB or 5% of RAM (whichever larger) for the OS before service allocation in `recommend-limits.sh`.
- CPU local services (ollama, speaches, sdcpp) now use `max-of-active + idle overhead` in concurrent RAM calculation — same accounting as the CUDA group.

## [v1.0.0] — 2026-04-24

**Breaking:** Global `CUDA=1` replaced with per-service flags.

- `OLLAMA_CUDA=1` — GPU inference
- `SDCPP_CUDA=1` — GPU image generation
- `SPEACHES_CUDA=1` — GPU STT
- `QWEN_TTS_CUDA=1` — GPU TTS
- Each CUDA service independently toggleable — no more implicit activation
- Docker Compose profiles, Makefile, build-config, resource calculator, tests, and all docs updated
- Fixed flaky tests: removed stale HF image models, fixed CUDA STT input, simplified dolphin-phi test

## [v0.13.3] — 2026-04-23

**Merge ollama pullers into a single service.**

- One `ollama-pull` service with `PULL_CPU` / `PULL_CUDA` flags replaces the separate `ollama-pull` + `ollama-cuda-pull` services.
- CUDA puller now pulls all models (CPU + CUDA) when both flags are on.

## [v0.13.2] — 2026-04-23

**Fallback chains for all 99 models + resource management docs.**

- Complete fallback coverage: every model has a chain. Local preferred over paid for image / TTS / STT. Bogus `cpu-flux-schnell` references removed.
- README expanded with fallback chains, resource management, troubleshooting, and logs sections.

## [v0.12.1] — 2026-04-23

**Fix model prefix to include provider name.**

- Correct v0.12.0 rename: `local-cpu-*` → `local-ollama-cpu-*`, etc. Provider name is now part of the local-model prefix so future local backends (sdcpp, speaches) don't collide.

## [v0.13.1] — 2026-04-23

**Hardcode sdcpp listen address + documentation updates.**

- Hardcode wrapper listen address (`0.0.0.0:7234`) in the Go binary; remove from `docker-compose.yml` env config.
- Comprehensive documentation updates for the sd.cpp integration.

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

## [v0.11.1] — 2026-04-22

**Docs: add LibreChat + MCP tools sections, fix stale counts.**

- Docs-only patch. No code changes.

## [v0.11.0] — 2026-04-22

**MCP media tools, LibreChat web UI, image pinning.**

- MCP server: `generate_image` + `generate_tts` with dynamic model discovery, structured JSON, HybridS3 uploads
- LibreChat web UI at `/librechat/` with LiteLLM backend and MCP tools
- All container images pinned to exact versions
- All provider YAMLs annotated with `model_info.mode` for media models

### Patches

- **v0.11.1** — Docs: add LibreChat + MCP tools docs, fix stale counts (94→92 models, 18→20 tools)

## [v0.10.1] — 2026-04-21

**Docs: correct counts, optional labels, fix broken browser examples.**

- Docs-only patch. No code changes.

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

## [v0.7.3] — 2026-04-18

**Bump proxq.**

- Routine proxq image bump.

## [v0.7.2] — 2026-04-18

**proxq v0.5.1, full proxq config via env.**

- All proxq tunables now configurable via env vars (per-upstream retries, timeouts, OpenAI client package).

## [v0.7.1] — 2026-04-18

**Configurable rate limits + timeouts, proxq v0.5.1.**

- Bump proxq v0.4.1 → v0.5.1 (Go OpenAI client package, job header tracking).
- Nginx rate-limit and timeout values exposed via env vars.

## [v0.6.6] — 2026-04-17

**Fix db.**

- DB-related patch.

## [v0.6.5] — 2026-04-17

**Dynamic config build, all providers/services opt-in via flags.**

- `build-config.py` assembles LiteLLM config from per-provider YAML fragments based on `.env` flags
- All providers/services opt-in: `GROQ=1`, `CEREBRAS=1`, `CLAUDEBOX=1`, etc.
- Docker profiles for hybrids3, browser, ollama, speaches
- Fix postgres data loss: mount `.data/postgres` directly to PGDATA

### Patches

- **v0.6.6** — Fix DB

## [v0.6.4] — 2026-04-17

**Bump service image versions.**

- claudebox: v1.3.0-minimal → v1.4.0-minimal.
- stealthy-auto-browse: v0.21.0 → v0.22.5.

## [v0.6.3] — 2026-04-17

**Enable client-side JSON schema validation in LiteLLM.**

- `enable_json_schema_validation: true` in `litellm_settings` — catches providers that treat `json_schema` as a hint (Gemini 1.5, older Anthropic models) and rejects non-conforming responses on the gateway side.
- README documents the JSON schema validation in the LiteLLM service description.

## [v0.6.2] — 2026-04-16

**Bump claudebox image.**

- Routine claudebox image bump.

## [v0.6.1] — 2026-04-16

**Minor fixes.**

- Misc. patch-level fixes (commit message: `f`). See `git log v0.6.0..v0.6.1` for the diff.

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

## [v0.1.1] — 2026-04-15

**Pin cloudflared image.**

- Pin cloudflared to a specific image tag for reproducibility.

## [v0.1.0] — 2026-04-15

Initial release.
