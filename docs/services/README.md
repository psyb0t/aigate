# Services

One file per service. Each file contains the deep reference (endpoints, models, config, internals) **and** the curl recipes / usage examples for that service.

## Local inference

| Service | Profile flag(s) | What it does |
|---|---|---|
| [llamacpp / llamacpp-cuda](llamacpp.md) | `LLAMACPP=1` / `LLAMACPP_CUDA=1` | GGUF + vision-VLM serving via `llama-server`. Ships **Surya OCR 2** (OCR / layout / table-rec). Server-side PDF input with per-page rasterization + per-mode stitching, per-request `dpi_rescale_to`, and auto `--ctx-size` (probes free VRAM, picks the largest fitting ctx up to the model's trained max). |
| [vllm / vllm-cuda](vllm.md) | `VLLM=1` / `VLLM_CUDA=1` | Text LLM + embeddings via `vllm serve`. Ships Nomic Embed v2 + Qwen3-0.6B. |
| [sd.cpp / sd.cpp-cuda](sdcpp.md) | `SDCPP=1` / `SDCPP_CUDA=1` | Local image generation via stable-diffusion.cpp. |
| [talkies / talkies-cuda](talkies.md) | `TALKIES=1` / `TALKIES_CUDA=1` | Unified ASR + TTS — Whisper / Canary / Parakeet / Nemotron + Kokoro + Qwen3-TTS. |
| [audiolla / audiolla-cuda](audiolla.md) | `AUDIOLLA=1` / `AUDIOLLA_CUDA=1` | Audio production — stem separation, restoration, mastering, MIR, MIDI, text-to-audio generation. |
| [flickies / flickies-cuda](flickies.md) | `FLICKIES=1` / `FLICKIES_CUDA=1` | Video toolkit — lipsync (LatentSync 1.5 + Wav2Lip), face restore (GFPGAN), ffmpeg ops. |
| [predictalot / predictalot-cuda](predictalot.md) | `PREDICTALOT=1` / `PREDICTALOT_CUDA=1` | Foundation time-series forecasting. |
| [decidealot / decidealot-cuda](decidealot.md) | `DECIDEALOT=1` / `DECIDEALOT_CUDA=1` | Typed decisions (`choice` / `score` / `noul` with probabilities) from the local Laya and Von models. |

## Agent execution tooling

| Service | Profile flag(s) | What it does |
|---|---|---|
| [piston](piston.md) | `PISTON=1` | Sandboxed multi-language code execution (50+ langs via [engineer-man/piston](https://github.com/engineer-man/piston) + nsjail isolation). REST + MCP tool. |

## Cloud LLM gateway

| Service | Profile flag(s) | What it does |
|---|---|---|
| [LiteLLM](litellm.md) | _always on_ | Single OpenAI-compatible front door for every backend. Provider routing, fallbacks, rate limits. |
| [MCP tools — media generation](mcp.md) | _auto-enabled_ | `generate_image` / `generate_tts` / `search_web` tools any function-calling model can call. |

For the full LLM/embeddings/STT/TTS model alias table see [`docs/providers.md`](../providers.md).

## Storage + infra

| Service | Profile flag(s) | What it does |
|---|---|---|
| [hybrids3](hybrids3.md) | `HYBRIDS3=1` | S3-compatible + plain-HTTP object storage with presigned URLs + MCP. |
| [browser](browser.md) | `BROWSER=1` | Stealth-browser cluster (stealthy-auto-browse) with HTTP + MCP API. |
| [searxng](searxng.md) | `SEARXNG=1` | Self-hosted meta-search; also powers the MCP `search_web` tool. |

## UIs

| Service | Profile flag(s) | What it does |
|---|---|---|
| [librechat](librechat.md) | `LIBRECHAT=1` | Web UI for chat. Pre-configured with every LiteLLM model + every MCP tool. |
| [claudebox](claudebox.md) | `CLAUDEBOX=1` | Headless Claude Code agent + agentic-coding endpoint. Pibox-zai also documented here. |

## Communications / integrations

| Service | Profile flag(s) | What it does |
|---|---|---|
| [telethon](telethon.md) | `TELETHON=1` | Telegram REST + MCP (send / read / forward / files). |
| [mailbox](mailbox.md) | `MAILBOX=1` | Stateless IMAP+SMTP gateway with MCP. |

## Network / exposure

| Service | Profile flag(s) | What it does |
|---|---|---|
| [tailscale](tailscale.md) | `TAILSCALE=1` | Tailnet-only exposure via `tailscale serve`. |
| [cloudflared](cloudflared.md) | `CLOUDFLARED=1` | Cloudflare Tunnel (quick or named). |

