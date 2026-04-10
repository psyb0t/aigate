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
| Model | Alias |
|-------|-------|
| llama-3.1-8b-instant | `llama-3.1-8b` |
| llama-3.3-70b-versatile | `llama-3.3-70b` |
| llama-4-scout-17b-16e-instruct | `llama-4-scout` *(multimodal)* |
| moonshotai/kimi-k2-instruct | `kimi-k2` |
| openai/gpt-oss-20b | `gpt-oss-20b` |
| openai/gpt-oss-120b | `gpt-oss-120b` |
| qwen/qwen3-32b | `qwen3-32b` |
| compound-beta | `compound` |
| compound-beta-mini | `compound-mini` |
| whisper-large-v3 | `whisper-large-v3` |
| whisper-large-v3-turbo | `whisper-large-v3-turbo` |

### HuggingFace Inference Providers (free tier)
| Model | Alias |
|-------|-------|
| meta-llama/Llama-3.1-8B-Instruct | `hf-llama-3.1-8b` |
| meta-llama/Llama-3.3-70B-Instruct | `hf-llama-3.3-70b` |
| meta-llama/Llama-4-Scout-17B-16E-Instruct | `hf-llama-4-scout` *(multimodal)* |
| Qwen/Qwen3-8B | `hf-qwen3-8b` |
| Qwen/QwQ-32B | `hf-qwq-32b` |
| deepseek-ai/DeepSeek-R1 | `hf-deepseek-r1` |
| Qwen/Qwen2.5-VL-72B-Instruct | `hf-qwen-vl-72b` *(multimodal)* |
| Qwen/Qwen2.5-VL-7B-Instruct | `hf-qwen3-vl-8b` *(multimodal)* |
| google/gemma-3-12b-it | `hf-gemma-3-12b` *(multimodal)* |
| black-forest-labs/FLUX.1-schnell | `flux-schnell` *(image gen)* |
| black-forest-labs/FLUX.1-dev | `flux-dev` *(image gen)* |
| stabilityai/stable-diffusion-3.5-large-turbo | `sd-3.5-turbo` *(image gen)* |

### Anthropic (API key)
| Model | Alias |
|-------|-------|
| claude-opus-4-6 | `claude-opus-4` *(multimodal)* |
| claude-sonnet-4-6 | `claude-sonnet-4` *(multimodal)* |
| claude-haiku-4-5 | `claude-haiku-4` *(multimodal)* |

### Claude Code — via OAuth
Uses [docker-claude-code](https://github.com/psyb0t/docker-claude-code) in API mode with a Claude OAuth token. Claude Code runs the actual CLI under the hood so it's not just a chat API — it can use tools, read/write files in the workspace, run shell commands, etc.

| Model | Alias |
|-------|-------|
| opus | `claude-code-opus` |
| sonnet | `claude-code-sonnet` |
| haiku | `claude-code-haiku` |

**Workspace control** — pass `x-claude-workspace` in `extra_headers` to isolate sessions:
```json
{
  "model": "claude-code-haiku",
  "messages": [{"role": "user", "content": "..."}],
  "extra_headers": {"x-claude-workspace": "myproject"}
}
```
Each workspace gets its own conversation history and file context. Different callers using different workspaces run fully concurrently.

### GLM via z.ai — via Claude Code adapter
[z.ai](https://z.ai) provides an Anthropic-compatible API that serves GLM models. This stack routes through a second docker-claude-code instance pointed at z.ai, so the same workspace/tool-use capabilities apply.

| Model | Alias |
|-------|-------|
| glm-5.1 | `glm-5.1` |
| glm-4.7 | `glm-4.7` |
| glm-4.5-air | `glm-4.5-air` |

### OpenAI (API key)
| Model | Alias |
|-------|-------|
| gpt-4o | `gpt-4o` *(multimodal)* |
| gpt-4o-mini | `gpt-4o-mini` *(multimodal)* |
| o3 | `o3` |
| o3-mini | `o3-mini` |
| dall-e-3 | `dall-e-3` *(image gen)* |
| gpt-image-1 | `gpt-image-1` *(image gen)* |
| whisper-1 | `whisper-openai` |
| tts-1 | `tts-1` |
| tts-1-hd | `tts-1-hd` |

## Model Groups

Hit these as the model name and LiteLLM routes to the best available with automatic fallback:

| Group | Members |
|-------|---------|
| `fast` | llama-3.1-8b → hf-llama-3.1-8b → gpt-4o-mini |
| `smart` | gpt-4o → claude-sonnet-4 → llama-3.3-70b |
| `vision` | gpt-4o → claude-sonnet-4 → llama-4-scout → hf-llama-4-scout → hf-qwen-vl-72b |
| `image-gen` | dall-e-3 → flux-schnell → flux-dev |
| `transcription` | whisper-large-v3-turbo → whisper-large-v3 → whisper-openai |

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
  -d '{"model": "llama-3.1-8b", "messages": [{"role": "user", "content": "hello"}]}'
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
- HuggingFace free tier is ~$0.10/month in credits — use smaller models for daily driving
- The `claude-code-*` and `glm-*` models support file-based workflows via the workspace header — Claude Code can read/write files, not just chat

## License

WTFPL
