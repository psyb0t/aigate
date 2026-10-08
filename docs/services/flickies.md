# flickies (optional, `FLICKIES=1` / `FLICKIES_CUDA=1`)

Self-hosted **video toolkit** REST + MCP API. Sibling of [audiolla](audiolla.md) (audio) and [talkies](talkies.md) (speech) — same wire format, same async-job model, same bind-mount-`/data` story.

- 👄 **Lipsync** — `LatentSync 1.5` (ByteDance, Apache-2.0, default on CUDA, ~8 GB VRAM) and `wav2lip` / `wav2lip-gan` (Rudrabha, fast and low-VRAM, **LRS2 non-commercial** — gated on `FLICKIES_ENABLE_NONCOMMERCIAL=1`).
- 🧹 **Face restore** — `GFPGAN v1.4` (TencentARC, Apache-2.0). Chains after Wav2Lip to fix the soft 96×96 mouth crop, or used stand-alone on a full video.
- ⚙️ **ffmpeg ops** (CPU) — `trim`, `concat`, `transcode` (incl. gif + fps + codec change), `scale`, `mux_audio`, `extract_audio`, `thumbnail_grid`.
- 📋 **Info** — ffprobe metadata at `POST /v1/video/info` (duration, codec, fps, dimensions, bitrate).
- 🐳 **Hot-swap eviction + idle unload** — one GPU pool. Different model requested → current model evicted. Idle longer than `FLICKIES_IDLE_UNLOAD_SECS` (default 600) → unloaded by the sweeper.

**API contract:** every video endpoint takes a **JSON body**. The only multipart/raw-bytes route is `PUT /v1/files/{path}` for staging. Input is `file_path` (FILES_DIR-relative, after staging) XOR `file_url` (server fetches, subject to `FLICKIES_ALLOW_PRIVATE_FETCH`). Video-producing tools require **`output_path` XOR `output_url`** (`output_path` stages under `${DATA_DIR_FLICKIES}/files` — caller downloads via `GET /v1/files/<path>`; `output_url` PUTs to a presigned URL).

CPU and CUDA variants run **side-by-side** on distinct routes and aliases — `/flickies/` → CPU container, `/flickies-cuda/` → GPU container. Enable independently via `FLICKIES=1` and/or `FLICKIES_CUDA=1`. CUDA needs `nvidia-container-toolkit`. **GFPGAN + LatentSync 1.5 are CUDA-only** — the CPU image refuses to load them. CPU image runs all ffmpeg ops + Wav2Lip-CPU (~44 s for a 3 s clip; usable for short clips). Both variants share `${DATA_DIR_FLICKIES}` for the weight cache, so the second variant to boot reuses the first's downloads with zero re-fetch.

Tested hardware ceiling: **RTX 3060 12 GB** — fits LatentSync 1.5 (~8 GB) with headroom; the Wav2Lip + GFPGAN chain peaks at ~5 GB.

| Endpoint        | CPU (`FLICKIES=1`)                   | CUDA (`FLICKIES_CUDA=1`)                   |
| --------------- | ------------------------------------ | ------------------------------------------ |
| REST            | `http://localhost:4000/flickies/*`   | `http://localhost:4000/flickies-cuda/*`    |
| MCP (direct)    | `http://localhost:4000/flickies/v1/mcp` | `http://localhost:4000/flickies-cuda/v1/mcp` |
| MCP (aggregated)| `http://localhost:4000/mcp/` (`flickies-*` prefix) | `http://localhost:4000/mcp/` (`flickies_cuda-*` prefix) |
| Health          | `http://localhost:4000/flickies/healthz` | `http://localhost:4000/flickies-cuda/healthz` |
| Engines         | `GET /flickies/v1/engines`           |
| Engine evict    | `POST /flickies/v1/engines/{slug}`   |

Auth: `Authorization: Bearer $FLICKIES_AUTH_TOKEN` (defaults to `AIGATE_TOKEN`).

Weights are fetched lazily on first call per engine into `${DATA_DIR_FLICKIES}/models/<slug>/`: S3FD ~85 MB, Wav2Lip ~436 MB each, GFPGAN v1.4 ~350 MB, LatentSync model.tar ~5 GB. `FLICKIES_OFFLINE=1` disables auto-download — stage weights yourself by dropping them under the matching `models/<slug>/` subdir.

