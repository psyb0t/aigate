# talkies / talkies-cuda — unified speech (ASR + TTS)

> Profile flags: `TALKIES=1` (CPU) / `TALKIES_CUDA=1` (NVIDIA GPU).
> One container, both endpoints: `/v1/audio/transcriptions` and `/v1/audio/speech`.

External image: [`psyb0t/talkies`](https://github.com/psyb0t/docker-talkies) (pinned to `v0.13.2` / `v0.13.2-cuda`). CPU image ships **11 models** — nine ASR (`whisper-large-v3`, `whisper-large-v3-turbo`, `canary-180m-flash`, `nemotron-3.5-asr-0.6b` via parakeet.cpp, the four English Sherpa-ONNX Zipformer variants `sherpa-zipformer-en-left-64` / `-left-128` / `-int8-left-64` / `-int8-left-128`, and `vosk-small-en-us-0.15`) plus two TTS (`kokoro-82m` PyTorch and `kokoro-82m-nvidia` ONNXRuntime). CUDA image ships **19 models** — adds Parakeet-TDT, Canary-1B-Flash, Canary-Qwen-2.5B SALM, and the full Qwen3-TTS line (Base 0.6B + Base 1.7B + CustomVoice 0.6B + CustomVoice 1.7B + VoiceDesign 1.7B). The Sherpa variants use the CUDA execution provider in the CUDA image; Kokoro stays CPU-bound in both images.

## Direct API routes

The direct routes preserve Talkies' raw API and model slugs; they do not pass through LiteLLM. Enable only the variant you need:

| Profile | Gateway prefix | When disabled |
|---|---|---|
| `TALKIES=1` | `/talkies/` | nginx returns `404` |
| `TALKIES_CUDA=1` | `/talkies-cuda/` | nginx returns `404` |

Every route except `/healthz` requires `Authorization: Bearer $AIGATE_TOKEN` by default. `TALKIES_AUTH_TOKEN` and `TALKIES_CUDA_AUTH_TOKEN` optionally replace that shared key for the CPU and CUDA service respectively. The containers have no host port bindings; nginx is the only entry point.

For example, query the CPU service without translating its upstream model slug:

```bash
curl http://localhost:4000/talkies/v1/models \
  -H "Authorization: Bearer $AIGATE_TOKEN"
```

The existing `/v1/audio/transcriptions`, `/v1/audio/speech`, and `/v1/audio/voices` gateway paths retain their LiteLLM/MCP behavior and aliases. Use the direct paths when an application needs a Talkies-specific endpoint or transport behavior.

## Available models

### Transcription (ASR)

| Slug | Backend | Languages | Notes |
|---|---|---|---|
| `local-talkies-whisper-large-v3` | Systran/faster-whisper-large-v3 | multilingual | highest accuracy |
| `local-talkies-whisper-large-v3-turbo` | deepdml/faster-whisper-large-v3-turbo-ct2 | multilingual | ~8× faster than large-v3 |
| `local-talkies-canary-180m-flash` | nvidia/canary-180m-flash | English | FastConformer encoder |
| `local-talkies-nemotron-3.5-asr-0.6b` | nvidia/Nemotron-3.5-ASR-Streaming-0.6B (parakeet.cpp) | 40+ locales | OpenMDW-1.1, per-word timestamps + confidence, WER-0 vs NeMo. C++17/ggml backend; CPU-only in both images at this stage. Operators can register additional parakeet.cpp checkpoints (any Parakeet TDT/CTC/RNNT GGUF in [mudler/parakeet-cpp-gguf](https://huggingface.co/mudler/parakeet-cpp-gguf)) via a custom `models.json`. |
| `local-talkies-cuda-parakeet-tdt-0.6b-v3` | nvidia/parakeet-tdt-0.6b-v3 | 25 European | NeMo RNNT |
| `local-talkies-cuda-canary-1b-flash` | nvidia/canary-1b-flash | EN/DE/FR/ES + EN↔X translation | NeMo multitask |
| `local-talkies-cuda-canary-qwen-2.5b` | nvidia/canary-qwen-2.5b | English | NeMo SALM hybrid ASR+LLM (text-only; no per-word timestamps) |

### Text-to-Speech (TTS)

| Slug | Model | Notes |
|---|---|---|
| `local-talkies-kokoro-tts` / `local-talkies-cuda-kokoro-tts` | hexgrad/Kokoro-82M | PyTorch + misaki G2P. ~41 voices across en/es/fr/hi/it/pt — `af_heart`, `bm_george`, `ef_dora`, etc. Discover via `GET /v1/audio/voices`. Runs on CPU even inside the CUDA image. |
| `local-talkies-kokoro-82m-nvidia` / `local-talkies-cuda-kokoro-82m-nvidia` | nvidia/kokoro-82M-onnx-opt | Same Kokoro weights + same voices, served via ONNXRuntime against NVIDIA's TensorRT-friendly ONNX export + espeak-ng G2P. No PyTorch on the inference hot path. Pick for a leaner runtime; pick PyTorch for misaki-driven G2P quality. |
| `local-talkies-cuda-qwen3-tts` | Qwen/Qwen3-TTS-12Hz-0.6B-Base | Base 0.6B voice cloning. Drop reference `.wav` (10-30 s clean speech) into `${DATA_DIR_TALKIES}/custom-voices/` → use `voice=<filename-without-ext>`. Nested paths supported. Samples `alloy` / `echo` / `fable` baked in. 17 languages (en, zh, ja, ko, fr, de, es, it, pt, ru, vi, th, id, ar, tr, pl, nl). |
| `local-talkies-cuda-qwen3-tts-1.7b` | Qwen/Qwen3-TTS-12Hz-1.7B-Base | Same as above, larger / higher quality. |
| `local-talkies-cuda-qwen3-tts-0.6b-custom` | Qwen/Qwen3-TTS-12Hz-0.6B-CustomVoice | CustomVoice mode. 9 baked-in presets: `Vivian`, `Serena`, `Uncle_Fu`, `Dylan`, `Eric`, `Ryan`, `Aiden`, `Ono_Anna`, `Sohee` — pass as `voice=<preset>`. |
| `local-talkies-cuda-qwen3-tts-1.7b-custom` | Qwen/Qwen3-TTS-12Hz-1.7B-CustomVoice | Same 9 presets + `instructions=<emotion>` (`"happy"`, `"sad"`, …). |
| `local-talkies-cuda-qwen3-tts-1.7b-design` | Qwen/Qwen3-TTS-12Hz-1.7B-VoiceDesign | VoiceDesign mode. Pass `voice="design"` (sentinel) + `instructions=<natural-language description>` (e.g. `"a young energetic female voice"`). |

## curl recipes

### Transcription

```bash
curl http://localhost:4000/audio/transcriptions \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -F "model=local-talkies-whisper-large-v3-turbo" \
  -F "file=@audio.mp3"
```

talkies-specific knobs (any ASR model):
- `response_format=text|json|verbose_json|srt|vtt`
- `diarization=true` — stereo channel-split. Left=L, right=R; segments + words get a `"channel": "L"/"R"` field
- `timestamp_granularities[]=word` — word-level timing on backends that support it (Whisper, Canary, Nemotron)

### Text-to-Speech — Kokoro

```bash
# PyTorch Kokoro (CPU, multiple voices)
curl http://localhost:4000/audio/speech \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{"model": "local-talkies-kokoro-tts", "input": "Hello world", "voice": "af_heart"}' \
  -o speech.mp3

# Kokoro via NVIDIA's ONNXRuntime export (no PyTorch on hot path)
curl http://localhost:4000/audio/speech \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{"model": "local-talkies-kokoro-82m-nvidia", "input": "Hello world", "voice": "af_heart"}' \
  -o speech.mp3
```

### Text-to-Speech — Qwen3-TTS (CUDA)

```bash
# Base 0.6B — voice cloning via baked-in samples or your own reference .wav
curl http://localhost:4000/audio/speech \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{"model": "local-talkies-cuda-qwen3-tts", "input": "Hello world", "voice": "alloy"}' \
  -o speech.mp3

# CustomVoice 1.7B + emotion (one of 9 preset speakers)
curl http://localhost:4000/audio/speech \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{"model": "local-talkies-cuda-qwen3-tts-1.7b-custom",
       "input": "Hello world",
       "voice": "Vivian",
       "instructions": "happy"}' \
  -o speech.mp3

# VoiceDesign — synthesise a voice from a natural-language description
curl http://localhost:4000/audio/speech \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{"model": "local-talkies-cuda-qwen3-tts-1.7b-design",
       "input": "Hello world",
       "voice": "design",
       "instructions": "a young energetic female voice"}' \
  -o speech.mp3
```

### Qwen3-TTS per-request sampling controls

OpenAI-extras (v0.8.0+) via `extra_body` on official SDKs, all Qwen3-TTS modes: `temperature`, `top_k`, `top_p`, `repetition_penalty`, `max_new_tokens`, `do_sample`, plus `language` (for CustomVoice / VoiceDesign). Out-of-range returns HTTP 422.

### Qwen3-TTS PCM streaming

`response_format="pcm"` against any qwen3_tts model streams the raw PCM body via HTTP/1.1 chunked transfer-encoding — TTFA drops to ~200-700 ms vs ~3-8 s buffered. Tune chunk size via `TALKIES_QWEN3_STREAM_CHUNK_SIZE` (default `8` codec-steps-per-chunk).

For the raw CUDA API, send the upstream slug directly to `/talkies-cuda/v1/audio/speech`; nginx does not buffer the PCM response.

### Live ASR WebSocket streaming

Talkies v0.12.0 added live ASR at `ws://<gateway>/talkies/v1/audio/transcriptions/stream` (or `/talkies-cuda/...` for CUDA). Send the same bearer token in the WebSocket upgrade header, then a `start` JSON message naming a streaming-capable upstream slug such as `nemotron-3.5-asr-0.6b`, `sherpa-zipformer-en-left-64`, or `vosk-small-en-us-0.15`, followed by binary PCM16LE, 16 kHz, mono frames. Talkies emits `ready`, `partial`, endpoint/final, and stats events according to its native protocol.

The stream is intentionally distinct from multipart transcription: it accepts only PCM audio and has independently configurable connection, frame, rolling-buffer, idle, and duration limits. nginx forwards WebSocket upgrades and leaves HTTP PCM responses unbuffered.

## Behavior

- **Lazy load + idle TTL unload** — weights download on first request, sit on disk in `${DATA_DIR_TALKIES}` (HF cache layout). A background sweeper unloads any model idle longer than `TALKIES_MODEL_TTL` (default `10m`); next request warm-reloads from disk.
- **Sibling eviction** — only one model resident per talkies container at a time. When request N arrives for a different model, talkies evicts the prior one before loading.
- **Resource-manager aware** — `local-talkies-cuda-*` participates in the `cuda-stt-talkies` group, `local-talkies-*` in `cpu-stt-talkies`. A competing job (LLM, image gen, TTS, other STT) triggers `DELETE /api/ps/{model_id}` for every model before its own load.
- **VAD chunking** — long audio is sliced via Silero VAD into ≤28-second speech regions before each backend forward pass, then results are stitched into one Whisper-shape timeline. Backends that don't support timeline assembly (the SALM `canary-qwen-2.5b`) concatenate per-chunk text without timestamps.
- **Audio preprocessing** — any container/codec is ffmpeg-converted to 16 kHz mono WAV before the backend sees it. Stereo `diarization=true` splits L/R into two mono streams, transcribes each, and time-interleaves the segments with channel tags.
- **OpenAI parity** — every `response_format` returns the correct Content-Type body: `text/plain` for `text`, `application/x-subrip` for `srt`, `text/vtt` for `vtt`, `application/json` for `json` / `verbose_json`. `verbose_json` carries `text`, `language`, `duration`, `segments[{id,start,end,text,channel?,…}]`, `words[{word,start,end,channel?}]`.

## Direct endpoints

| Endpoint | CPU URL | CUDA URL | Description |
|---|---|---|
| Transcribe | `POST /talkies/v1/audio/transcriptions` | `POST /talkies-cuda/v1/audio/transcriptions` | OpenAI-compatible multipart upload using raw Talkies model slugs. |
| Speech | `POST /talkies/v1/audio/speech` | `POST /talkies-cuda/v1/audio/speech` | TTS, including raw Qwen3 PCM streaming on CUDA. |
| Live ASR | `WS /talkies/v1/audio/transcriptions/stream` | `WS /talkies-cuda/v1/audio/transcriptions/stream` | Bidirectional native Talkies PCM stream. |
| List models | `GET /talkies/v1/models` | `GET /talkies-cuda/v1/models` | Configured model IDs. |
| List voices | `GET /talkies/v1/audio/voices` | `GET /talkies-cuda/v1/audio/voices` | Available voices per slug. |
| Loaded models | `GET /talkies/api/ps` | `GET /talkies-cuda/api/ps` | Currently loaded backends + `idle_seconds`. |
| Unload one | `DELETE /talkies/api/ps/{model_id}` | `DELETE /talkies-cuda/api/ps/{model_id}` | Evict one model (URL-encoded ID). |
| Unload all | `POST /talkies/unload` | `POST /talkies-cuda/unload` | Evict every loaded backend. |
| Health | `GET /talkies/healthz` | `GET /talkies-cuda/healthz` | Liveness + device + configured model IDs; no bearer token. |

## Configuration

| Variable | Default | Description |
|---|---|---|
| `TALKIES_MODEL_TTL` / `TALKIES_CUDA_MODEL_TTL` | `10m` | Idle duration before unload (`-1` disables). Accepts bare seconds or Go-style strings (`3h30m5s`, `45m`, `90s`). |
| `TALKIES_SWEEPER_INTERVAL` / `TALKIES_CUDA_SWEEPER_INTERVAL` | `1m` | Idle sweeper poll interval |
| `TALKIES_LOAD_TIMEOUT` / `TALKIES_CUDA_LOAD_TIMEOUT` | `5m` | Max wait for model load before the request errors |
| `TALKIES_MAX_UPLOAD_BYTES` / `TALKIES_CUDA_MAX_UPLOAD_BYTES` | `104857600` | Max audio upload size (bytes) |
| `TALKIES_LOG_LEVEL` / `TALKIES_CUDA_LOG_LEVEL` | `INFO` | Log level |
| `TALKIES_PRELOAD` / `TALKIES_CUDA_PRELOAD` | _empty_ | Comma-separated model_ids to load at boot |
| `TALKIES_VAD_CHUNK_THRESHOLD` / `TALKIES_CUDA_VAD_CHUNK_THRESHOLD` | `30` | Audio length (seconds) above which VAD chunking kicks in |
| `TALKIES_VAD_MAX_SPEECH` / `TALKIES_CUDA_VAD_MAX_SPEECH` | `28` | Max chunk length fed to a single forward pass |
| `TALKIES_AUTH_TOKEN` / `TALKIES_CUDA_AUTH_TOKEN` | `AIGATE_TOKEN` | Direct-route bearer token. Use a separate variant token only when needed. |
| `TALKIES_BLOCK_PRIVATE_DOWNLOADS` / `TALKIES_CUDA_BLOCK_PRIVATE_DOWNLOADS` | `true` | Blocks private, loopback, link-local, multicast, and metadata `file_path` URL targets. Set `false` only for trusted callers that require private-network downloads. |
| `TALKIES_STREAM_MAX_CONNECTIONS` / `TALKIES_CUDA_STREAM_MAX_CONNECTIONS` | `4` | Concurrent live-ASR WebSockets per service. |
| `TALKIES_STREAM_MAX_FRAME_BYTES` / `TALKIES_CUDA_STREAM_MAX_FRAME_BYTES` | `65536` | Largest accepted binary PCM frame (2–16777216). |
| `TALKIES_STREAM_MAX_BUFFER_SECONDS` / `TALKIES_CUDA_STREAM_MAX_BUFFER_SECONDS` | `5` | Rolling Whisper buffer length (0.1–300 seconds). |
| `TALKIES_STREAM_IDLE_TIMEOUT` / `TALKIES_CUDA_STREAM_IDLE_TIMEOUT` | `30s` | Maximum wait between client messages. |
| `TALKIES_STREAM_MAX_DURATION` / `TALKIES_CUDA_STREAM_MAX_DURATION` | `4h` | Maximum accepted PCM duration; keep it within the matching nginx timeout. |
| `TALKIES_CUDA_QWEN3_STREAM_CHUNK_SIZE` | `8` | Qwen3-TTS PCM streaming chunk size (codec steps per chunk). `TALKIES_QWEN3_STREAM_CHUNK_SIZE` remains a backward-compatible fallback. |
| `TIMEOUT_TALKIES` / `TIMEOUT_TALKIES_CUDA` | `4h` | nginx direct-route read/send timeout for HTTP and WebSocket streams. |
| `TALKIES_MEM_LIMIT` / `TALKIES_CUDA_MEM_LIMIT` | `8g` / `12g` | Container memory limit |
| `TALKIES_CPUS` / `TALKIES_CUDA_CPUS` | `4.0` | Container CPU limit |
| `DATA_DIR_TALKIES` | `${DATA_DIR}/talkies` | Bind-mount root for talkies' `/data` dir. Contains `hf/hub/models--*/` (HF cache, shared by CPU + CUDA) and — for CUDA — `custom-voices/<name>.wav` (Qwen3-TTS reference voices). |

Plus all the hosted cloud transcription / TTS slugs registered through LiteLLM live alongside talkies (`groq-whisper-large-v3-turbo`, `openai-tts-1`, etc.) — see [docs/providers.md](../providers.md) for the full alias table.
