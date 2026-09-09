# Providers and Models

Providers are configured via YAML fragments in `litellm/config/providers/`. `make run` assembles them into `litellm/config.yaml` (auto-generated, gitignored). Free-tier providers are tried first in fallback chains. Each provider is opt-in: set its flag to `1` in `.env` (e.g. `GROQ=1`) and fill in the API key. The flag activates the provider — the key alone does nothing.

## Free-tier reality check

"Free" never means unlimited. Every cloud provider on this gateway has a hard cap somewhere — RPM, RPD, TPM, TPD, monthly tokens, monthly request count, or a tiny dollar-denominated credit. Cross the cap and you get 429s, blocked accounts, or pay-as-you-go billing. The fallback chains in `litellm/config/fallbacks.json` hop to the next provider on 429, but if you've exhausted all of them you're either falling all the way to local models or getting an error.

Numbers below were correct at last check (provider docs change — click through for current values before relying on a tier).

| Provider     | CC required? | Per-minute            | Per-day                              | Monthly cap                          | Notes                                                                                | Official limits page                                                                                                  |
| ------------ | ------------ | --------------------- | ------------------------------------ | ------------------------------------ | ------------------------------------------------------------------------------------ | --------------------------------------------------------------------------------------------------------------------- |
| Groq         | No           | 30 RPM, 6–12K TPM     | 1K–14.4K RPD, 100K–500K TPD          | —                                    | Per-model. `llama-3.3-70b`: 1K RPD / 100K TPD. `llama-3.1-8b`: 14.4K RPD / 500K TPD. | [console.groq.com/docs/rate-limits](https://console.groq.com/docs/rate-limits)                                        |
| Cerebras     | Yes          | n/a                   | n/a                                  | n/a                                  | No free tier at the last audit: every model returns `Payment required`. | [inference-docs.cerebras.ai/support/rate-limits](https://inference-docs.cerebras.ai/support/rate-limits)                |
| OpenRouter   | No (for $0)  | 20 RPM on `:free`     | 50 RPD with $0 / 1000 RPD with $10+  | —                                    | Daily cap is per-account, not per-model.                                             | [openrouter.ai/docs/api-reference/limits](https://openrouter.ai/docs/api-reference/limits)                            |
| HuggingFace  | No           | varies per provider   | varies per provider                  | **$0.10 credits/mo** (PRO: $2/mo)    | Once credits run out you must purchase more — there is no "stays free forever" tier. | [huggingface.co/docs/inference-providers/pricing](https://huggingface.co/docs/inference-providers/pricing)            |
| Mistral      | No           | not published         | not published                        | not published                        | "Experiment" plan exists but Mistral doesn't publish numeric limits — see Admin → Limits in console after sign-up. Only `mistral-large`, `mistral-small`, `ministral-8b`, `mistral-embed` are free-tier. | [docs.mistral.ai/admin/user-management-finops/tier](https://docs.mistral.ai/admin/user-management-finops/tier)         |
| Cohere       | No           | 20 RPM chat, 10 RPM rerank, 2K inputs/min embed | —                          | **1,000 API calls/month** (chat)     | Hard monthly request cap is very low — runs out fast on any real workload.            | [docs.cohere.com/v2/docs/rate-limits](https://docs.cohere.com/v2/docs/rate-limits)                                     |
| Claudebox    | Subscription | depends on plan       | depends on plan                      | —                                    | Uses your Claude Pro/Max OAuth — no extra cost beyond the sub.                       | [anthropic.com/pricing](https://www.anthropic.com/pricing)                                                            |
| Pibox-zai    | Subscription | depends on plan       | depends on plan                      | —                                    | pi-coding-agent on a [GLM Coding Plan](https://z.ai/subscribe). Metered allowance, not unlimited. | [z.ai](https://z.ai)                                                                                                  |
| Anthropic    | **Yes**      | tiered                | tiered                               | pay-per-token, no free tier          | Not free. Standard API.                                                              | [docs.anthropic.com/en/api/rate-limits](https://docs.anthropic.com/en/api/rate-limits)                                |
| OpenAI       | **Yes**      | tiered                | tiered                               | pay-per-token, no free tier          | Not free. Standard API.                                                              | [platform.openai.com/docs/guides/rate-limits](https://platform.openai.com/docs/guides/rate-limits)                    |
| Local (CPU / CUDA) | N/A    | unlimited             | unlimited                            | unlimited                            | Only constrained by your hardware. Last-resort fallback when all cloud tiers fail.   | —                                                                                                                     |

What this means for the gateway:

- **Hammer Groq → 429 → fallback** chain hops. A single requesting client doing >30 chat completions/minute is hitting Groq's RPM ceiling, not yours.
- **Cohere is a footgun**: 1,000 calls/month at trial is enough for testing, not enough for any real workload. Don't put Cohere first in a custom fallback chain unless you've enabled production billing.
- **HuggingFace free is ~$0.10/month** — designed for evaluation, not production. Use a custom provider key (your own HF Pro / direct Together / Fireworks / etc.) for sustained use.
- **OpenRouter $0 → 50 req/day total** across all `:free` models. Bumping to $10 loaded raises it to 1000 RPD.
- **Cerebras has no free tier at the last audit**: every model, including the ones previously free-trial eligible, returns `Payment required to access this resource`. Enabling `CEREBRAS=1` without a billing plan adds models that fail at request time and fall through to the next entry in their chain.
- **Mistral doesn't publish free-tier numbers anywhere** — the "Experiment" plan exists but exact RPS/TPM/TPMonth values live only in your account's Admin → Limits page. Plan accordingly, treat it as low-volume eval-only until you've seen your numbers.
- **Local models** are the only true "no limit" — at the cost of your own VRAM / CPU / latency.

## Groq (free tier — 30 RPM, 1K–14.4K RPD per model, no CC)

Sign up: [console.groq.com](https://console.groq.com) — no credit card required. Per-model limits at [console.groq.com/docs/rate-limits](https://console.groq.com/docs/rate-limits).

| Model                          | Alias                               | Notes           |
| ------------------------------ | ----------------------------------- | --------------- |
| openai/gpt-oss-20b             | `groq-gpt-oss-20b`                  | small, fast     |
| openai/gpt-oss-120b            | `groq-gpt-oss-120b`                 | flagship        |
| openai/gpt-oss-safeguard-20b   | `groq-gpt-oss-safeguard-20b`        | safety filter   |
| qwen/qwen3.8-27b               | `groq-qwen3.8-27b`                  | mid-size, newest |
| qwen/qwen3.6-27b               | `groq-qwen3.6-27b`                  | mid-size        |
| groq/compound                  | `groq-compound`                     | tool use        |
| groq/compound-mini             | `groq-compound-mini`                | tool use, fast  |
| allam-2-7b                     | `groq-allam-2-7b`                   | Arabic          |
| meta-llama/llama-prompt-guard-2-22m | `groq-prompt-guard-22m`        | prompt-injection score, not chat |
| meta-llama/llama-prompt-guard-2-86m | `groq-prompt-guard-86m`        | prompt-injection score, not chat |
| whisper-large-v3               | `groq-whisper-large-v3`             | transcription   |
| whisper-large-v3-turbo         | `groq-whisper-large-v3-turbo`       | transcription, fast |

The two compound models are namespaced `groq/` upstream. Groq also serves the Orpheus TTS voices, left out here because they need a one-time terms acceptance in the Groq console before the API will serve them.

## Cerebras (paid only as of the last audit)

Sign up: [cloud.cerebras.ai](https://cloud.cerebras.ai). At the last provider audit every model returned `Payment required to access this resource`, including the ones previously listed as free-trial eligible, so `CEREBRAS=1` buys nothing without a billing plan. Separately, `zai-glm-4.7` is archived and returns `Model zai-glm-4.7 is archived and unavailable for the organization`. Cerebras now serves `gpt-oss-120b`, `qwen-3.8-27b`, and `gemma-4-31b`. Limits page: [inference-docs.cerebras.ai/support/rate-limits](https://inference-docs.cerebras.ai/support/rate-limits). Among the fastest inference available if you are paying.

| Model                          | Alias                     | Notes             |
| ------------------------------ | ------------------------- | ----------------- |
| gpt-oss-120b                   | `cerebras-gpt-oss-120b`   | needs a paid plan |
| qwen-3.8-27b                   | `cerebras-qwen3.8-27b`    | needs a paid plan |
| gemma-4-31b                    | `cerebras-gemma-4-31b`    | needs a paid plan |

The previously listed `zai-glm-4.7` is archived upstream and was removed.

## OpenRouter (free tier — 50 RPD at $0, 1000 RPD at $10+)

Sign up: [openrouter.ai](https://openrouter.ai) — 50 req/day free across all `:free` models with $0 loaded; 1000 req/day once you've loaded ≥$10 in credits (lifetime, not monthly). Limits page: [openrouter.ai/docs/api-reference/limits](https://openrouter.ai/docs/api-reference/limits).

The `:free` roster rotates. OpenRouter withdraws a model's free variant without removing the paid one, so a pin that worked last month stops resolving while the model itself still exists. Every alias below returned a completion when the list was last audited. Re-check with `bash tests/test_litellm.sh`.

| Model                                         | Alias                        | Context | Notes                                    |
| --------------------------------------------- | ---------------------------- | ------- | ---------------------------------------- |
| nvidia/nemotron-3.5-lightning                 | `or-nemotron-lightning`      | 1M      | largest context here                     |
| nvidia/nemotron-3-super-120b-a12b             | `or-nemotron-120b`           | 262k    |                                          |
| dots-studio/dots-3-note-preview               | `or-dots-3-note`             | 512k    | text + image                             |
| nvidia/nemotron-3-nano-omni-30b-a3b-reasoning | `or-nemotron-omni-30b`       | 256k    | text/image/audio/video, reasoning        |
| cohere/north-mini-code                        | `or-north-mini-code`         | 256k    | code                                     |
| liquid/lfm-2.5-2.6b                           | `or-lfm-2.5-2.6b`            | 65k     | small and fast                           |
| inclusionai/ling-3.0-flash-sante              | `or-ling-3-sante`            | 262k    | health-domain tuned                      |
| inclusionai/ling-3.0-flash-fin                | `or-ling-3-fin`              | 262k    | finance-domain tuned                     |
| nvidia/nemotron-3.5-content-safety            | `or-nemotron-content-safety` | 128k    | safety classifier, not general chat      |

The last three answer by name but stay out of the general fallback chains, where a domain-tuned model or a classifier would answer off-target.

## HuggingFace Inference Providers ($0.10/mo free credits — not really "free")

Sign up: [huggingface.co](https://huggingface.co/settings/tokens). Free users get **$0.10 in credits per month** (PRO: $2/mo, Team/Enterprise: $2/seat/mo). Past that you're pay-as-you-go at the provider's rate — HF doesn't mark up. Treat this as a "try before you buy" tier, not sustained free inference. Pricing: [huggingface.co/docs/inference-providers/pricing](https://huggingface.co/docs/inference-providers/pricing).

| Model                                        | Alias                  | Notes          |
| -------------------------------------------- | ---------------------- | -------------- |
| meta-llama/Llama-3.1-8B-Instruct             | `hf-llama-3.1-8b`      |                |
| meta-llama/Llama-3.3-70B-Instruct            | `hf-llama-3.3-70b`     |                |
| meta-llama/Llama-4-Scout-17B-16E-Instruct    | `hf-llama-4-scout`     | multimodal     |
| Qwen/Qwen3-8B                                | `hf-qwen3-8b`          |                |
| Qwen/Qwen3-32B                               | `hf-qwen3-32b`         | reasoning      |
| Qwen/Qwen3-235B-A22B                         | `hf-qwen3-235b`        | largest here   |
| deepseek-ai/DeepSeek-R1                      | `hf-deepseek-r1`       | reasoning      |
| Qwen/Qwen2.5-VL-72B-Instruct                 | `hf-qwen-vl-72b`       | multimodal     |
| google/gemma-3-12b-it                        | `hf-gemma-3-12b`       | multimodal     |
| google/gemma-3-27b-it                        | `hf-gemma-3-27b`       | multimodal     |
| black-forest-labs/FLUX.1-schnell             | `hf-flux-schnell`      | image gen, fast |

## Mistral AI (free "Experiment" tier — exact limits not published, no CC)

Sign up: [console.mistral.ai](https://console.mistral.ai) — no credit card required to start. Mistral has a free **"Experiment" plan** ("intended for evaluation and prototyping only") and a paid **"Scale" plan** (pay-as-you-go, auto-promoted Tier 1 → Tier 4 by cumulative billing). The free plan covers `mistral-large`, `mistral-small`, `ministral-8b`, and `mistral-embed`. Anything else (magistral, devstral, codestral, voxtral) requires Scale plan.

**Mistral does not publish numeric free-tier RPS/TPM/TPMonth values anywhere on their public docs site.** The official tier page ([docs.mistral.ai/admin/user-management-finops/tier](https://docs.mistral.ai/admin/user-management-finops/tier)) explicitly directs you to "Admin → Limits" inside your own console to see exact numbers. Treat the free tier as low-volume eval until you've signed in and checked yours.

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

## Cohere (trial — 20 RPM chat, **1K calls/month total cap**, no CC)

Sign up: [dashboard.cohere.com](https://dashboard.cohere.com) — no credit card required. Trial key gives access to all models, but **the monthly chat cap is only 1,000 API calls** — runs out fast on any real workload. Rerank: 10 RPM. Embed: 2,000 inputs/min (text) or 5 inputs/min (images). Limits page: [docs.cohere.com/v2/docs/rate-limits](https://docs.cohere.com/v2/docs/rate-limits). For production, switch to a production key (500 RPM chat, contact sales).

| Model                  | Alias                   | Notes                        |
| ---------------------- | ----------------------- | ---------------------------- |
| command-a-plus-05-2026    | `cohere-command-a-plus`      | newest flagship              |
| command-a-03-2025         | `cohere-command-a`           | flagship, 256K ctx, tool use |
| command-a-reasoning-08-2025 | `cohere-command-a-reasoning` | reasoning                  |
| command-a-vision-07-2025  | `cohere-command-a-vision`    | multimodal                   |
| command-a-translate-08-2025 | `cohere-command-a-translate` | translation                |
| north-mini-code-1-0       | `cohere-north-mini-code`     | code                         |
| command-r-plus-08-2024    | `cohere-command-r-plus`      | strong, 128K ctx             |
| command-r-08-2024         | `cohere-command-r`           | balanced                     |
| command-r7b-12-2024       | `cohere-command-r7b`         | fast, small                  |
| command-r7b-arabic-02-2025 | `cohere-command-r7b-arabic` | Arabic                       |
| c4ai-aya-expanse-32b      | `cohere-aya-32b`             | multilingual (23 languages)  |
| c4ai-aya-vision-32b       | `cohere-aya-vision-32b`      | multilingual multimodal      |
| tiny-aya-global           | `cohere-tiny-aya-global`     | small multilingual           |
| tiny-aya-earth            | `cohere-tiny-aya-earth`      | small multilingual           |
| tiny-aya-fire             | `cohere-tiny-aya-fire`       | small multilingual           |
| tiny-aya-water            | `cohere-tiny-aya-water`      | small multilingual           |
| embed-v4.0                | `cohere-embed`               | embeddings                   |
| rerank-v3.5               | `cohere-rerank`              | reranking                    |

## Claudebox (requires Claude subscription or API key)

Full Claude Code CLI in API mode — not a standard LLM API. Each request runs Claude Code's full agentic loop with tool use, file I/O, shell access, and web browsing. Authentication: either an OAuth token from a Claude Pro/Max/Team subscription, or an Anthropic API key (pay-per-use).

Set up with `claude setup-token` or generate at [console.anthropic.com](https://console.anthropic.com/settings/keys).

| Alias              | Underlying model      | Best for                                        |
| ------------------ | --------------------- | ----------------------------------------------- |
| `claudebox-haiku`  | Claude Haiku 4.5      | Quick tasks, high-volume, minimal token use      |
| `claudebox-sonnet` | Claude Sonnet 4.6     | Daily coding, balanced speed/intelligence        |
| `claudebox-opus`   | Claude Opus 4.6       | Complex reasoning, architecture, hard debugging  |

## Pibox-zai, pi-coding-agent on a GLM Coding Plan (subscription)

Buy the [GLM Coding Plan](https://z.ai/subscribe), not pay-as-you-go API credits. The plan is the supported path here: a flat monthly fee that buys a credit allowance, rather than per-token billing. The allowance is metered, so it is not unlimited use. Routed through [pibox](https://github.com/psyb0t/docker-pibox) — [pi-coding-agent](https://github.com/earendil-works/pi-mono) wrapped in an API server, pointed at z.ai's Anthropic-compatible endpoint. Same agentic capabilities (shell, files, tools, MCP) as claudebox. Why pibox over a second claudebox: pi speaks the Anthropic wire protocol natively, no Claude Code license/OAuth ceremony, and pibox adds a `/files/*` CRUD API plus optional Telegram + cron modes for free. The `-zai` suffix names the upstream — future `PIBOX_*` flags can run pi against OpenAI, OpenRouter, etc.

The plan serves two models:

| Alias                     | Underlying model | Notes                                   |
| ------------------------- | ---------------- | --------------------------------------- |
| `pibox-zai-glm-5.3`       | GLM-5.3          | Flagship. Reserve for hard tasks.       |
| `pibox-zai-glm-5.3-flash` | GLM-5.3-Flash    | Default. 1M context, native multimodal. |

Retired ids still resolve, because z.ai routes them on their end: `glm-5.2` and `glm-5.1` serve **GLM-5.3**, and `glm-4.7` serves **GLM-5.3-Flash**. Only the two live ids are exposed as aliases here, so the alias you call always names the model that actually runs.

Override the exposed list with `PIBOX_ZAI_AVAILABLE_MODELS=glm-5.3,glm-5.3-flash` and the default with `PIBOX_ZAI_DEFAULT_MODEL=glm-5.3-flash` in `.env`. Both are already the compose defaults; set the override only to subset.

**How the allowance is spent.** The plan meters credits, not requests, against both a 5-hour and a weekly limit. z.ai converts tokens to credits per model:

```
credits = (input_tokens × in + cached_input_tokens × cached + output_tokens × out) / 10,000
```

| Model         | in  | cached | out |
| ------------- | --- | ------ | --- |
| GLM-5.3       | 6.9 | 1.7    | 24  |
| GLM-5.3-Flash | 2.3 | 0.56   | 8   |

Read these as conversion rates, not as multipliers against some 1x baseline. Comparing them to the older peak/off-peak scheme, which scaled a prompt quota rather than tokens, does not give a like-for-like answer. What they do show is the gap between the two current models: Flash costs exactly a third of GLM-5.3 on both input and output, which is why it is the default for routine, batch, and catalog work. Output dominates either way, at roughly 3.5x the input rate, so a chatty run costs far more than a long prompt with a short answer.

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
| `openai-whisper`               | whisper-1              | transcription  |
| `openai-gpt-4o-transcribe`     | gpt-4o-transcribe      | transcription, lower WER than whisper, streaming |
| `openai-gpt-4o-mini-transcribe`| gpt-4o-mini-transcribe | transcription, cheaper variant of the gpt-4o transcriber |
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
| `local-ollama-cpu-phi4-mini` | phi4-mini | general chat, 128K ctx, ~2.5GB RAM |
| `local-ollama-cpu-gemma4-e2b` | gemma4:e2b | general chat + vision (Gemma 4), ~7.2GB RAM |
| `local-ollama-cpu-gemma3-4b` | gemma3:4b | general chat + vision — lightweight, ~2.6GB RAM |
| `local-ollama-cpu-dolphin-phi` | dolphin-phi:latest | uncensored, ~1.6GB RAM |
| `local-ollama-cpu-nuextract-v1.5` | nuextract | structured extraction — unstructured text → JSON, ~2.3GB RAM |
| `local-ollama-cpu-bge-m3` | bge-m3 | embeddings, multilingual, 8192 ctx, ~570MB RAM |
| `local-ollama-cpu-qwen3-embed-0.6b` | qwen3-embedding:0.6b | embeddings, ~500MB RAM |

## Ollama CUDA (local NVIDIA — `OLLAMA_CUDA=1`)

Requires `nvidia-container-toolkit`. Flash attention + quantized KV cache enabled. Resource manager unloads the CUDA LLM before any CUDA TTS/STT request.

| Alias | Model | Notes |
| ----- | ----- | ----- |
| `local-ollama-cuda-qwen3-8b` | qwen3:8b | general chat, thinking mode, ~5GB VRAM |
| `local-ollama-cuda-llama3.1-8b` | llama3.1:8b | general chat, ~5GB VRAM |
| `local-ollama-cuda-gemma4-e2b` | gemma4:e2b | general chat + vision, ~7.2GB VRAM |
| `local-ollama-cuda-gemma4-e4b` | gemma4:e4b | general chat + vision, ~9.6GB VRAM |
| `local-ollama-cuda-qwen2.5-coder-7b` | qwen2.5-coder:7b | code, ~5GB VRAM |
| `local-ollama-cuda-deepseek-coder-v2-16b` | deepseek-coder-v2:16b | code, MoE 2.4B active, 160K ctx, ~8.9GB VRAM |
| `local-ollama-cuda-deepseek-r1-8b` | deepseek-r1:8b | reasoning, thinking mode, ~5.2GB VRAM |
| `local-ollama-cuda-qwen3-abliterated-16b` | huihui_ai/qwen3-abliterated:16b | uncensored, ~9.8GB VRAM |
| `local-ollama-cuda-gemma4-abliterated-e4b` | huihui_ai/gemma-4-abliterated:e4b | uncensored + vision, ~9.6GB VRAM |
| `local-ollama-cuda-dolphin-phi` | dolphin-phi:latest | uncensored, tiny, ~1.6GB VRAM |
| `local-ollama-cuda-llama3.2-3b` | llama3.2:3b | general chat, ~2.0GB VRAM |
| `local-ollama-cuda-qwen3-4b` | qwen3:4b | general chat, thinking mode, ~2.6GB VRAM |
| `local-ollama-cuda-smollm2-1.7b` | smollm2:1.7b | tiny general chat, ~1.0GB VRAM |
| `local-ollama-cuda-qwen2.5-coder-1.5b` | qwen2.5-coder:1.5b | code completion, tiny, ~1.0GB VRAM |
| `local-ollama-cuda-qwen2.5-coder-3b` | qwen2.5-coder:3b | code completion, small, ~2.0GB VRAM |
| `local-ollama-cuda-phi4-mini` | phi4-mini | general chat + reasoning, ~2.5GB VRAM |
| `local-ollama-cuda-gemma3-4b` | gemma3:4b | general chat + vision, lightweight, ~2.6GB VRAM |
| `local-ollama-cuda-nuextract-v1.5` | iodose/nuextract-v1.5 | structured extraction — unstructured text → JSON, ~2.3GB VRAM |
| `local-ollama-cuda-bge-m3` | bge-m3 | embeddings, multilingual, 8192 ctx, ~570MB VRAM |
| `local-ollama-cuda-qwen3-embed-0.6b` | qwen3-embedding:0.6b | embeddings, ~500MB VRAM |

## talkies CPU (local — `TALKIES=1`)

Unified OpenAI-compatible speech service via [`psyb0t/talkies:v0.17.0`](https://github.com/psyb0t/docker-talkies). One container exposes both `/v1/audio/transcriptions` (whisper + canary-180m + nemotron-3.5-asr + Sherpa-ONNX Zipformer + Vosk + phoneme ASR) and `/v1/audio/speech` (Kokoro-82M PyTorch + Kokoro-82M ONNXRuntime). Stereo channel-split diarization (`diarization=true` → segments tagged with `"channel": "L"/"R"`), VAD-chunked long audio, idle-unload TTL. Weights auto-downloaded into `.data/talkies/` on first request. Loaded models auto-unload after `TALKIES_MODEL_TTL` (default `10m`). Its native API, including live-ASR WebSockets, is also available at `/talkies/`; see [the Talkies service guide](services/talkies.md#direct-api-routes).

| Alias | Model | Mode |
| ----- | ----- | ---- |
| `local-talkies-whisper-large-v3` | Systran/faster-whisper-large-v3 | transcription (multilingual, highest accuracy) |
| `local-talkies-whisper-large-v3-turbo` | deepdml/faster-whisper-large-v3-turbo-ct2 | transcription (multilingual, ~8x faster than large-v3) |
| `local-talkies-canary-180m-flash` | nvidia/canary-180m-flash | transcription (English, FastConformer encoder) |
| `local-talkies-nemotron-3.5-asr-0.6b` | nvidia/Nemotron-3.5-ASR-Streaming-0.6B (via parakeet.cpp / mudler/parakeet-cpp-gguf) | transcription (40+ locales, per-word timestamps, OpenMDW-1.1) |
| `local-talkies-sherpa-zipformer-en-left-64` | k2-fsa/sherpa-onnx Zipformer (English) | transcription (English, streaming; 64-frame attention left context) |
| `local-talkies-sherpa-zipformer-en-left-128` | k2-fsa/sherpa-onnx Zipformer (English) | transcription (English, streaming; 128-frame left context — more context, slightly slower) |
| `local-talkies-sherpa-zipformer-en-int8-left-64` | k2-fsa/sherpa-onnx Zipformer int8 (English) | transcription (English, streaming; int8-quantized, smaller/faster) |
| `local-talkies-sherpa-zipformer-en-int8-left-128` | k2-fsa/sherpa-onnx Zipformer int8 (English) | transcription (English, streaming; int8-quantized, 128-frame left context) |
| `local-talkies-vosk-small-en-us-0.15` | alphacep/vosk-model-small-en-us-0.15 | transcription (English, streaming; smallest footprint) |
| `local-talkies-wav2vec2-xlsr-53-espeak` | facebook/wav2vec2-xlsr-53-espeak-cv-ft | transcription (phoneme ASR, eSpeak IPA, no lexicon; v0.17.0) |
| `local-talkies-zipa-ipa` | anyspeech/zipa-small-crctc-500k | transcription (phoneme ASR, IPA via sherpa-onnx offline CTC; v0.17.0) |
| `local-talkies-kokoro-tts` | hexgrad/Kokoro-82M | TTS — ~41 voices across en/es/fr/hi/it/pt (`af_heart`, `bm_george`, `ef_dora`, …; discover via `GET /v1/audio/voices`) |
| `local-talkies-kokoro-82m-nvidia` | nvidia/kokoro-82M-onnx-opt | TTS — same Kokoro-82M weights via ONNXRuntime + espeak-ng G2P (no PyTorch on the inference hot path) |

## talkies CUDA (local NVIDIA — `TALKIES_CUDA=1`)

CUDA-accelerated talkies (`psyb0t/talkies:v0.17.0-cuda`). Adds Parakeet TDT, Canary-1B-Flash, Canary-Qwen-2.5B SALM, and the full Qwen3-TTS line (Base / CustomVoice / VoiceDesign across 0.6B + 1.7B) on top of the CPU set. The Sherpa-ONNX variants run on the GPU here — the CUDA image installs a hash-verified upstream Sherpa CUDA wheel so they use its CUDA execution provider instead of a CPU fallback. Kokoro TTS still runs on CPU inside the CUDA image (fast enough that it doesn't need a GPU). Shares `.data/talkies/` with the CPU variant. The LiteLLM resource manager evicts these from VRAM whenever a competing CUDA job (LLM / image / TTS / other STT) arrives. Its raw API and PCM streaming are available at `/talkies-cuda/` only when `TALKIES_CUDA=1`; otherwise the route returns `404`.

| Alias | Model | Mode |
| ----- | ----- | ---- |
| `local-talkies-cuda-whisper-large-v3` | Systran/faster-whisper-large-v3 | transcription (CUDA, multilingual) |
| `local-talkies-cuda-whisper-large-v3-turbo` | deepdml/faster-whisper-large-v3-turbo-ct2 | transcription (CUDA, fastest Whisper at near-large WER) |
| `local-talkies-cuda-parakeet-tdt-0.6b-v3` | nvidia/parakeet-tdt-0.6b-v3 | transcription (CUDA, 25 European languages) |
| `local-talkies-cuda-canary-180m-flash` | nvidia/canary-180m-flash | transcription (CUDA, English) |
| `local-talkies-cuda-canary-1b-flash` | nvidia/canary-1b-flash | transcription (CUDA, EN/DE/FR/ES + EN↔X translation) |
| `local-talkies-cuda-canary-qwen-2.5b` | nvidia/canary-qwen-2.5b | transcription (CUDA, English, NeMo SALM hybrid ASR+LLM) |
| `local-talkies-cuda-nemotron-3.5-asr-0.6b` | nvidia/Nemotron-3.5-ASR-Streaming-0.6B (via parakeet.cpp) | transcription (40+ locales, per-word timestamps; GPU-accelerated as of talkies v0.14.0, which ships the upstream parakeet.cpp CUDA build instead of the CPU-only library it compiled before) |
| `local-talkies-cuda-sherpa-zipformer-en-left-64` | k2-fsa/sherpa-onnx Zipformer (English) | transcription (CUDA, English, streaming; 64-frame attention left context) |
| `local-talkies-cuda-sherpa-zipformer-en-left-128` | k2-fsa/sherpa-onnx Zipformer (English) | transcription (CUDA, English, streaming; 128-frame left context) |
| `local-talkies-cuda-sherpa-zipformer-en-int8-left-64` | k2-fsa/sherpa-onnx Zipformer int8 (English) | transcription (CUDA, English, streaming; int8-quantized) |
| `local-talkies-cuda-sherpa-zipformer-en-int8-left-128` | k2-fsa/sherpa-onnx Zipformer int8 (English) | transcription (CUDA, English, streaming; int8-quantized, 128-frame left context) |
| `local-talkies-cuda-vosk-small-en-us-0.15` | alphacep/vosk-model-small-en-us-0.15 | transcription (English, streaming; smallest footprint) |
| `local-talkies-cuda-wav2vec2-xlsr-53-espeak` | facebook/wav2vec2-xlsr-53-espeak-cv-ft | transcription (CUDA, phoneme ASR, eSpeak IPA, no lexicon; v0.17.0) |
| `local-talkies-cuda-zipa-ipa` | anyspeech/zipa-small-crctc-500k | transcription (CUDA, phoneme ASR, IPA via sherpa-onnx offline CTC; v0.17.0) |
| `local-talkies-cuda-kokoro-tts` | hexgrad/Kokoro-82M | TTS (runs on CPU inside the CUDA image) |
| `local-talkies-cuda-kokoro-82m-nvidia` | nvidia/kokoro-82M-onnx-opt | TTS — ONNXRuntime path, same voices as kokoro-82m |
| `local-talkies-cuda-qwen3-tts` | Qwen/Qwen3-TTS-12Hz-0.6B-Base | TTS — Base 0.6B voice cloning via reference `.wav` files in `${DATA_DIR_TALKIES}/custom-voices/`; samples `alloy`/`echo`/`fable` baked in; supports 17 languages (en, zh, ja, ko, fr, de, es, it, pt, ru, vi, th, id, ar, tr, pl, nl) |
| `local-talkies-cuda-qwen3-tts-1.7b` | Qwen/Qwen3-TTS-12Hz-1.7B-Base | TTS — Base 1.7B voice cloning (larger / higher quality than 0.6B) |
| `local-talkies-cuda-qwen3-tts-0.6b-custom` | Qwen/Qwen3-TTS-12Hz-0.6B-CustomVoice | TTS — CustomVoice mode, 9 preset speakers (`Vivian`, `Serena`, `Uncle_Fu`, `Dylan`, `Eric`, `Ryan`, `Aiden`, `Ono_Anna`, `Sohee`) — pass as `voice=<preset>` |
| `local-talkies-cuda-qwen3-tts-1.7b-custom` | Qwen/Qwen3-TTS-12Hz-1.7B-CustomVoice | TTS — same 9 preset speakers as the 0.6b-custom slug, plus `instructions=<emotion>` (`"happy"`, `"sad"`, …) |
| `local-talkies-cuda-qwen3-tts-1.7b-design` | Qwen/Qwen3-TTS-12Hz-1.7B-VoiceDesign | TTS — VoiceDesign mode. Pass `voice="design"` (sentinel) + `instructions=<natural-language description>` (e.g. `"a young energetic female voice"`); model synthesises a voice that matches the description |
| `local-talkies-cuda-chatterbox-turbo` | ResembleAI/chatterbox-turbo | TTS — expressive English only, 24 kHz mono, buffered (no PCM streaming). Emotion and non-verbal sounds go inline in `input` as bracketed tags; the tokenizer defines exactly 19, so anything else in brackets is spoken literally. `voice=builtin` or a reference `.wav` under `${DATA_DIR_TALKIES}/custom-voices/` — no transcript needed, but the clip must exceed 5 seconds. `speed` is ignored. Output carries a neural watermark by default; set `TALKIES_CHATTERBOX_WATERMARK=false` to disable it. See [the Talkies service guide](services/talkies.md#chatterbox-turbo-emotion-tags) for the tag list |

## sd.cpp CPU (local — `SDCPP=1`)

Local CPU image generation via [stable-diffusion.cpp](https://github.com/leejet/stable-diffusion.cpp). Go wrapper with model hot-swap, idle auto-unload, OpenAI-compatible `/v1/images/generations`. Models cached in `.data/sdcpp/models/`.

| Alias | Model | Notes |
| ----- | ----- | ----- |
| `local-sdcpp-cpu-sd-turbo` | stabilityai/sd-turbo | fastest, smallest (~1.7GB) |
| `local-sdcpp-cpu-sdxl-turbo` | stabilityai/sdxl-turbo | better quality (~2.5GB) |

## sd.cpp CUDA (local NVIDIA — `SDCPP_CUDA=1`)

CUDA-accelerated image generation. Same Go wrapper with CUDA backend. Non-blocking — rejects concurrent requests with 503 (resource manager handles scheduling via semaphore).

| Alias | Model | Notes |
| ----- | ----- | ----- |
| `local-sdcpp-cuda-sd-turbo` | stabilityai/sd-turbo | fastest on GPU (~1.7GB VRAM) |
| `local-sdcpp-cuda-sdxl-turbo` | stabilityai/sdxl-turbo | fast, good quality (~2.5GB VRAM) |
| `local-sdcpp-cuda-sdxl-lightning` | ByteDance/SDXL-Lightning | fast, high quality (~2.5GB VRAM) |
| `local-sdcpp-cuda-flux-schnell` | black-forest-labs/FLUX.1-schnell | best quality, largest (~7GB VRAM) |
| `local-sdcpp-cuda-juggernaut-xi` | RunDiffusion/Juggernaut-XI-v11 | photorealistic SDXL fine-tune (~5GB VRAM) |

## vLLM CPU (local — `VLLM=1`)

Supervised single-model wrapper around `vllm serve` on top of the `vllm/vllm-openai-cpu` base image. Same surface as the CUDA variant — only one model resident at a time, idle-unloads after `VLLM_MODEL_TTL` (default 10m). Edit `vllm/models.cpu.json` to add models.

| Alias | Model | Notes |
| ----- | ----- | ----- |
| `local-vllm-nomic-embed-v2` | nomic-ai/nomic-embed-text-v2-moe | embeddings, MoE 305M active, 8192 ctx |
| `local-vllm-qwen3-0.6b` | Qwen/Qwen3-0.6B | chat / completions, 8192 ctx |

## vLLM CUDA (local NVIDIA — `VLLM_CUDA=1`)

Supervised single-model wrapper around `vllm serve` for chat/completions/embeddings. Only one model resident in VRAM at a time — the wrapper restarts the subprocess when a different model is requested. Idle-unloads after `VLLM_CUDA_MODEL_TTL` (default 10m). The LiteLLM resource_manager evicts vllm-cuda whenever a competing CUDA job (ollama / sdcpp / talkies) arrives. Add or change models by editing `vllm/models.cuda.json`. Both CPU and CUDA variants share the same `${DATA_DIR_VLLM}/models/` weight store.

| Alias | Model | Notes |
| ----- | ----- | ----- |
| `local-vllm-cuda-nomic-embed-v2` | nomic-ai/nomic-embed-text-v2-moe | embeddings, MoE 305M active, 8192 ctx |
| `local-vllm-cuda-qwen3-0.6b` | Qwen/Qwen3-0.6B | chat / completions, 16384 ctx |

## llama.cpp CPU (local — `LLAMACPP=1`)

Supervised single-model wrapper around `llama-server` for GGUF chat / completions / embeddings, with native vision support via `mmproj`. Same lifecycle as vllm-wrap (`/api/ps`, `DELETE /api/ps/{model_id}`, idle TTL unload). The LiteLLM resource_manager evicts llamacpp whenever a competing CPU job (ollama / sdcpp-cpu / talkies-cpu / vllm-cpu) arrives. Add or change models by editing `llamacpp/models.cpu.json`. Wrapper rewrites `image_url.url: https://...` to `data:` URLs transparently so any OpenAI vision client works. **Server-side PDF input** + **auto `--ctx-size`** — see the Surya row below.

| Alias | Model | Notes |
| ----- | ----- | ----- |
| `local-llamacpp-surya-ocr-2` | datalab-to/surya-ocr-2-gguf | Vision VLM (~650M, Qwen3-VL-style hybrid Mamba+attention, **256K trained context**). One model, four trained-in prompt modes: **block OCR** (`OCR this block image to HTML.`), **full-page OCR** (`OCR this image to HTML. Each block is a div with data-label and data-bbox (x0 y0 x1 y1, normalized 0-1000).`), **layout detection** (`Output the layout of this image as JSON. Each entry is a dict with "label", "bbox", and "count" fields. Bbox is x0 y0 x1 y1, normalized 0-1000.`), **table recognition** (`Output the table rows then columns as JSON. Each entry is a dict with "label" ("Row" or "Col") and "bbox" (x0 y0 x1 y1, normalized 0-1000).`). Pass the prompts verbatim — they're training-time contracts. **PDF input is server-side** — drop a PDF in `image_url.url` (data URL or http URL) and the wrapper rasterizes per page, runs the per-page chat completion, stitches the responses by prompt mode. Per-request `dpi_rescale_to` knob (default 96 cap, `-1` for native, hard cap 600). `--ctx-size` is set to `auto` — the supervisor probes free RAM and picks the largest fitting ctx, capped at the model's 256K trained max. See [docs/services/llamacpp.md](services/llamacpp.md) for curl examples of each mode and the auto-ctx-size math. |

## llama.cpp CUDA (local NVIDIA — `LLAMACPP_CUDA=1`)

Same wrapper as the CPU variant but with `--n-gpu-layers 999` and the CUDA base image. Strongly preferred for vision-VLM work — Surya OCR 2 on a single A4 page at 96 DPI is ~seconds on CUDA vs minutes on CPU. Shares `${DATA_DIR_LLAMACPP}/models/` with the CPU variant — enabling both does not duplicate downloads. Participates in the LiteLLM resource_manager `cuda-llamacpp` group, so it evicts (and is evicted by) ollama-cuda / sdcpp-cuda / talkies-cuda / vllm-cuda under VRAM contention.

| Alias | Model | Notes |
| ----- | ----- | ----- |
| `local-llamacpp-cuda-surya-ocr-2` | datalab-to/surya-ocr-2-gguf | Same model + same 4 prompt modes + same server-side PDF handling + `dpi_rescale_to` knob + auto `--ctx-size` as the CPU slug — see the row above. The resolver picks the **full 262144 trained max** on any RTX-class GPU with ~3+ GB free for KV cache (verified live on the aigate stack). |

---

## Fallbacks

Every model has its own fallback chain. When a provider fails, is rate-limited, or returns an error, LiteLLM automatically tries the next model in the chain. Free providers are always tried first.

For example, `groq-gpt-oss-120b` falls back through `cerebras-gpt-oss-120b` → `mistral-large` → `or-nemotron-omni-30b` → `hf-llama-3.3-70b` → `openai-gpt-4o`. See `litellm/config/fallbacks.json` for all chains.
