# sd.cpp — Local Image Generation (optional, `SDCPP=1`)

Local image generation via [stable-diffusion.cpp](https://github.com/leejet/stable-diffusion.cpp) with a Go wrapper. CPU variant runs with `SDCPP=1`, CUDA variant with `SDCPP_CUDA=1`. Both expose an OpenAI-compatible `/v1/images/generations` endpoint proxied through LiteLLM.

### Endpoints (internal — accessed through LiteLLM, not directly via nginx)

| Endpoint | URL | Description |
| -------- | --- | ----------- |
| Image generation | `POST /v1/images/generations` | OpenAI-compatible, proxied through LiteLLM |
| Load model | `POST /sdcpp/v1/load?model=<key>` | Pre-load a model without generating |
| Unload model | `POST /sdcpp/v1/unload` | Free VRAM/RAM |
| Cancel generation | `POST /sdcpp/v1/cancel` | Kill in-progress generation |
| Status | `GET /sdcpp/v1/status` | Current state: loaded model, generating, process info |
| Models list | `GET /v1/models` | Available models |
| Health | `GET /health` | Wrapper health check |

### Models

**CPU** (`SDCPP=1`): sd-turbo, sdxl-turbo

**CUDA** (`SDCPP_CUDA=1`): sd-turbo, sdxl-turbo, sdxl-lightning, flux-schnell, juggernaut-xi

### Behavior

- **Auto-load**: sending a generation request loads the model automatically if not loaded
- **Model hot-swap**: requesting a different model stops the current sd-server, starts a new one
- **Idle timeout**: unloads model after 5 minutes of inactivity (configurable)
- **Non-blocking**: concurrent requests get 503 immediately instead of queuing. The LiteLLM resource manager semaphore handles scheduling.
- **CUDA resource manager**: only one CUDA job (LLM, image gen, TTS, STT) runs at a time. Competing services are unloaded before the request proceeds.

### Environment variables

| Variable | Default | Description |
| -------- | ------- | ----------- |
| `SDCPP_IDLE_TIMEOUT` | `5m` | CPU idle timeout before auto-unload |
| `SDCPP_CUDA_IDLE_TIMEOUT` | `5m` | CUDA idle timeout before auto-unload |
| `SDCPP_MEM_LIMIT` | `12g` | CPU container memory limit |
| `SDCPP_MEMSWAP_LIMIT` | `24g` | CPU container memory + swap limit |
| `SDCPP_CPUS` | `4.0` | CPU container CPU limit |
| `SDCPP_CUDA_MEM_LIMIT` | `12g` | CUDA container memory limit |
| `SDCPP_CUDA_MEMSWAP_LIMIT` | `24g` | CUDA container memory + swap limit |
| `SDCPP_CUDA_CPUS` | `4.0` | CUDA container CPU limit |
| `SDCPP_LOAD_TIMEOUT` / `SDCPP_CUDA_LOAD_TIMEOUT` | `10m` | Max time to wait for model load |
| `SDCPP_VERBOSE` / `SDCPP_CUDA_VERBOSE` | `false` | Debug logging |
| `SDCPP_LOG_LEVEL` / `SDCPP_CUDA_LOG_LEVEL` | `info` | Log level |

---