Full API — every endpoint, every engine, the JSON body shape for each tool, the `openapi.yaml` contract, the generated Go + Python clients: **[docker-flickies README](https://github.com/psyb0t/docker-flickies)**.

Env vars: `FLICKIES_AUTH_TOKEN`, `FLICKIES_DEVICE`, `FLICKIES_ENABLED_ENGINES`, `FLICKIES_PREFETCH_ALL` (boot-time weight prefetch, cuts cold-call latency), `FLICKIES_IDLE_UNLOAD_SECS`, `FLICKIES_MAX_UPLOAD_BYTES`, `FLICKIES_RATE_LIMIT_PER_MIN`, `FLICKIES_FETCH_TIMEOUT_SECS`, `FLICKIES_ALLOW_PRIVATE_FETCH`, `FLICKIES_OFFLINE`, `FLICKIES_WEBHOOK_SECRET`, `FLICKIES_LOG_LEVEL`, `FLICKIES_LOG_FILE` (rotating JSON log), `FLICKIES_ENABLE_NONCOMMERCIAL` (LRS2 opt-in for Wav2Lip / Wav2Lip-GAN), `DATA_DIR_FLICKIES`, `TIMEOUT_FLICKIES`. Full reference in [`.env.example`](../../.env.example).

---


## Usage

### Lipsync + face restore chain (flickies-cuda)

With `FLICKIES_CUDA=1` the `/flickies-cuda/` route exposes LatentSync 1.5 (default) plus Wav2Lip / GFPGAN. Direct nginx route, bearer auth via `FLICKIES_AUTH_TOKEN`. MCP is aggregated into `/mcp/`.

```bash
# 1) stage the source video + the new audio track (the ONLY routes that take bytes on the wire)
curl -X PUT http://localhost:4000/flickies-cuda/v1/files/uploads/clip.mp4 \
  -H "Authorization: Bearer $FLICKIES_AUTH_TOKEN" \
  -H "Content-Type: application/octet-stream" \
  --data-binary @clip.mp4

curl -X PUT http://localhost:4000/flickies-cuda/v1/files/uploads/voice.wav \
  -H "Authorization: Bearer $FLICKIES_AUTH_TOKEN" \
  -H "Content-Type: application/octet-stream" \
  --data-binary @voice.wav

# 2) lipsync with LatentSync 1.5 (Apache-2.0 default, no gate)
curl -X POST http://localhost:4000/flickies-cuda/v1/video/lipsync \
  -H "Authorization: Bearer $FLICKIES_AUTH_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
        "engine": "latentsync-1.5",
        "video_path": "uploads/clip.mp4",
        "audio_path": "uploads/voice.wav",
        "output_path": "out/clip_synced.mp4"
      }'

# 3) (optional) GFPGAN face-restore the result for sharper mouth detail
curl -X POST http://localhost:4000/flickies-cuda/v1/video/restore \
  -H "Authorization: Bearer $FLICKIES_AUTH_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
        "engine": "gfpgan",
        "file_path": "out/clip_synced.mp4",
        "output_path": "out/clip_synced_restored.mp4"
      }'

# 4) download the result
curl -o final.mp4 http://localhost:4000/flickies-cuda/v1/files/out/clip_synced_restored.mp4 \
  -H "Authorization: Bearer $FLICKIES_AUTH_TOKEN"

# inspect configured engines + their load state
curl http://localhost:4000/flickies-cuda/v1/engines \
  -H "Authorization: Bearer $FLICKIES_AUTH_TOKEN"
```

### ffmpeg ops (CPU image is enough)

```bash
# trim 5s starting at 2s
curl -X POST http://localhost:4000/flickies/v1/video/trim \
  -H "Authorization: Bearer $FLICKIES_AUTH_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"file_path":"uploads/clip.mp4","start_sec":2,"end_sec":7,"output_path":"out/clip_5s.mp4"}'

# transcode to GIF
curl -X POST http://localhost:4000/flickies/v1/video/transcode \
  -H "Authorization: Bearer $FLICKIES_AUTH_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"file_path":"uploads/clip.mp4","format":"gif","fps":12,"output_path":"out/clip.gif"}'

# inspect metadata
curl -X POST http://localhost:4000/flickies/v1/video/info \
  -H "Authorization: Bearer $FLICKIES_AUTH_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"file_path":"uploads/clip.mp4"}'
```

Wav2Lip weights are trained on LRS2 (non-commercial); the server refuses to load them unless `FLICKIES_ENABLE_NONCOMMERCIAL=1` is set on the container. LatentSync 1.5 (Apache-2.0) and GFPGAN (Apache-2.0) are commercial-safe — no opt-in needed.

Full API — every endpoint, every engine, the `openapi.yaml` contract, the generated Go + Python clients: **[docker-flickies README](https://github.com/psyb0t/docker-flickies)**.

---
