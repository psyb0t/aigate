# LibreChat (optional, `LIBRECHAT=1`)

Web UI for LLM interaction at `/librechat/`. Pre-configured with all LiteLLM models and MCP tools. Uses MongoDB for conversation storage.

| Endpoint      | URL                          | Auth                     |
| ------------- | ---------------------------- | ------------------------ |
| Web UI        | `GET /librechat/`            | email/password (own auth)|
| API           | `/librechat/api/*`           | JWT (managed by LibreChat)|

### Authentication

LibreChat has its own email/password authentication — no basic auth (SPAs and basic auth are incompatible due to Authorization header collision). The first registered user automatically becomes admin. After creating your account, set `LIBRECHAT_ALLOW_REGISTRATION=false` in `.env` and restart to lock registration.

### MCP tools integration

All MCP tools from the LiteLLM aggregated endpoint are available in LibreChat conversations. Connected via streamable-http with `apiKey.source: admin` (bypasses LibreChat's OAuth detection probe). Configuration in `librechat/librechat.yaml`.

### Environment variables

| Variable                              | Default                                  | Description                                  |
| ------------------------------------- | ---------------------------------------- | -------------------------------------------- |
| `LIBRECHAT_DOMAIN_CLIENT`             | `http://librechat:3080/librechat`        | Public URL for client (sets `<base href>`)   |
| `LIBRECHAT_DOMAIN_SERVER`             | `http://librechat:3080/librechat`        | Public URL for server API                    |
| `LIBRECHAT_CREDS_KEY`                 | —                                        | Encryption key for stored credentials (64 hex chars) |
| `LIBRECHAT_CREDS_IV`                  | —                                        | Encryption IV (32 hex chars)                 |
| `LIBRECHAT_JWT_SECRET`                | —                                        | JWT signing secret                           |
| `LIBRECHAT_TITLE_MODEL`               | `groq-gpt-oss-120b`                      | Model for auto-titling conversations         |
| `LIBRECHAT_ALLOW_REGISTRATION`        | `true`                                   | Set to `false` after creating admin account  |
| `LIBRECHAT_ALLOW_EMAIL_LOGIN`         | `true`                                   | Enable email/password login                  |
| `LIBRECHAT_ALLOW_SOCIAL_LOGIN`        | `false`                                  | Enable social login providers                |
| `LIBRECHAT_ALLOW_UNVERIFIED_EMAIL_LOGIN` | `true`                                | Allow login without email verification       |
| `LIBRECHAT_DEBUG_LOGGING`             | `true`                                   | Enable debug-level logging                   |
| `LIBRECHAT_DEBUG_CONSOLE`             | `false`                                  | Log to console (in addition to file)         |
| `LIBRECHAT_MEM_LIMIT`                 | `512m`                                   | LibreChat container memory limit             |
| `LIBRECHAT_MEMSWAP_LIMIT`             | `1g`                                     | LibreChat container memory + swap limit      |
| `LIBRECHAT_CPUS`                      | `1.0`                                    | LibreChat CPU limit                          |
| `LIBRECHAT_MONGO_MEM_LIMIT`           | `512m`                                   | MongoDB container memory limit               |
| `LIBRECHAT_MONGO_MEMSWAP_LIMIT`       | `1g`                                     | MongoDB container memory + swap limit        |
| `LIBRECHAT_MONGO_CPUS`                | `0.5`                                    | MongoDB CPU limit                            |
| `TIMEOUT_LIBRECHAT`                   | `600s`                                   | Nginx proxy timeout                          |
| `LIBRECHAT_MAX_BODY_SIZE`             | `25m`                                    | Max upload size                              |
| `DATA_DIR_LIBRECHAT`                  | `${DATA_DIR}/librechat`                  | Data directory (MongoDB + uploads)           |

---


## Usage

### LibreChat Web UI

Enable with `LIBRECHAT=1` in `.env`. Access at `http://localhost:4000/librechat/`.

### First-time setup

1. Navigate to `http://localhost:4000/librechat/`
2. Register an account — the first user automatically becomes admin
3. Set `LIBRECHAT_ALLOW_REGISTRATION=false` in `.env` and restart (`docker compose restart librechat`) to lock registration

### What's pre-configured

- All LiteLLM models are available in the model selector (auto-fetched)
- All MCP tools (browser, storage, claudebox, image generation, TTS) are connected and available in conversations
- Conversations are stored in MongoDB and persist across restarts
- WebSocket streaming for real-time responses

### Configuration

All settings are customizable via `.env` — see [the LibreChat service page](librechat.md) for the full list of environment variables.

The LibreChat config file at `librechat/librechat.yaml` controls endpoints, MCP servers, and interface settings. Edit it directly for advanced customization (e.g. adding more MCP servers, changing interface options).

---

