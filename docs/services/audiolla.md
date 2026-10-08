# audiolla (optional, `AUDIOLLA=1` / `AUDIOLLA_CUDA=1`)

Self-hosted **audio-production** REST + MCP API (v1.0.1+). Stem separation (Demucs / UVR), restoration (UVR de-reverb / de-echo / de-noise), mastering (matchering + pedalboard chains), MIR analysis (librosa: BPM, key, LUFS, beats, onsets, melody, chords, segments), DSP transforms (sox + ffmpeg), loudness normalization, speech enhancement (DeepFilterNet), VAD (silero), diarization (pyannote), CLAP embeddings + zero-shot classification, AudioSet tagging (AST), audio→MIDI (basic-pitch), MIDI compose / inspect / transform / render via fluidsynth. **CUDA-only text-to-audio generation** under `POST /v1/audio/generate/{engine}`: `stable-audio-open` (Stability Community Licence), `musicgen-small` / `musicgen-medium` (CC-BY-NC — gated on `AUDIOLLA_ENABLE_NONCOMMERCIAL=1`), `riffusion` (CreativeML OpenRAIL-M), `audioldm2` (CC-BY 4.0 — commercial-safe, no opt-in).

Curated YAML workflow presets ship in-image (`master-for-spotify`, `podcast-cleanup`, `vocal-cleanup`). Ad-hoc op-chain pipelines run server-side — intermediates stay in memory between steps, no re-upload. Async jobs + webhooks for long-running work. Direct nginx route, not via LiteLLM. MCP is aggregated into `/mcp/`.

**API contract (breaking from v0.23.x):** every audio endpoint takes a **JSON body**. The only multipart/raw-bytes route is `PUT /v1/files/{path}` for staging. Input is `file_path` (FILES_DIR-relative, after staging) XOR `file_url` (server fetches, subject to `AUDIOLLA_FETCH_MODE`). Audio-producing tools require **`output_path` XOR `output_url`** (`output_path` stages under `${DATA_DIR_AUDIOLLA}/files` — caller downloads via `GET /v1/files/<path>`; `output_url` PUTs to a presigned URL). The pre-1.0 `*_base64` response fields are gone — pull results from the staging area.

CPU and CUDA variants run **side-by-side** on distinct routes and aliases — `/audiolla/` → CPU container, `/audiolla-cuda/` → GPU container. Enable independently via `AUDIOLLA=1` and/or `AUDIOLLA_CUDA=1`. CUDA needs `nvidia-container-toolkit` and is significantly faster on Demucs, UVR, pyannote, basic-pitch, DeepFilterNet, CLAP. Both share `${DATA_DIR_AUDIOLLA}` for the weight cache, so the second variant to boot reuses the first's downloads with zero re-fetch.

Aigate pins Audiolla v2.0.0 for CPU and CUDA. Staged uploads and outputs under `${DATA_DIR_AUDIOLLA}/files` expire after 24 hours by file modification time. Download results before they expire. Model caches are excluded. `AUDIOLLA_FILES_TTL` sets a different duration, such as `72h`; `0` disables file cleanup. Reading a file does not renew its lifetime. The sweeper checks every `AUDIOLLA_SWEEPER_INTERVAL` seconds, default 60, and active processing or downloads can postpone cleanup across both variants.

Upgrading also applies this expiry to existing staged files. Set `AUDIOLLA_FILES_TTL=0` in `.env` before upgrading to retain the old indefinite storage behavior. Once the pinned images are available locally, `make restart-audiolla` applies image and configuration changes to enabled Audiolla variants only, without rebuilding, pulling images, or recreating the rest of the stack. For a normal fresh deployment, use `make run-bg`.

| Endpoint        | CPU (`AUDIOLLA=1`)                   | CUDA (`AUDIOLLA_CUDA=1`)                   |
| --------------- | ------------------------------------ | ------------------------------------------ |
| REST            | `http://localhost:4000/audiolla/*`   | `http://localhost:4000/audiolla-cuda/*`    |
| MCP (direct)    | `http://localhost:4000/audiolla/v1/mcp` | `http://localhost:4000/audiolla-cuda/v1/mcp` |
| MCP (aggregated)| `http://localhost:4000/mcp/` (`audiolla-*` prefix) | `http://localhost:4000/mcp/` (`audiolla_cuda-*` prefix) |
| Health          | `http://localhost:4000/audiolla/healthz` | `http://localhost:4000/audiolla-cuda/healthz` |
| Catalog         | `GET /audiolla/v1/catalog`           |
| Engine lifecycle| `GET /audiolla/v1/ps`, `DELETE /audiolla/v1/ps/{engine}`, `POST /audiolla/v1/unload` |

