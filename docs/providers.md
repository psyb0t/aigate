# Providers and Models

## Groq (free tier)

| Model                          | Alias                               |
| ------------------------------ | ----------------------------------- |
| llama-3.1-8b-instant           | `groq-llama-3.1-8b`                 |
| llama-3.3-70b-versatile        | `groq-llama-3.3-70b`                |
| llama-4-scout-17b-16e-instruct | `groq-llama-4-scout` _(multimodal)_ |
| moonshotai/kimi-k2-instruct    | `groq-kimi-k2`                      |
| openai/gpt-oss-20b             | `groq-gpt-oss-20b`                  |
| openai/gpt-oss-120b            | `groq-gpt-oss-120b`                 |
| qwen/qwen3-32b                 | `groq-qwen3-32b`                    |
| compound-beta                  | `groq-compound`                     |
| compound-beta-mini             | `groq-compound-mini`                |
| whisper-large-v3               | `groq-whisper-large-v3`             |
| whisper-large-v3-turbo         | `groq-whisper-large-v3-turbo`       |

## Cerebras (free tier)

1M tokens/day free, no credit card required. Among the fastest inference available (Llama 3.1 8B ~1,800 t/s, Qwen3 235B ~1,400 t/s).

| Model                          | Alias                                                 |
| ------------------------------ | ----------------------------------------------------- |
| qwen-3-235b-a22b-instruct-2507 | `cerebras-qwen3-235b`                                 |
| gpt-oss-120b                   | `cerebras-gpt-oss-120b` _(rate-limited on free tier)_ |
| zai-glm-4.7                    | `cerebras-glm-4.7` _(rate-limited on free tier)_      |
| llama3.1-8b                    | `cerebras-llama-3.1-8b`                               |

## OpenRouter (free tier)

50 req/day free (no credits), 1000 req/day with $10+ loaded.

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

| Model                                        | Alias                             |
| -------------------------------------------- | --------------------------------- |
| meta-llama/Llama-3.1-8B-Instruct             | `hf-llama-3.1-8b`                 |
| meta-llama/Llama-3.3-70B-Instruct            | `hf-llama-3.3-70b`                |
| meta-llama/Llama-4-Scout-17B-16E-Instruct    | `hf-llama-4-scout` _(multimodal)_ |
| Qwen/Qwen3-8B                                | `hf-qwen3-8b`                     |
| Qwen/QwQ-32B                                 | `hf-qwq-32b`                      |
| deepseek-ai/DeepSeek-R1                      | `hf-deepseek-r1`                  |
| Qwen/Qwen2.5-VL-72B-Instruct                 | `hf-qwen-vl-72b` _(multimodal)_   |
| Qwen/Qwen2.5-VL-7B-Instruct                  | `hf-qwen3-vl-8b` _(multimodal)_   |
| google/gemma-3-12b-it                        | `hf-gemma-3-12b` _(multimodal)_   |
| black-forest-labs/FLUX.1-schnell             | `hf-flux-schnell` _(image gen)_   |
| black-forest-labs/FLUX.1-dev                 | `hf-flux-dev` _(image gen)_       |
| stabilityai/stable-diffusion-3.5-large-turbo | `hf-sd-3.5-turbo` _(image gen)_   |

## Mistral AI (free tier: 1B tokens/month, 60 RPM)

Chat, code, reasoning, embedding, and audio models. The core chat models (Large, Small, Ministral 8B, Codestral) are on the free tier with no credit card required. Magistral (reasoning) and Devstral (coding agent) are paid.

| Model                 | Alias              | Notes                 |
| --------------------- | ------------------ | --------------------- |
| mistral-large-2512    | `mistral-large`    | free                  |
| mistral-small-2603    | `mistral-small`    | free, multimodal      |
| ministral-3-8b-2512   | `ministral-8b`     | free, fast            |
| magistral-medium-2509 | `magistral-medium` | paid, reasoning       |
| magistral-small-2509  | `magistral-small`  | paid, reasoning       |
| devstral-2512         | `devstral`         | paid, coding agent    |
| codestral-2508        | `codestral`        | paid, code completion |
| mistral-embed         | `mistral-embed`    | free, embeddings      |
| voxtral-small-25-07   | `voxtral-small`    | audio                 |

## Cohere (trial: 1K req/day, 20 RPM — all models included)

