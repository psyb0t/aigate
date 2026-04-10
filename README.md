# docker-litellm

A production-ready [LiteLLM](https://github.com/BerriAI/litellm) proxy stack with a ridiculous number of providers, all behind one OpenAI-compatible endpoint. Built on Docker Compose.

## What's in it

One `docker compose up` gives you:

- **LiteLLM proxy** on port 4000 — single OpenAI-compatible API for everything
- **PostgreSQL** — key management, budgets, usage tracking
- **Redis** — caching + rate limiting
- **[docker-claude-code](https://github.com/psyb0t/docker-claude-code)** (×2) — Claude Code running in API mode, one per provider

## Providers & Models

### Groq (free tier)

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

### HuggingFace Inference Providers (free tier)

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

### Anthropic (API key)

| Model             | Alias                                      |
| ----------------- | ------------------------------------------ |
| claude-opus-4-6   | `anthropic-claude-opus-4` _(multimodal)_   |
| claude-sonnet-4-6 | `anthropic-claude-sonnet-4` _(multimodal)_ |
| claude-haiku-4-5  | `anthropic-claude-haiku-4` _(multimodal)_  |

### Claude Code — via OAuth

Uses [docker-claude-code](https://github.com/psyb0t/docker-claude-code) in API mode with a Claude OAuth token. Claude Code runs the actual CLI under the hood so it's not just a chat API — it can use tools, read/write files in the workspace, run shell commands, etc.

| Model  | Alias                |
| ------ | -------------------- |
| opus   | `claude-code-opus`   |
| sonnet | `claude-code-sonnet` |
| haiku  | `claude-code-haiku`  |

**Workspace control** — pass `x-claude-workspace` in `extra_headers` to isolate sessions:

```json
{
  "model": "claude-code-haiku",
  "messages": [{ "role": "user", "content": "..." }],
  "extra_headers": { "x-claude-workspace": "myproject" }
}
```

Each workspace gets its own conversation history and file context. Different callers using different workspaces run fully concurrently.

### Claude Code GLM — via z.ai

[z.ai](https://z.ai) provides an Anthropic-compatible API that serves GLM models. This stack routes through a second docker-claude-code instance pointed at z.ai, so the same workspace/tool-use capabilities apply.

| Model       | Alias                     |
| ----------- | ------------------------- |
| glm-5.1     | `claude-code-glm-5.1`     |
| glm-4.7     | `claude-code-glm-4.7`     |
| glm-4.5-air | `claude-code-glm-4.5-air` |

### OpenRouter (free tier)

50 req/day free (no credits loaded), 1000 req/day with $10+. Only models that work with API key auth (some require ToS acceptance on the website first).

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

### Cerebras (free tier)

1M tokens/day free, no credit card required. Fastest inference available (~2,600 t/s).

| Model                          | Alias                                                 |
| ------------------------------ | ----------------------------------------------------- |
| qwen-3-235b-a22b-instruct-2507 | `cerebras-qwen3-235b`                                 |
| gpt-oss-120b                   | `cerebras-gpt-oss-120b` _(rate-limited on free tier)_ |
| zai-glm-4.7                    | `cerebras-glm-4.7` _(rate-limited on free tier)_      |
| llama3.1-8b                    | `cerebras-llama-3.1-8b`                               |

### OpenAI (API key)

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

## Model Groups

Hit these as the model name and LiteLLM routes to the best available with automatic fallback:

| Group           | Members (priority order)                                                                                                                                                                                                                                                                   |
| --------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `fast`          | groq-llama-3.1-8b → cerebras-llama-3.1-8b → claude-code-haiku → claude-code-glm-4.5-air → hf-llama-3.1-8b → openai-gpt-4o-mini                                                                                                                                                             |
| `smart`         | cerebras-qwen3-235b → claude-code-sonnet → or-hermes-3-405b → or-qwen3-80b → cerebras-gpt-oss-120b → or-nemotron-120b → or-minimax-m2.5 → claude-code-glm-4.7 → cerebras-glm-4.7 → openai-gpt-4o → anthropic-claude-sonnet-4 → claude-code-opus → claude-code-glm-5.1 → groq-llama-3.3-70b |
| `vision`        | openai-gpt-4o → anthropic-claude-sonnet-4 → claude-code-sonnet → claude-code-glm-4.7 → groq-llama-4-scout → hf-llama-4-scout → hf-qwen-vl-72b                                                                                                                                              |
| `image-gen`     | openai-dall-e-3 → hf-flux-schnell → hf-flux-dev                                                                                                                                                                                                                                            |
| `transcription` | groq-whisper-large-v3-turbo → groq-whisper-large-v3 → openai-whisper                                                                                                                                                                                                                       |

## Setup

### 1. Clone

```bash
git clone https://github.com/psyb0t/docker-litellm
cd docker-litellm
```

### 2. Configure

```bash
cp .env.example .env
```

Edit `.env` and fill in your keys:

```env
# Required — change this, it's your LiteLLM master key
LITELLM_MASTER_KEY=sk-your-secret-here

# Required for Claude Code models (OAuth subscription token)
# Get it: claude setup-token
CLAUDE_CODE_OAUTH_TOKEN=sk-ant-oat01-...

# Required for GLM/z.ai models
# Get it: https://z.ai
ZAI_AUTH_TOKEN=...

# Required for Groq models (free)
# Get it: https://console.groq.com
GROQ_API_KEY=gsk_...

# Required for HuggingFace models (free tier)
# Get it: https://huggingface.co/settings/tokens
HF_TOKEN=hf_...

# Optional — only needed if you want OpenAI models
OPENAI_API_KEY=sk-...

# Optional — only needed if you want direct Anthropic API models
ANTHROPIC_API_KEY=sk-ant-...
```

### 3. Run

```bash
docker compose up -d
```

LiteLLM UI and API at `http://localhost:4000`

### 4. Test

```bash
curl http://localhost:4000/chat/completions \
  -H "Authorization: Bearer YOUR_LITELLM_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{"model": "groq-llama-3.1-8b", "messages": [{"role": "user", "content": "hello"}]}'
```

## Claude Code OAuth token

The `CLAUDE_CODE_OAUTH_TOKEN` is the OAuth token used by the Claude Code CLI. Get it by running `claude setup-token` with an existing [Claude Code](https://github.com/psyb0t/docker-claude-code) install.

The token expires daily. To refresh:

```bash
# Run claude once to auto-refresh the credentials file, then:
TOKEN=$(python3 -c "import json; print(json.load(open('$HOME/.claude/.credentials.json'))['claudeAiOauth']['accessToken'])")
sed -i "s|^CLAUDE_CODE_OAUTH_TOKEN=.*|CLAUDE_CODE_OAUTH_TOKEN=$TOKEN|" .env
docker compose restart claude-code
```

## Notes

- Postgres and Redis data persist in named volumes across restarts
- LiteLLM waits for all dependencies (including claude-code containers) to be healthy before starting
- Routing strategy is latency-based with automatic retries and fallbacks
- Free-tier priority: `smart` and `fast` groups prefer `claude-code-*` and `claude-code-glm-*` (no per-token cost) before falling back to paid APIs
- HuggingFace free tier is ~$0.10/month in credits — use smaller models for daily driving
- The `claude-code-*` and `claude-code-glm-*` models support file-based workflows via the workspace header — Claude Code can read/write files, not just chat

## License

WTFPL
