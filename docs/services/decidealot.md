# decidealot (optional, `DECIDEALOT=1` / `DECIDEALOT_CUDA=1`)

Typed decisions with local Laya, Von, and CLM, or hosted TypeSafe Jev, served by [decidealot](https://github.com/psyb0t/decidealot) behind the TypeSafe System One API. You send the `state` to judge and one or more named questions. Each question is typed `choice`, `score`, or `noul`, and each answer comes back with model probabilities. The models do not write prose or run an action. The caller picks the threshold and decides what happens next.

Direct nginx route, not via LiteLLM. The MCP tools join the aggregated `/mcp/`.

Aigate builds a thin launcher on the upstream CPU/CUDA images. Decidealot's provider supervisor is injected, not patched. Each Laya/Von inference takes the existing Redis hardware lock, including direct REST, MCP and individual batch items. Before CUDA allocation, Aigate unloads its local llama.cpp encoder when the internal CLM route or standalone CUDA llama.cpp profile is enabled. It waits for a successful unload response; an unreachable, busy or malformed encoder response fails admission without loading Laya/Von. CPU Laya/Von uses the CPU lock and does not unload Qwen. CLM takes no outer lock because its nested embeddings request acquires LiteLLM's hardware lock. Hosted Jev takes no local hardware lock. Remote embedding endpoints remain outside Aigate's lifecycle control.

`AIGATE_DECIDEALOT_ENCODER_URL` controls Aigate's internal unload API, default `http://llamacpp-cuda:8000`, and `AIGATE_DECIDEALOT_UNLOAD_TIMEOUT_SECONDS` defaults to `30` (greater than zero, at most `300`). These are separate from `DECIDEALOT_CLM_EMBEDDINGS_URL`. `make build-decidealot` rebuilds the thin wrappers without recompiling the upstream CUDA stack. `make test-decidealot-coordination` runs admission tests with a throwaway Redis.

When CUDA Decidealot and its internal encoder share the GPU, Aigate also serializes CLM against local provider swaps, even if `DECIDEALOT_CLM_PARALLEL_WITH_LOCAL_MODELS=true`. Otherwise a swap could hold the GPU lock while waiting for CLM, which still needs that lock to finish embeddings. Remote encoder URLs do not take this shared-encoder lane.

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

One local provider is resident per container by default. `DECIDEALOT_MAX_RESIDENT_LOCAL_PROVIDERS` can raise that limit to three if memory permits. Moving between Laya selectors stays on Laya. With one slot, moving to Von or CLM waits for active work, releases the old model and its Torch memory, then starts the selected provider. An idle provider is released after `DECIDEALOT_PROVIDER_IDLE_UNLOAD_SECONDS` (600 by default). AIGate's resource manager also calls `POST /v1/models/unload` before LiteLLM-routed local model work starts, and `POST /v1/unload/{cuda,cpu}` includes Decidealot. A decision in flight returns `409`, so the unload is skipped and the provider stays until its idle timer. Direct CUDA Laya/Von requests evict the configured local encoder, not every LiteLLM-routed resident model. See [resource management](../resource-management.md).

Measured on this stack, CPU with the bundles on a network share: a cold Laya start plus the first decision took about 75 seconds, a warm Laya decision about 1 second, and a swap to Von about 80 seconds. On CUDA the cold starts ran 2 to 2.5 minutes because of first-run kernel compilation, then warm decisions returned in under a second.

## First start and storage

The first start downloads and verifies the enabled pinned bundles from Hugging Face before `/health` passes. Laya, Von, and CLM are enabled by default. Starting Decidealot with `make run-bg` also starts the CUDA Qwen3-8B embeddings route. Set `DECIDEALOT_CLM_ENABLED=false` when you want to run without that NVIDIA GPU dependency. Jev enables when its TypeSafe key is present. The health check allows 15 minutes for preparation. Later starts reuse `${DATA_DIR_DECIDEALOT}/models/{laya,von,clm}` and come up in seconds. Set `HF_TOKEN` to raise the Hugging Face rate limit. The repos are public, so it is optional.

## CLM with the local encoder

Set `DECIDEALOT=1` or `DECIDEALOT_CUDA=1` in `.env`, then run `make run-bg`. CLM is enabled by default, and the Makefile starts the `llamacpp-cuda` profile with it. The Decidealot container calls LiteLLM on AIGate's internal network. LiteLLM routes the request to `local-llamacpp-cuda-qwen3-8b`. The Qwen model is embeddings-only and receives the rendered decision state and criteria.

```dotenv
DECIDEALOT=1
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
