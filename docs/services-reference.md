# Services Reference

## LiteLLM

| Endpoint               | URL                                           |
| ---------------------- | --------------------------------------------- |
| Chat completions       | `POST http://localhost:4000/chat/completions` |
| Models list            | `GET http://localhost:4000/models`            |
| Health check           | `GET http://localhost:4000/health/liveliness` |
| MCP server (all tools) | `POST http://localhost:4000/mcp/`             |
| Admin UI               | `http://localhost:4000/litellm-admin/`        |

Authentication: all endpoints require `Authorization: Bearer $LITELLM_MASTER_KEY`.

The admin UI at `/litellm-admin/` is rate-limited (5 req/min) and optionally protected by HTTP basic auth — set `LITELLM_UI_BASIC_AUTH=user:password` in `.env` to enable it.

## Claudebox

| Endpoint                       | URL                                                                    |
| ------------------------------ | ---------------------------------------------------------------------- |
| Chat completions (via LiteLLM) | `POST http://localhost:4000/chat/completions` with model `claudebox-*` |
| Direct API                     | `http://localhost:4000/claudebox/`                                     |
| MCP server (OAuth)             | `http://localhost:4000/claudebox/mcp/`                                 |
| MCP server (GLM)               | `http://localhost:4000/claudebox-zai/mcp/`                             |
| OpenAI models list (OAuth)     | `GET http://localhost:4000/claudebox/openai/v1/models`                 |
| OpenAI models list (GLM)       | `GET http://localhost:4000/claudebox-zai/openai/v1/models`             |
| File upload                    | `PUT http://localhost:4000/claudebox/files/<workspace>/<path>`         |
| File download                  | `GET http://localhost:4000/claudebox/files/<workspace>/<path>`         |
| File list                      | `GET http://localhost:4000/claudebox/files/<workspace>`                |
| Workspace status               | `GET http://localhost:4000/claudebox/status`                           |
| Cancel run                     | `POST http://localhost:4000/claudebox/run/cancel?workspace=<name>`     |
| Health                         | `GET http://localhost:4000/claudebox/health`                           |

Authentication: `/claudebox/` endpoints use `Authorization: Bearer $CLAUDEBOX_API_TOKEN`. `/claudebox-zai/` endpoints use `Authorization: Bearer $CLAUDEBOX_ZAI_API_TOKEN`. Health endpoints require no auth.

Workspace isolation: pass `x-claude-workspace: <name>` in request headers. Each workspace gets its own directory, file context, and conversation history.

## Object Storage (hybrids3)

| Endpoint          | URL                                                      |
| ----------------- | -------------------------------------------------------- |
| Upload / download | `http://localhost:4000/storage/uploads/<key>`            |
| List bucket       | `GET http://localhost:4000/storage/uploads`              |
| Health            | `GET http://localhost:4000/storage/health`               |
| MCP server        | `http://localhost:4000/storage/mcp/`                     |
| S3-compatible     | `http://localhost:4000/storage` (use with boto3/aws-cli) |

Authentication: writes and deletes require `Authorization: Bearer $HYBRIDS3_UPLOADS_KEY`. Downloads from the `uploads` bucket are public (no auth).

## Browser Cluster (stealthy-auto-browse)

| Endpoint             | URL                                                                 |
| -------------------- | ------------------------------------------------------------------- |
| Browser API          | `POST http://localhost:4000/stealthy-auto-browse/`                  |
| Screenshot (browser) | `GET http://localhost:4000/stealthy-auto-browse/screenshot/browser` |
| Screenshot (desktop) | `GET http://localhost:4000/stealthy-auto-browse/screenshot/desktop` |
| MCP server           | `http://localhost:4000/stealthy-auto-browse/mcp/`                   |
| Queue health         | `GET http://localhost:4000/stealthy-auto-browse/__queue/health`     |
| Cluster status       | `GET http://localhost:4000/stealthy-auto-browse/__queue/status`     |

Configuration: 5 browser replicas by default (configurable via `STEALTHY_AUTO_BROWSE_NUM_REPLICAS`). Each replica has 256 MB RAM and up to 1 GB swap. HAProxy handles sticky routing:

- MCP requests are pinned by `Mcp-Session-Id` header
- All other requests are pinned by `INSTANCEID` cookie, with max 1 concurrent request per replica

## Cloudflared

Cloudflared is disabled by default. Enable it via `COMPOSE_PROFILES` in `.env`.

**Quick tunnel (no account needed):**

```env
COMPOSE_PROFILES=cloudflared
```

Cloudflare assigns a random `*.trycloudflare.com` URL and logs it on startup:

```bash
docker compose up -d
docker compose logs cloudflared | grep trycloudflare
```

**Named tunnel (fixed domain, requires Cloudflare account):**

```env
COMPOSE_PROFILES=cloudflared
CLOUDFLARED_CONFIG=/absolute/path/to/config.yml
CLOUDFLARED_CREDS=/absolute/path/to/credentials.json
```

Example `config.yml`:

```yaml
tunnel: <your-tunnel-id>
credentials-file: /etc/cloudflared/credentials.json
ingress:
  - hostname: aigate.yourdomain.com
    service: http://nginx:4000
  - service: http_status:404
```

Get your tunnel ID and credentials: [Cloudflare Tunnel guide](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/get-started/)