All chat models are accessible on the trial key with no credit card required. Command A is their flagship with 256K context and native tool use. Aya Expanse is their strongest multilingual model (23 languages).

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

Full Claude Code CLI in API mode. Authenticate with either an OAuth token (Claude Pro/Max/Team subscription) or an Anthropic API key (pay-per-use). These are not standard API calls — each request runs through Claude Code's full agentic loop with tool use, file I/O, shell access, and web browsing within a persistent workspace.

| Model  | Alias              |
| ------ | ------------------ |
| opus   | `claudebox-opus`   |
| sonnet | `claudebox-sonnet` |
| haiku  | `claudebox-haiku`  |

## Claudebox GLM — via z.ai (requires z.ai account)

[z.ai](https://z.ai) provides an Anthropic-compatible API backed by GLM models. Routed through a second claudebox instance pointed at z.ai — same agentic capabilities and workspace features as the OAuth instance above.

| Model       | Alias                   |
| ----------- | ----------------------- |
| glm-5.1     | `claudebox-glm-5.1`     |
| glm-4.7     | `claudebox-glm-4.7`     |
| glm-4.5-air | `claudebox-glm-4.5-air` |

## Anthropic (optional, API key required)

| Model             | Alias                                      |
| ----------------- | ------------------------------------------ |
| claude-opus-4-6   | `anthropic-claude-opus-4` _(multimodal)_   |
| claude-sonnet-4-6 | `anthropic-claude-sonnet-4` _(multimodal)_ |
| claude-haiku-4-5  | `anthropic-claude-haiku-4` _(multimodal)_  |

## OpenAI (optional, API key required)

| Model       | Alias                               |
| ----------- | ----------------------------------- |
| gpt-4o      | `openai-gpt-4o` _(multimodal)_      |
| gpt-4o-mini | `openai-gpt-4o-mini` _(multimodal)_ |
| o3          | `openai-o3`                         |
| o3-mini     | `openai-o3-mini`                    |
| dall-e-3    | `openai-dall-e-3` _(image gen)_     |
| gpt-image-1 | `openai-gpt-image-1` _(image gen)_  |
| whisper-1   | `openai-whisper`                    |
| tts-1       | `openai-tts-1`                      |
| tts-1-hd    | `openai-tts-1-hd`                   |

## Model Groups and Fallbacks

Model groups let you use a single alias and let the gateway figure out which provider to hit. LiteLLM tries each model in priority order and automatically falls back to the next one when a provider fails, is rate-limited, or returns an error. Free providers are always tried first.

| Group           | Fallback chain (priority order)                                                                                                                                                                                                                                                                                                       |
| --------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `fast`          | groq-llama-3.1-8b → cerebras-llama-3.1-8b → ministral-8b → cohere-command-r7b → claudebox-haiku → claudebox-glm-4.5-air → or-gpt-oss-20b → hf-llama-3.1-8b → openai-gpt-4o-mini                                                                                                                                                       |
| `smart`         | cerebras-qwen3-235b → claudebox-sonnet → mistral-large → mistral-small → cohere-command-a → or-hermes-3-405b → or-qwen3-80b → cerebras-gpt-oss-120b → or-nemotron-120b → or-minimax-m2.5 → claudebox-glm-4.7 → cerebras-glm-4.7 → openai-gpt-4o → anthropic-claude-sonnet-4 → claudebox-opus → claudebox-glm-5.1 → groq-llama-3.3-70b |
| `vision`        | openai-gpt-4o → anthropic-claude-sonnet-4 → claudebox-sonnet → claudebox-glm-4.7 → mistral-small → cohere-command-a → groq-llama-4-scout → hf-llama-4-scout → hf-qwen-vl-72b                                                                                                                                                          |
| `image-gen`     | openai-dall-e-3 → hf-flux-schnell → hf-flux-dev                                                                                                                                                                                                                                                                                       |
| `transcription` | groq-whisper-large-v3-turbo → groq-whisper-large-v3 → voxtral-small → openai-whisper                                                                                                                                                                                                                                                  |

Every individual model also has its own fallback chain configured. For example, if `groq-llama-3.3-70b` fails, it automatically tries `cerebras-qwen3-235b`, then `or-llama-3.3-70b`, then `hf-llama-3.3-70b`, then `claudebox-sonnet`, and so on. See `config.yaml` for the full fallback configuration.
