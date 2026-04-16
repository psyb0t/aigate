# Providers and Models

All providers are configured in `litellm/config.yaml`. Free-tier providers are tried first in fallback chains. Add API keys in `.env` to activate providers.

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
| black-forest-labs/FLUX.1-dev                 | `hf-flux-dev`          | image gen      |
| stabilityai/stable-diffusion-3.5-large-turbo | `hf-sd-3.5-turbo`      | image gen      |

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

## Fallbacks

Every model has its own fallback chain. When a provider fails, is rate-limited, or returns an error, LiteLLM automatically tries the next model in the chain. Free providers are always tried first.

For example, `groq-llama-3.3-70b` falls back to `cerebras-qwen3-235b` → `or-llama-3.3-70b` → `hf-llama-3.3-70b` → `claudebox-sonnet`. See `litellm/config.yaml` for the full configuration.
