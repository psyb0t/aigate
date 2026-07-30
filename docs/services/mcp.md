# MCP Tools — Media Generation (auto-enabled)

Auto-enabled when any image or TTS provider is active (HuggingFace, OpenAI, Speaches, SDCPP, CUDA). Runs as an internal service — no direct nginx route, accessed only through LiteLLM's aggregated MCP endpoint at `/mcp/`.

| Endpoint               | URL                | Auth                              |
| ---------------------- | ------------------ | --------------------------------- |
| MCP server (via proxy) | `POST /mcp/`       | `Bearer $LITELLM_MASTER_KEY`      |
| Health (internal only) | `GET :8000/health`  | none (not exposed via nginx)      |

### Tools

- `generate_image` — create images from text prompts (FLUX, DALL-E, Stable Diffusion depending on enabled providers)
- `generate_tts` — generate speech audio from text (Kokoro, Qwen3-TTS, OpenAI TTS depending on enabled providers)

Both tools return structured JSON with persistent HybridS3 URLs — no base64 blobs sent to the LLM.

See [mcp-tools.md](../mcp-tools.md#mcp_tools--2-tools-auto-enabled-with-imagetts-providers) for full parameter reference.

### Environment variables

| Variable               | Default  | Description                          |
| ---------------------- | -------- | ------------------------------------ |
| `MCP_TOOLS_AUTH_TOKEN`  | —       | Bearer token for MCP auth (required) |
| `MCP_MEM_LIMIT`        | `256m`   | Container memory limit               |
| `MCP_MEMSWAP_LIMIT`    | `512m`   | Container memory + swap limit        |
| `MCP_CPUS`             | `0.5`    | CPU limit                            |
| `MCP_PIDS_LIMIT`       | `128`    | Process limit                        |

---
