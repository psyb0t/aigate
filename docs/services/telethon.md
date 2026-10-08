# Telethon Plus (optional, `TELETHON=1`)

Telegram client at `/telethon/`. Backed by [docker-telethon-plus](https://github.com/psyb0t/docker-telethon-plus) — exposes a REST API and MCP server for sending/reading messages, managing dialogs, forwarding content, and group operations.

| Endpoint        | URL                        | Auth         |
| --------------- | -------------------------- | ------------ |
| Health          | `GET /telethon/healthz`    | none         |
| REST API        | `/telethon/api/*`          | Bearer token |
| MCP server      | `/telethon/mcp`            | Bearer token |

### Setup

1. Get API credentials at [my.telegram.org/apps](https://my.telegram.org/apps)
2. Generate a string session:
   ```bash
   docker run -it --rm \
     -e TELETHON_API_ID=your_id \
     -e TELETHON_API_HASH=your_hash \
     psyb0t/telethon-plus:v0.2.0 login
   ```
3. Add to `.env`: `TELETHON=1`, `TELETHON_API_ID`, `TELETHON_API_HASH`, `TELETHON_SESSION`, `TELETHON_AUTH_KEY`

### Environment variables

| Variable                        | Default        | Description                              |
| ------------------------------- | -------------- | ---------------------------------------- |
| `TELETHON_API_ID`               | —              | Telegram app ID (required)               |
| `TELETHON_API_HASH`             | —              | Telegram app hash (required)             |
| `TELETHON_SESSION`              | —              | String session from login.py (required)  |
| `TELETHON_AUTH_KEY`             | `lulz-4-security` | Bearer token for REST + MCP auth      |
| `TELETHON_PROXY`                | —              | SOCKS5 proxy (`socks5://user:pass@host:port`) |
| `TELETHON_REQUEST_TIMEOUT`      | `60`           | Telegram API request timeout (seconds)   |
| `TELETHON_FLOOD_SLEEP_THRESHOLD`| `60`           | Auto-sleep on flood wait up to this many seconds |
| `TIMEOUT_TELETHON`              | `60s`          | Nginx proxy timeout                      |
| `TELETHON_MEM_LIMIT`            | `256m`         | Container memory limit                   |
| `TELETHON_MEMSWAP_LIMIT`        | `512m`         | Container memory + swap limit            |
| `TELETHON_CPUS`                 | `0.2`          | CPU limit                                |

---


## Usage

### Telegram client (telethon)

With `TELETHON=1`, the `/telethon/` route fronts a Telegram client using the official MTProto user-account API. Requires `TELETHON_API_ID` / `TELETHON_API_HASH` from [my.telegram.org/apps](https://my.telegram.org/apps) and a string session in `TELETHON_SESSION`. Bearer auth via `TELETHON_AUTH_KEY`.

```bash
# who am I — verifies the session is authorized
curl http://localhost:4000/telethon/api/me \
  -H "Authorization: Bearer $TELETHON_AUTH_KEY"

# list dialogs
curl "http://localhost:4000/telethon/api/dialogs?limit=10" \
  -H "Authorization: Bearer $TELETHON_AUTH_KEY"

# send a message (markdown supported via parse_mode)
curl -X POST http://localhost:4000/telethon/api/messages \
  -H "Authorization: Bearer $TELETHON_AUTH_KEY" \
  -H "Content-Type: application/json" \
  -d '{"chat": "@username", "text": "**hello** from aigate", "parse_mode": "md"}'

# read recent messages from a chat
curl "http://localhost:4000/telethon/api/messages?chat=me&limit=5" \
  -H "Authorization: Bearer $TELETHON_AUTH_KEY"
```

Chat references accept `@username`, phone numbers, `t.me/...` links, or numeric IDs as strings. The same surface is exposed as MCP tools (`telethon-send_message`, `telethon-get_dialogs`, etc.) so any function-calling model can operate Telegram on your behalf.

→ [Telethon configuration](#configuration) · [Telethon MCP tools](../mcp-tools.md#telethon-plus--telegram-client-telethon1)