Auth: `Authorization: Bearer $AUDIOLLA_AUTH_TOKEN` (defaults to `AIGATE_TOKEN`). Pyannote diarization additionally needs `HF_TOKEN` + the user accepting model terms at huggingface.co/pyannote/speaker-diarization-3.1.

Full API — every endpoint, every request/response shape, all 90+ routes, generation engines, presets, pipelines, MCP tool list, server-side URL fetch policy, the v0.23→v1.0 migration cheatsheet, and the canonical `openapi.yaml`: **[docker-audiolla README](https://github.com/psyb0t/docker-audiolla)**.

Env vars: `AUDIOLLA_AUTH_TOKEN`, `AUDIOLLA_DEVICE`, `AUDIOLLA_ENABLED_ENGINES`, `AUDIOLLA_PRELOAD`, `AUDIOLLA_ENGINE_TTL`, `AUDIOLLA_FILES_TTL`, `AUDIOLLA_SWEEPER_INTERVAL`, `AUDIOLLA_MAX_UPLOAD_BYTES`, `AUDIOLLA_FETCH_*` (server-side URL fetch policy), `AUDIOLLA_JOB_TTL`, `AUDIOLLA_JOB_MAX_CONCURRENT`, `AUDIOLLA_ENABLE_NONCOMMERCIAL` (CC-BY-NC opt-in for MusicGen), `DATA_DIR_AUDIOLLA`, `TIMEOUT_AUDIOLLA`. Full reference in [`.env.example`](../../.env.example).

---


## Usage

### Audio production (audiolla)

With `AUDIOLLA=1` (or `AUDIOLLA_CUDA=1` for GPU) the `/audiolla/` route exposes a self-hosted audio-production stack — stem separation, restoration, mastering, MIR analysis, DSP transforms, loudness, speech enhancement, diarization, MIDI transcription + composition, **plus text-to-audio generation** (stable-audio-open / musicgen / riffusion / audioldm2 on CUDA). Curated YAML workflow presets and ad-hoc op-chain pipelines run server-side. Direct nginx route, bearer auth via `AUDIOLLA_AUTH_TOKEN`. MCP is aggregated into `/mcp/`.

**v1.0.1 API:** every audio endpoint takes a **JSON body**. The only multipart route is `PUT /v1/files/{path}` for staging raw bytes. Audio-producing endpoints require `output_path` xor `output_url` (no more raw bytes in responses). To run a smoke test you stage the file first, then POST referencing it.

```bash
# 1) stage the source file (this is the ONLY route that takes bytes on the wire)
curl -X PUT http://localhost:4000/audiolla/v1/files/uploads/song.wav \
  -H "Authorization: Bearer $AUDIOLLA_AUTH_TOKEN" \
  -H "Content-Type: application/octet-stream" \
  --data-binary @song.wav

# 2) detect chords + key — JSON in, JSON out (analyze endpoints don't produce audio,
#    so no output_path is needed)
curl -X POST http://localhost:4000/audiolla/v1/audio/chords \
  -H "Authorization: Bearer $AUDIOLLA_AUTH_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"file_path":"uploads/song.wav"}'

# 3) stem-separate (4 stems) — audio-producing, so output_path is required
curl -X POST http://localhost:4000/audiolla/v1/audio/separate \
  -H "Authorization: Bearer $AUDIOLLA_AUTH_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"file_path":"uploads/song.wav","engine":"htdemucs","output_paths":{
      "drums":"out/drums.wav","bass":"out/bass.wav",
      "other":"out/other.wav","vocals":"out/vocals.wav"}}'

# 4) download the resulting stem
curl -o vocals.wav http://localhost:4000/audiolla/v1/files/out/vocals.wav \
  -H "Authorization: Bearer $AUDIOLLA_AUTH_TOKEN"

# inspect configured engines + their load state
curl http://localhost:4000/audiolla/v1/engines \
  -H "Authorization: Bearer $AUDIOLLA_AUTH_TOKEN"
```

MusicGen weights are CC-BY-NC 4.0; the engine refuses to load unless `AUDIOLLA_ENABLE_NONCOMMERCIAL=1` is set on the container. AudioLDM 2 is CC-BY 4.0 — no opt-in needed.

Full API — every endpoint, every engine, generators, presets, ad-hoc pipelines, async jobs, fetch policy, MCP tool list, the v0.23 → v1.0 migration cheatsheet: **[docker-audiolla README](https://github.com/psyb0t/docker-audiolla)**.

---

