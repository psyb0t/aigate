# Documentation

Top-level docs index. See the per-feature pages below.

## Start here

- [Top-level README](../README.md) — what aigate is, what services it includes, the security/exposure story, how to enable each profile, contribution flow.

## By service

Every service has its own page under [`services/`](services/) — deep reference (endpoints, models, config, internals) **and** curl recipes / usage examples for that service, all in one file. See [`services/README.md`](services/README.md) for the full index, organised by purpose (local inference / cloud gateway / storage / UIs / etc).

The big ones at a glance:

- [llamacpp / llamacpp-cuda](services/llamacpp.md) — Surya OCR 2 (OCR / layout / table-rec) and any other GGUF VLM
- [vllm / vllm-cuda](services/vllm.md) — text LLMs + embeddings via `vllm serve`
- [talkies / talkies-cuda](services/talkies.md) — Whisper / Canary / Parakeet / Nemotron + Kokoro + Qwen3-TTS
- [audiolla / audiolla-cuda](services/audiolla.md) — audio production REST + MCP (stem sep / mastering / MIR / MIDI / text-to-audio)
- [flickies / flickies-cuda](services/flickies.md) — video toolkit REST + MCP (lipsync via LatentSync 1.5 + Wav2Lip, GFPGAN face restore, ffmpeg ops)
- [sd.cpp](services/sdcpp.md) — local image generation
- [LiteLLM](services/litellm.md) — OpenAI-compatible gateway
- [piston](services/piston.md) — sandboxed multi-language code execution (50+ langs), nsjail isolation, REST + MCP tool any function-calling LLM can call

## By topic

- [Configuration](../README.md#2-configure). `make bootstrap` creates `.env` from `.env.example`. Change what you can through `.env`; for compose changes write `docker-compose.override.yml`, which is gitignored and merges last. `docker-compose.yml` itself is tracked and an update overwrites edits to it.
- [Providers + model aliases](providers.md) — every LLM / embedding / ASR / TTS model registered through LiteLLM, with its slug and provider.
- [Testing](testing.md) — what the test suite covers per service + how to run it.
- [Resource management](resource-management.md) — cross-cutting LiteLLM resource_manager: single-job-per-hardware semaphores, competing-group eviction, who unloads whom.

