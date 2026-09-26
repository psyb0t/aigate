# vllm / vllm-cuda — local LLM + embeddings (optional, `VLLM=1` / `VLLM_CUDA=1`)

Supervised wrapper around `vllm serve` that holds at most one model in memory at a time. Lazy-loads on first request for a given model_id, idle-unloads after `VLLM_*_MODEL_TTL`, and exposes the same `/api/ps` + `DELETE /api/ps/{model_id}` lifecycle surface as talkies so the LiteLLM resource_manager can swap models in/out of memory under contention.

Both variants share the supervisor (`vllm/src/vllm_wrap/`), built from `vllm/` with `Dockerfile.cpu` (`vllm/vllm-openai-cpu` base) or `Dockerfile.cuda` (`vllm/vllm-openai:v0.21.0` base). Each ships its own model list:

- `vllm/models.cpu.json` — CPU-tuned `vllm_args` (no `--gpu-memory-utilization`, smaller context for Qwen3 to bound KV cache RAM)
- `vllm/models.cuda.json` — CUDA-tuned `vllm_args` (gpu memory split, larger context)

Each entry maps a slug to `{repo, vllm_args, endpoints}`. Endpoints must be a subset of `{"chat", "completions", "embeddings"}`. Both variants share `${DATA_DIR_VLLM}/models/<org>/<repo>/` (populated once by `vllm-pull`) so enabling both does not duplicate downloads.

| Endpoint                                  | URL (via litellm)                  | Auth                              |
| ----------------------------------------- | ---------------------------------- | --------------------------------- |
| Chat (OpenAI-compat)                      | `POST /v1/chat/completions`        | `Bearer $LITELLM_MASTER_KEY`      |
| Completions (legacy OpenAI)               | `POST /v1/completions`             | `Bearer $LITELLM_MASTER_KEY`      |
| Embeddings                                | `POST /v1/embeddings`              | `Bearer $LITELLM_MASTER_KEY`      |
| Health (internal)                         | `GET vllm-cuda:8000/healthz`       | none                              |
| Loaded models (internal)                  | `GET vllm-cuda:8000/api/ps`        | none                              |
| Unload one (internal — resource_manager)  | `DELETE vllm-cuda:8000/api/ps/{id}`| none                              |
| Unload all (internal)                     | `POST vllm-cuda:8000/unload`       | none                              |

Default models:

- `bge-m3` (CPU): `BAAI/bge-m3` (multilingual, 8192-token context, embeddings only)
- `nomic-embed-v1.5` (CPU): `nomic-ai/nomic-embed-text-v1.5` (English, 2048-token context, embeddings only)
- `nomic-embed-v2` (CUDA): `nomic-ai/nomic-embed-text-v2-moe` (MoE, 305M active, 512-token context, embeddings only)
- `qwen3-0.6b` (both): `Qwen/Qwen3-0.6B` (chat + completions; 8192 ctx on CPU, 16384 on CUDA)

The vLLM CPU build has no Mixture-of-Experts kernels, so Nomic Embed v2 (a MoE model) is CUDA-only and the CPU variant serves the dense BGE-M3 and Nomic Embed v1.5 instead.

LiteLLM aliases register per enabled variant:

- `VLLM=1` → `local-vllm-bge-m3`, `local-vllm-nomic-embed-v1.5`, `local-vllm-qwen3-0.6b`
- `VLLM_CUDA=1` → `local-vllm-cuda-nomic-embed-v2`, `local-vllm-cuda-qwen3-0.6b`

Every tunable below has a CPU (`VLLM_*`) and CUDA (`VLLM_CUDA_*`) counterpart with the same meaning and default:

| Tunable | Default | Notes |
| ------- | ------- | ----- |
| `VLLM_MODEL_TTL` / `VLLM_CUDA_MODEL_TTL` | `600` | Seconds idle before the subprocess is killed (`-1` disables) |
| `VLLM_SWEEPER_INTERVAL` / `VLLM_CUDA_SWEEPER_INTERVAL` | `60` | How often the idle sweeper checks (seconds) |
| `VLLM_LOAD_TIMEOUT` / `VLLM_CUDA_LOAD_TIMEOUT` | `600` | Max time to wait for `/health` after spawning `vllm serve` |
| `VLLM_REQUEST_TIMEOUT` / `VLLM_CUDA_REQUEST_TIMEOUT` | `300` | Per-request proxy timeout |
| `VLLM_LOG_LEVEL` / `VLLM_CUDA_LOG_LEVEL` | `INFO` | Wrapper log level |
| `VLLM_PRELOAD` / `VLLM_CUDA_PRELOAD` | _empty_ | Pre-spawn this model_id at boot |
| `VLLM_PREFETCH` / `VLLM_CUDA_PREFETCH` | _empty_ | Comma-separated model_ids the entrypoint should fetch on first start |
| `VLLM_MEM_LIMIT` / `VLLM_CUDA_MEM_LIMIT` | `12g` | Container memory limit |
| `VLLM_CPUS` / `VLLM_CUDA_CPUS` | `4.0` | Container CPU limit |
| `VLLM_CPU_KVCACHE_SPACE` | `4` | CPU-only: GB of RAM reserved for the vllm KV cache |
| `DATA_DIR_VLLM` | `${DATA_DIR}/vllm` | Bind-mount root for the wrapper's `/data` dir. Holds the flat HF-repo layout under `models/<org>/<repo>/<files>` (no blobs/snapshots dedup) — `vllm-pull` populates this via `huggingface-cli download <repo> --local-dir <path>`. Both CPU and CUDA wrappers, and any other service mounting the same dir, share the same files. |

---

