# Providers and Models

Providers are configured via YAML fragments in `litellm/config/providers/`. `make run` assembles them into `litellm/config.yaml` (auto-generated, gitignored). Free-tier providers are tried first in fallback chains. Each provider is opt-in: set its flag to `1` in `.env` (e.g. `GROQ=1`) and fill in the API key. The flag activates the provider — the key alone does nothing.

## Groq (free tier)

Sign up: [console.groq.com](https://console.groq.com) — no credit card required.

| Model                          | Alias                               | Notes           |
| ------------------------------ | ----------------------------------- | --------------- |
| llama-3.1-8b-instant           | `groq-llama-3.1-8b`                 | fast            |
| llama-3.3-70b-versatile        | `groq-llama-3.3-70b`                |                 |
| llama-4-scout-17b-16e-instruct | `groq-llama-4-scout`                | multimodal      |
| moonshotai/kimi-k2-instruct    | `groq-kimi-k2`                      |                 |
| openai/gpt-oss-20b             | `groq-gpt-oss-20b`                  |                 |
| openai/gpt-oss-120b            | `groq-gpt-oss-120b`                 |                 |
| qwen/qwen3-32b                 | `groq-qwen3-32b`                    |                 |
| compound-beta                  | `groq-compound`                     | tool use        |
| compound-beta-mini             | `groq-compound-mini`                | tool use, fast  |
| whisper-large-v3               | `groq-whisper-large-v3`             | transcription   |
| whisper-large-v3-turbo         | `groq-whisper-large-v3-turbo`       | transcription, fast |

## Cerebras (free tier)

Sign up: [cloud.cerebras.ai](https://cloud.cerebras.ai) — 1M tokens/day free, no credit card required. Among the fastest inference available (Llama 3.1 8B ~1,800 t/s, Qwen3 235B ~1,400 t/s).

| Model                          | Alias                    | Notes                         |
| ------------------------------ | ------------------------ | ----------------------------- |
| qwen-3-235b-a22b-instruct-2507 | `cerebras-qwen3-235b`    | flagship, very fast           |
| gpt-oss-120b                   | `cerebras-gpt-oss-120b`  | rate-limited on free tier     |
| zai-glm-4.7                    | `cerebras-glm-4.7`       | rate-limited on free tier     |
| llama3.1-8b                    | `cerebras-llama-3.1-8b`  | fastest option on this tier   |

## OpenRouter (free tier)

Sign up: [openrouter.ai](https://openrouter.ai) — 50 req/day free (no credits), 1000 req/day with $10+ loaded.

| Model                                | Alias              |
| ------------------------------------ | ------------------ |
| nousresearch/hermes-3-llama-3.1-405b | `or-hermes-3-405b` |
| qwen/qwen3-coder                     | `or-qwen3-coder`   |
| qwen/qwen3-next-80b-a3b-instruct     | `or-qwen3-80b`     |
| nvidia/nemotron-3-super-120b-a12b    | `or-nemotron-120b` |
| minimax/minimax-m2.5                 | `or-minimax-m2.5`  |
| meta-llama/llama-3.3-70b-instruct    | `or-llama-3.3-70b` |
| openai/gpt-oss-120b                  | `or-gpt-oss-120b`  |
| openai/gpt-oss-20b                   | `or-gpt-oss-20b`   |

## HuggingFace Inference Providers (free tier)

Sign up: [huggingface.co](https://huggingface.co/settings/tokens) — free tier with rate limits per provider.

| Model                                        | Alias                  | Notes          |
| -------------------------------------------- | ---------------------- | -------------- |
| meta-llama/Llama-3.1-8B-Instruct             | `hf-llama-3.1-8b`      |                |
| meta-llama/Llama-3.3-70B-Instruct            | `hf-llama-3.3-70b`     |                |
| meta-llama/Llama-4-Scout-17B-16E-Instruct    | `hf-llama-4-scout`     | multimodal     |
| Qwen/Qwen3-8B                                | `hf-qwen3-8b`          |                |
| Qwen/QwQ-32B                                 | `hf-qwq-32b`           | reasoning      |
| deepseek-ai/DeepSeek-R1                      | `hf-deepseek-r1`       | reasoning      |
| Qwen/Qwen2.5-VL-72B-Instruct                 | `hf-qwen-vl-72b`       | multimodal     |
| Qwen/Qwen2.5-VL-7B-Instruct                  | `hf-qwen3-vl-8b`       | multimodal     |
| google/gemma-3-12b-it                        | `hf-gemma-3-12b`       | multimodal     |
| black-forest-labs/FLUX.1-schnell             | `hf-flux-schnell`      | image gen, fast |

## Mistral AI (free tier: 1B tokens/month, 60 RPM)

Sign up: [console.mistral.ai](https://console.mistral.ai) — no credit card required for free models.

| Model                 | Alias              | Tier | Notes              |
| --------------------- | ------------------ | ---- | ------------------ |
| mistral-large-2512    | `mistral-large`    | free |                    |
| mistral-small-2603    | `mistral-small`    | free | multimodal         |
| ministral-3-8b-2512   | `ministral-8b`     | free | fast               |
| magistral-medium-2509 | `magistral-medium` | paid | reasoning          |
| magistral-small-2509  | `magistral-small`  | paid | reasoning          |
| devstral-2512         | `devstral`         | paid | coding agent       |
| codestral-2508        | `codestral`        | paid | code completion    |
| mistral-embed         | `mistral-embed`    | free | embeddings         |
| voxtral-small-25-07   | `voxtral-small`    | -    | audio transcription |

## Cohere (trial: 1K req/day, 20 RPM — all models included)

Sign up: [dashboard.cohere.com](https://dashboard.cohere.com) — no credit card required. Trial key gives access to all models.

| Model                  | Alias                   | Notes                        |
| ---------------------- | ----------------------- | ---------------------------- |
| command-a-03-2025      | `cohere-command-a`      | flagship, 256K ctx, tool use |
| command-r-plus-08-2024 | `cohere-command-r-plus` | strong, 128K ctx             |
| command-r-08-2024      | `cohere-command-r`      | balanced                     |
| command-r7b-12-2024    | `cohere-command-r7b`    | fast, small                  |
| c4ai-aya-expanse-32b   | `cohere-aya-32b`        | multilingual (23 languages)  |
| embed-v4.0             | `cohere-embed`          | embeddings                   |
| rerank-v3.5            | `cohere-rerank`         | reranking                    |

## Claudebox (requires Claude subscription or API key)

Full Claude Code CLI in API mode — not a standard LLM API. Each request runs Claude Code's full agentic loop with tool use, file I/O, shell access, and web browsing. Authentication: either an OAuth token from a Claude Pro/Max/Team subscription, or an Anthropic API key (pay-per-use).

Set up with `claude setup-token` or generate at [console.anthropic.com](https://console.anthropic.com/settings/keys).

| Alias              | Underlying model      | Best for                                        |
| ------------------ | --------------------- | ----------------------------------------------- |
| `claudebox-haiku`  | Claude Haiku 4.5      | Quick tasks, high-volume, minimal token use      |
| `claudebox-sonnet` | Claude Sonnet 4.6     | Daily coding, balanced speed/intelligence        |
| `claudebox-opus`   | Claude Opus 4.6       | Complex reasoning, architecture, hard debugging  |

## Claudebox GLM — via z.ai (requires z.ai account)

[z.ai](https://z.ai) provides an Anthropic-compatible API backed by GLM models. Routed through a second claudebox instance pointed at z.ai — same agentic capabilities (shell, files, tools) as the OAuth instance above.

| Alias                   | Underlying model |
| ----------------------- | ---------------- |
| `claudebox-glm-4.5-air` | GLM-4.5-Air      |
| `claudebox-glm-4.7`     | GLM-4.7          |
| `claudebox-glm-5.1`     | GLM-5.1          |

## Anthropic (optional, API key required)

Standard Anthropic API — not agentic, just LLM inference. Sign up: [console.anthropic.com](https://console.anthropic.com).

| Alias                        | Model             | Notes      |
| ---------------------------- | ----------------- | ---------- |
| `anthropic-claude-opus-4`    | claude-opus-4-6   | multimodal |
| `anthropic-claude-sonnet-4`  | claude-sonnet-4-6 | multimodal |
| `anthropic-claude-haiku-4`   | claude-haiku-4-5  | multimodal |

## OpenAI (optional, API key required)

Sign up: [platform.openai.com](https://platform.openai.com).

| Alias                  | Model       | Notes          |
| ---------------------- | ----------- | -------------- |
| `openai-gpt-4o`        | gpt-4o      | multimodal     |
| `openai-gpt-4o-mini`   | gpt-4o-mini | multimodal     |
| `openai-o3`            | o3          | reasoning      |
| `openai-o3-mini`       | o3-mini     | reasoning      |
| `openai-dall-e-3`      | dall-e-3    | image gen      |
| `openai-gpt-image-1`   | gpt-image-1 | image gen      |
| `openai-whisper`       | whisper-1   | transcription  |
| `openai-tts-1`         | tts-1       | text-to-speech |
| `openai-tts-1-hd`      | tts-1-hd    | text-to-speech |

---

## Ollama (local CPU — `OLLAMA=1`)

Models are downloaded on first start and cached in `.data/ollama/`. No GPU required.

| Alias | Model | Notes |
| ----- | ----- | ----- |
| `local-ollama-cpu-llama3.2-3b` | llama3.2:3b | general chat, ~2GB RAM |
| `local-ollama-cpu-qwen3-4b` | qwen3:4b | general chat, thinking mode, ~2.6GB RAM |
| `local-ollama-cpu-smollm2-1.7b` | smollm2:1.7b | general chat, smallest, ~1GB RAM |
| `local-ollama-cpu-qwen2.5-coder-1.5b` | qwen2.5-coder:1.5b | code, ~1GB RAM |
| `local-ollama-cpu-qwen2.5-coder-3b` | qwen2.5-coder:3b | code, ~2GB RAM |
| `local-ollama-cpu-phi3.5` | phi3.5 | general chat, ~2.2GB RAM |
| `local-ollama-cpu-gemma3-4b` | gemma3:4b | general chat + vision, ~2.6GB RAM |
| `local-ollama-cpu-dolphin-phi` | dolphin-phi:latest | uncensored, ~1.6GB RAM |
| `local-ollama-cpu-nomic-embed` | nomic-embed-text | embeddings, 512 ctx, ~270MB RAM |
| `local-ollama-cpu-bge-m3` | bge-m3 | embeddings, multilingual, 8192 ctx, ~570MB RAM |
| `local-ollama-cpu-qwen3-embed-0.6b` | qwen3-embedding:0.6b | embeddings, ~500MB RAM |

## Ollama CUDA (local NVIDIA — `CUDA=1`)

Requires `nvidia-container-toolkit`. Flash attention + quantized KV cache enabled. Resource manager unloads the CUDA LLM before any CUDA TTS/STT request.

| Alias | Model | Notes |
| ----- | ----- | ----- |
| `local-ollama-cuda-qwen3-8b` | qwen3:8b | general chat, thinking mode, ~5GB VRAM |
| `local-ollama-cuda-llama3.1-8b` | llama3.1:8b | general chat, ~5GB VRAM |
| `local-ollama-cuda-gemma3-4b` | gemma3:4b | general chat + vision, ~3GB VRAM |
| `local-ollama-cuda-gemma3-12b` | gemma3:12b | general chat + vision, ~8GB VRAM |
| `local-ollama-cuda-qwen2.5-coder-7b` | qwen2.5-coder:7b | code, ~5GB VRAM |
| `local-ollama-cuda-dolphin-mistral-7b` | dolphin-mistral:7b | uncensored, ~5GB VRAM |
| `local-ollama-cuda-dolphin3` | dolphin3:latest | uncensored (latest Dolphin), ~5GB VRAM |
| `local-ollama-cuda-dolphin-phi` | dolphin-phi:latest | uncensored, tiny, ~1.6GB VRAM |

## Speaches CPU (local — `SPEACHES=1`)

Transcription and TTS on CPU. Models auto-downloaded and cached in `.data/speaches/`.

| Alias | Model | Mode |
| ----- | ----- | ---- |
| `local-speaches-whisper-distil-large-v3` | Systran/faster-distil-whisper-large-v3 | transcription (multilingual) |
| `local-speaches-parakeet-tdt-0.6b` | istupakov/parakeet-tdt-0.6b-v2-onnx | transcription (English, ~3400× real-time) |
| `local-speaches-kokoro-tts` | speaches-ai/Kokoro-82M-v1.0-ONNX-int8 | TTS — voices: af_heart, af_alloy, am_echo, bm_fable, and many more |

## Speaches CUDA (local NVIDIA — `CUDA=1`)

CUDA-accelerated STT. Shares model cache with CPU speaches (`.data/speaches/`) — no extra download.

| Alias | Model | Mode |
| ----- | ----- | ---- |
| `local-speaches-cuda-whisper-distil-large-v3` | Systran/faster-distil-whisper-large-v3 | transcription (CUDA, float16) |
| `local-speaches-cuda-parakeet-tdt-0.6b` | istupakov/parakeet-tdt-0.6b-v2-onnx | transcription (CUDA) |

## Qwen3 CUDA TTS (local NVIDIA — `CUDA=1`)

CUDA-accelerated TTS with voice cloning via [faster-qwen3-tts](https://github.com/andimarafioti/faster-qwen3-tts). Model cached in `.data/qwen3-tts/`.

| Alias | Model | Mode |
| ----- | ----- | ---- |
| `local-qwen3-cuda-tts` | Qwen/Qwen3-TTS-12Hz-0.6B-Base | TTS — voices: alloy, echo, fable |

## sd.cpp CPU (local — `SDCPP=1`)

Local CPU image generation via [stable-diffusion.cpp](https://github.com/leejet/stable-diffusion.cpp). Go wrapper with model hot-swap, idle auto-unload, OpenAI-compatible `/v1/images/generations`. Models cached in `.data/sdcpp/models/`.

| Alias | Model | Notes |
| ----- | ----- | ----- |
| `local-sdcpp-cpu-sd-turbo` | stabilityai/sd-turbo | fastest, smallest (~1.7GB) |
| `local-sdcpp-cpu-sdxl-turbo` | stabilityai/sdxl-turbo | better quality (~2.5GB) |

## sd.cpp CUDA (local NVIDIA — `SDCPP=1` + `CUDA=1`)

CUDA-accelerated image generation. Same Go wrapper with CUDA backend. Non-blocking — rejects concurrent requests with 503 (resource manager handles scheduling via semaphore).

| Alias | Model | Notes |
| ----- | ----- | ----- |
| `local-sdcpp-cuda-sd-turbo` | stabilityai/sd-turbo | fastest on GPU (~1.7GB VRAM) |
| `local-sdcpp-cuda-sdxl-turbo` | stabilityai/sdxl-turbo | fast, good quality (~2.5GB VRAM) |
| `local-sdcpp-cuda-sdxl-lightning` | ByteDance/SDXL-Lightning | fast, high quality (~2.5GB VRAM) |
| `local-sdcpp-cuda-flux-schnell` | black-forest-labs/FLUX.1-schnell | best quality, largest (~7GB VRAM) |
| `local-sdcpp-cuda-juggernaut-xi` | RunDiffusion/Juggernaut-XI-v11 | photorealistic SDXL fine-tune (~2.5GB VRAM) |

---

## Fallbacks

Every model has its own fallback chain. When a provider fails, is rate-limited, or returns an error, LiteLLM automatically tries the next model in the chain. Free providers are always tried first.

For example, `groq-llama-3.3-70b` falls back through `cerebras-qwen3-235b` → `mistral-small` → `cohere-command-r` → `or-llama-3.3-70b` → `hf-llama-3.3-70b` → `claudebox-sonnet` → `claudebox-glm-4.7` → `openai-gpt-4o`. See `litellm/config/fallbacks.json` for all chains.
