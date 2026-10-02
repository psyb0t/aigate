# decidealot (optional, `DECIDEALOT=1` / `DECIDEALOT_CUDA=1`)

Typed decisions with local Laya, Von, and optional CLM, or hosted TypeSafe Jev, served by [decidealot](https://github.com/psyb0t/decidealot) behind the TypeSafe System One API. You send the `state` to judge and one or more named questions. Each question is typed `choice`, `score`, or `noul`, and each answer comes back with model probabilities. The models do not write prose or run an action. The caller picks the threshold and decides what happens next.

Direct nginx route, not via LiteLLM. The MCP tools join the aggregated `/mcp/`.

CPU and CUDA variants run side-by-side on distinct routes and aliases: `/decidealot/` goes to the CPU container, `/decidealot-cuda/` to the GPU container. Enable either or both. CUDA needs `nvidia-container-toolkit`. Both mount `${DATA_DIR_DECIDEALOT}/models`, so the second variant reuses the bundles the first one downloaded.

| Endpoint         | CPU (`DECIDEALOT=1`)                        | CUDA (`DECIDEALOT_CUDA=1`)                       |
| ---------------- | ------------------------------------------- | ------------------------------------------------ |
| Decision         | `POST http://localhost:4000/decidealot/v1/systemone` | `POST http://localhost:4000/decidealot-cuda/v1/systemone` |
| Batch decisions  | `POST http://localhost:4000/decidealot/v1/systemone/batch` | `POST http://localhost:4000/decidealot-cuda/v1/systemone/batch` |
| Models           | `GET http://localhost:4000/decidealot/v1/models` | `GET http://localhost:4000/decidealot-cuda/v1/models` |
| Unload           | `POST http://localhost:4000/decidealot/v1/models/unload` | `POST http://localhost:4000/decidealot-cuda/v1/models/unload` |
| MCP (direct)     | `http://localhost:4000/decidealot/mcp`      | `http://localhost:4000/decidealot-cuda/mcp`      |
| MCP (aggregated) | `http://localhost:4000/mcp/` (`decidealot-*` prefix) | `http://localhost:4000/mcp/` (`decidealot_cuda-*` prefix) |
| Health           | `http://localhost:4000/decidealot/health`   | `http://localhost:4000/decidealot-cuda/health`   |

Auth: `Authorization: Bearer $DECIDEALOT_AUTH_TOKEN`, which defaults to `AIGATE_TOKEN`. `/health` is open.

## Models

| Selector | Runs | Use it when |
| --- | --- | --- |
| `laya`, `laya-auto`, `laya-latest` | Laya, picking the English or multilingual checkpoint from the input script | Mixed or unknown languages. The default. |
| `laya-english` | Laya's English checkpoint | English, Latin-script input |
| `laya-multilingual` | Laya's multilingual checkpoint | Known non-English input, including short Latin-script text auto-routing can misread |
| `laya-typed-decisions` | Laya's checkpoint tuned for structured decisions | Repeated policy, routing, triage, or approval decisions. Validate on your own cases first. |
| `von`, `von-latest`, `von-1.1`, `von-1.1.0` | Von 1.1, English only | Short questions with clear criteria, or a second opinion next to Laya |
| `clm`, `clm-latest`, `clm-0.1`, `clm-0.1-8b` | CLM v0.1 projection head over local Qwen3-8B embeddings | Repeated typed decisions where you want the CLM model. Requires the CLM setup below. |

Hosted Jev is optional. Set `DECIDEALOT_TYPESAFE_API_KEY` in the gitignored `.env`, then `GET /v1/models` lists the exact Jev names available to that account. Decidealot refreshes TypeSafe's catalog every 60 seconds and accepts those names without hardcoded aliases. Jev receives the complete decision state and questions over HTTPS. `DECIDEALOT_JEV_ENABLED=false` disables it even when a key is present.

One local provider is resident per container by default. `DECIDEALOT_MAX_RESIDENT_LOCAL_PROVIDERS` can raise that limit to three if memory permits. Moving between Laya selectors stays on Laya. With one slot, moving to Von or CLM waits for active work, releases the old model and its Torch memory, then starts the selected provider. An idle provider is released after `DECIDEALOT_PROVIDER_IDLE_UNLOAD_SECONDS` (600 by default). AIGate's resource manager also calls `POST /v1/models/unload` before LiteLLM-routed local model work starts, and `POST /v1/unload/{cuda,cpu}` includes Decidealot. A decision in flight returns `409`, so the unload is skipped and the provider stays until its idle timer. See [resource management](../resource-management.md). A request sent straight to Decidealot does not evict LiteLLM-routed models.

Measured on this stack, CPU with the bundles on a network share: a cold Laya start plus the first decision took about 75 seconds, a warm Laya decision about 1 second, and a swap to Von about 80 seconds. On CUDA the cold starts ran 2 to 2.5 minutes because of first-run kernel compilation, then warm decisions returned in under a second.

## First start and storage

The first start downloads and verifies the enabled pinned bundles from Hugging Face before `/health` passes. Laya and Von are enabled by default. CLM is disabled by default. The health check allows 15 minutes for preparation. Later starts reuse `${DATA_DIR_DECIDEALOT}/models/{laya,von,clm}` and come up in seconds. Set `HF_TOKEN` to raise the Hugging Face rate limit. The repos are public, so it is optional.

## Enable CLM with the local encoder

Set these flags in `.env`, then run `make run-bg`. The Makefile starts the `decidealot` and `llamacpp-cuda` profiles together. The Decidealot container calls LiteLLM on AIGate's internal network. LiteLLM routes the request to `local-llamacpp-cuda-qwen3-8b`. The Qwen model is embeddings-only and receives the rendered decision state and criteria. It does not become an external service or need another key.

```dotenv
DECIDEALOT=1
DECIDEALOT_CLM_ENABLED=true
LLAMACPP_CUDA=1
```

Keep `DECIDEALOT_CLM_EMBEDDINGS_URL`, `DECIDEALOT_CLM_EMBEDDINGS_MODEL`, and `DECIDEALOT_CLM_EMBEDDINGS_API_KEY` at their defaults unless you intentionally operate a different trusted Qwen3-8B embeddings service. The defaults use `http://litellm:4000/v1/embeddings`, `local-llamacpp-cuda-qwen3-8b`, and AIGate's LiteLLM credential.

The containers run as `DECIDEALOT_UID:DECIDEALOT_GID` (default `1000:1000`) with a read-only root filesystem, no capabilities, and `no-new-privileges`. The models directory must be writable by that user. The repo ships `.data/decidealot/models/` so a fresh clone gets it owned by the cloning user. If you point `DATA_DIR_DECIDEALOT` elsewhere, create `models/` there with the right owner first.

The CUDA variant also mounts a 512 MB `/var/cache` tmpfs with `exec` allowed. Triton compiles CUDA helpers at runtime and loads them from there, and every other writable path is `noexec`.

## Usage

### Choice

```bash
curl http://localhost:4000/decidealot/v1/systemone \
  -H "Authorization: Bearer $AIGATE_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "laya",
    "state": "A proposed action would permanently delete protected data.",
    "questions": {
      "handling": {
        "type": "choice",
        "instructions": "Choose the required handling for this action.",
        "criteria": {
          "allow": "The action is reversible and does not affect protected data.",
          "require_review": "The action is irreversible or affects protected data."
        }
      }
    }
  }'
```

```json
{"model":"laya","answers":{"handling":{"type":"choice","choice":"require_review","confidence":0.0217,"probabilities":{"allow":0.4134,"require_review":0.5866}}},"usage":{"input_tokens":52,"output_tokens":0}}
```

`choice` needs named `criteria`. The answer has the picked key and a probability per key.

### Score and noul in one request

```bash
curl http://localhost:4000/decidealot/v1/systemone \
  -H "Authorization: Bearer $AIGATE_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "von",
    "state": "The production database is down and customers cannot log in.",
    "questions": {
      "priority": {
        "type": "score",
        "instructions": "Score the response priority.",
        "criteria": ["Routine, answer in the normal queue.", "Important, answer soon.", "Urgent, interrupt the on-call queue."]
      },
      "needs_review": {
        "type": "noul",
        "instructions": "Is human review required before the change runs?",
        "criteria": {"true": "Review is required before the operation.", "false": "The operation may run without human review."}
      }
    }
  }'
```

```json
{"model":"von-1.1","answers":{"priority":{"type":"score","score":1.44,"confidence":0.11,"legend":{"0":"Routine, answer in the normal queue.","1":"Important, answer soon.","2":"Urgent, interrupt the on-call queue."},"probabilities":{"0":0.0002,"1":0.555,"2":0.4449}},"needs_review":{"type":"noul","noul":0.6012}},"usage":{"input_tokens":34,"output_tokens":2}}
```

`score` takes an ordered criteria array. Position is the score, so `score` is a weighted position and `legend` maps positions back to text. `noul` returns a probability between 0 and 1 for the `true` side.

### Release model memory

```bash
curl -X POST http://localhost:4000/decidealot/v1/models/unload \
  -H "Authorization: Bearer $AIGATE_TOKEN"
```

### MCP

Four tools: `system_one` (same `model`, `state`, `questions` fields as the REST call), `system_one_batch` (a list of independent requests), `list_models`, and `unload_models`. Through the aggregator they appear as `decidealot-system_one` and `decidealot_cuda-system_one` and so on. See [the MCP tools page](../mcp-tools.md#decidealot-typed-decisions-decidealot1-or-decidealot_cuda1).

decidealot keeps the MCP SDK's DNS-rebinding protection on. Its MCP endpoint answers `421` to a `Host` outside `DECIDEALOT_MCP_ALLOWED_HOSTS` and `403` to a browser `Origin` outside `DECIDEALOT_MCP_ALLOWED_ORIGINS`. aigate sets each container's host list to loopback plus its own service name (`decidealot` or `decidealot-cuda`), which is what LiteLLM's MCP client sends. The nginx routes send `Host: 127.0.0.1:8080` upstream because aigate cannot know your tailnet or tunnel hostname, so direct MCP through nginx works from any of them without extra config. A browser-based MCP client on a public domain also needs that origin in `DECIDEALOT_MCP_ALLOWED_ORIGINS`. Non-browser clients do not send `Origin`.

## Configuration

Env vars: `DECIDEALOT_AUTH_TOKEN`, `DECIDEALOT_UID`, `DECIDEALOT_GID`, `DECIDEALOT_PROVIDER_IDLE_UNLOAD_SECONDS`, `DECIDEALOT_MAX_RESIDENT_LOCAL_PROVIDERS`, `DECIDEALOT_MAX_BATCH_REQUESTS`, `DECIDEALOT_MAX_BATCH_CONCURRENCY`, `DECIDEALOT_REQUEST_TIMEOUT_SECONDS`, `DECIDEALOT_PROVIDER_START_TIMEOUT_SECONDS`, `DECIDEALOT_{LAYA,VON,CLM}_ENABLED`, `DECIDEALOT_CLM_EMBEDDINGS_{URL,MODEL,API_KEY,TIMEOUT_SECONDS}`, `DECIDEALOT_CLM_PARALLEL_WITH_LOCAL_MODELS`, `DECIDEALOT_TYPESAFE_API_KEY`, `DECIDEALOT_JEV_ENABLED`, `DECIDEALOT_MAX_REQUEST_BYTES`, `DECIDEALOT_LOG_LEVEL`, `DECIDEALOT_MCP_ALLOWED_HOSTS`, `DECIDEALOT_CUDA_MCP_ALLOWED_HOSTS`, `DECIDEALOT_MCP_ALLOWED_ORIGINS`, `DATA_DIR_DECIDEALOT`, resource limits `DECIDEALOT[_CUDA]_{MEM_LIMIT,MEMSWAP_LIMIT,CPUS,PIDS_LIMIT}`, per-route `RATELIMIT_DECIDEALOT[_BURST]` and `RATELIMIT_DECIDEALOT_CUDA[_BURST]`, and shared `TIMEOUT_DECIDEALOT`. Full reference in [`.env.example`](../../.env.example).

Upstream docs: [API](https://github.com/psyb0t/decidealot/blob/main/docs/api.md) for request rules, validation errors, and response shapes, and [deployment](https://github.com/psyb0t/decidealot/blob/main/docs/deployment.md).
