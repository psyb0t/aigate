# mailbox (optional, `MAILBOX=1`)

IMAP+SMTP gateway at `/mailbox/`, backed by [docker-mailbox](https://github.com/psyb0t/docker-mailbox). One YAML config selects the accounts exposed through REST and MCP at `/mailbox/mcp`. Reads reach the upstream IMAP server; a SQLite database in the `mailbox-state` named volume persists audit records, send limits, checkpoints and webhook delivery state.

### Upgrade notes

The current service supports scoped tokens, replies, drafts, attachments, threads, identities and sanitized HTML. New token entries declare `name`, `token`, `scopes` and `mailboxes`. Existing string tokens remain valid with full access. Empty token lists deny protected routes. Use the example config for scoped credentials and mirror the aggregator token as `MAILBOX_AUTH_TOKEN`.

Reading a message no longer marks it seen. Deleting moves it to Trash; permanent deletion requires an explicit request from Trash and server support. SMTP sender addresses must match a configured identity. TLS certificates are verified, so private mail servers need a trusted CA bundle. MCP errors now carry a structured `error` object. Back up the `mailbox-state` volume with the account config; removing the volume loses local audit and delivery state.

Not registered with LiteLLM (no chat/completion surface). MCP is enabled by default via LiteLLM's `/mcp/` aggregator with a flat tool set (`mailbox-mailboxes`, `mailbox-inbox`, `mailbox-list_messages`, `mailbox-get_message`, `mailbox-search`, `mailbox-send`, `mailbox-mark_seen`, `mailbox-move`, `mailbox-delete`, …) — every per-account op takes `mailbox` as a parameter, so 100 inboxes ship the same handful of tools.

| Endpoint        | URL                                  | Auth         |
| --------------- | ------------------------------------ | ------------ |
| Health          | `GET /mailbox/health`                | open         |
| List mailboxes  | `GET /mailbox/mailboxes`             | Bearer token |
| Unified inbox   | `GET /mailbox/inbox`                 | Bearer token |
| Per-mailbox ops | `GET/POST/DELETE /mailbox/mailboxes/<name>/…`  | Bearer token |
| Send            | `POST /mailbox/mailboxes/<name>/send`          | Bearer token |
| MCP (direct)    | `/mailbox/mcp`                       | Bearer token |
| MCP (aggregated)| `/mcp/` (via LiteLLM master key)     | Master key   |

### Setup

1. Copy `mailbox/config.example.yaml` to a host path **outside git history** (recommended: `.data/mailbox/config.yaml` — `.data/**` is gitignored).
2. Fill in the IMAP/SMTP creds for each account.
3. Put at least one bearer token in `auth.tokens:` and mirror it as `MAILBOX_AUTH_TOKEN` in `.env` (the MCP aggregator uses this to reach `/mailbox/mcp`).
4. Set `MAILBOX_CONFIG` in `.env` to the absolute or repo-relative path of the YAML.
5. `MAILBOX=1` in `.env`, then `make run-bg`.

```bash
curl -s http://localhost:4000/mailbox/mailboxes -H "Authorization: Bearer $MAILBOX_AUTH_TOKEN" | jq
curl -s "http://localhost:4000/mailbox/inbox?limit=5" -H "Authorization: Bearer $MAILBOX_AUTH_TOKEN" | jq
```

The config file holds **plaintext IMAP/SMTP passwords + bearer tokens** — treat it like a private key. Never commit. `Makefile`'s `check_file_vars` validates `MAILBOX_CONFIG` resolves to an existing file before bringing the stack up.

### Environment variables

| Variable               | Default                  | Description                                                          |
| ---------------------- | ------------------------ | -------------------------------------------------------------------- |
| `MAILBOX_CONFIG`       | — (required)             | Host path to the mailbox YAML config                                 |
| `MAILBOX_AUTH_TOKEN`   | `change-me-mailbox-auth` | Bearer token; MUST also appear in the YAML's `auth.tokens:`          |
| `TIMEOUT_MAILBOX`      | `120s`                   | Nginx proxy timeout (IMAP fetches can be slow on large folders)      |
| `MAILBOX_MEM_LIMIT`    | `256m`                   | Container memory limit                                               |
| `MAILBOX_CPUS`         | `0.5`                    | CPU limit                                                            |

See [docker-mailbox README](https://github.com/psyb0t/docker-mailbox) for the full config schema, query params (`mailbox=`, `unseen=`, `from=`, reader-mode HTML stripping, etc.), and the complete MCP tool list.

---


## Usage

### Email gateway (mailbox)

With `MAILBOX=1`, the `/mailbox/` route fronts the accounts in `MAILBOX_CONFIG`. Reads reach IMAP live; local state persists in the `mailbox-state` volume. Bearer auth uses tokens from the config, with `MAILBOX_AUTH_TOKEN` selecting the aggregator credential.

```bash
# list configured accounts
curl http://localhost:4000/mailbox/mailboxes \
  -H "Authorization: Bearer $MAILBOX_AUTH_TOKEN"

# unified inbox across all accounts (paginated)
curl "http://localhost:4000/mailbox/inbox?limit=10" \
  -H "Authorization: Bearer $MAILBOX_AUTH_TOKEN"

# search a specific account
curl "http://localhost:4000/mailbox/inbox?mailbox=work&subject=invoice&limit=5" \
  -H "Authorization: Bearer $MAILBOX_AUTH_TOKEN"

# send through a configured account (SMTP)
curl -X POST http://localhost:4000/mailbox/mailboxes/work/send \
  -H "Authorization: Bearer $MAILBOX_AUTH_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"to": ["someone@example.com"], "subject": "hello", "body_text": "from aigate"}'

# delete by uid
curl -X DELETE http://localhost:4000/mailbox/mailboxes/work/messages/<uid> \
  -H "Authorization: Bearer $MAILBOX_AUTH_TOKEN"
```

The MCP catalog is flat regardless of how many accounts you've configured — per-account tools take a `mailbox` parameter (name or address) instead of namespacing.

→ [mailbox configuration](#configuration) · [mailbox MCP tools](../mcp-tools.md#mailbox--imapsmtp-gateway-mailbox1)

---

