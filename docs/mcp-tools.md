# MCP Tool Ecosystem

The [Model Context Protocol](https://modelcontextprotocol.io/) is what makes this gateway more than just an LLM router. Four MCP servers are registered in LiteLLM, exposing a total of 34 tools. Any model that supports tool use (function calling) can invoke these tools during a conversation — the model decides when and how to use them based on the user's request.

This means you can ask a Groq model to browse a website, take a screenshot, upload it to object storage, and return the public URL — and it will orchestrate all of that autonomously through MCP tool calls.

## Connecting

The gateway exposes a single aggregated MCP endpoint that proxies all four servers:

```
POST http://localhost:4000/mcp/
Authorization: Bearer $LITELLM_MASTER_KEY
Content-Type: application/json
Accept: application/json, text/event-stream
```

Each individual service also exposes its own MCP endpoint directly (routed via nginx):

| Server               | Endpoint                                            |
| -------------------- | --------------------------------------------------- |
| All tools (proxied)  | `http://localhost:4000/mcp/`                        |
| stealthy-auto-browse | `http://localhost:4000/stealthy-auto-browse/mcp/`   |
| hybrids3             | `http://localhost:4000/storage/mcp/`                |
| claudebox            | `http://localhost:4000/claudebox/mcp/`              |
| claudebox-zai        | `http://localhost:4000/claudebox-zai/mcp/`          |

```bash
# list all available MCP tools
curl -X POST http://localhost:4000/mcp/ \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}'
```

## stealthy_auto_browse — 17 tools

Stealth browser automation. Navigate pages, interact with elements using real mouse/keyboard input, extract content, and take screenshots. All interactions are undetectable by bot detection systems (passes Cloudflare, CreepJS, BrowserScan, Pixelscan).

| Tool                       | Description                                                              |
| -------------------------- | ------------------------------------------------------------------------ |
| `goto`                     | Navigate to a URL                                                        |
| `get_text`                 | Extract all visible text from the current page (up to 10,000 chars)      |
| `get_html`                 | Get the full HTML source of the current page                             |
| `get_interactive_elements` | Find all clickable/interactive elements with their viewport coordinates  |
| `screenshot`               | Capture the browser viewport or full desktop as PNG                      |
| `system_click`             | Click at specific viewport coordinates using OS-level mouse input        |
| `system_type`              | Type text using OS-level keyboard input                                  |
| `send_key`                 | Send a keyboard key (`enter`, `tab`, `escape`, arrow keys, etc.)         |
| `click`                    | Click a CSS selector                                                     |
| `fill`                     | Fill a form field by CSS selector                                        |
| `scroll`                   | Scroll the page up/down                                                  |
| `mouse_move`               | Move the mouse to specific coordinates                                   |
| `wait_for_element`         | Wait for a CSS selector to appear on the page                            |
| `wait_for_text`            | Wait for specific text to appear on the page                             |
| `eval_js`                  | Execute JavaScript in the browser context                                |
| `browser_action`           | Perform browser-level actions (`back`, `forward`, `refresh`)             |
| `run_script`               | Execute a multi-step automation script atomically                        |

### Usage notes

- Browser sessions are sticky — each MCP session is pinned to one replica by `Mcp-Session-Id` header. Maintain session continuity across tool calls within a conversation.
- `run_script` is the preferred tool for multi-step flows — it executes a sequence of actions atomically on the same replica without round-tripping through LiteLLM between steps.
- `system_click` / `system_type` use OS-level input simulation (PyAutoGUI) — completely undetectable, as they bypass CDP entirely.
- For page parsing, `get_interactive_elements` returns coordinates alongside element metadata, so you can click by coordinates instead of guessing CSS selectors.

## hybrids3 — 7 tools

Object storage operations. Upload, download, list, and manage files in storage buckets. The `uploads` bucket is public-read (downloads need no auth), but all writes require the bucket key via `auth_key`.

| Tool              | Auth required             | Description                                                                               |
| ----------------- | ------------------------- | ----------------------------------------------------------------------------------------- |
| `upload_object`   | bucket key or master key  | Upload text or base64-encoded binary. MIME type auto-detected if not specified.           |
| `download_object` | public bucket: none; private: bucket key | Download object content. Returns text or base64 binary. Max 50 MB via MCP. |
| `delete_object`   | bucket key or master key  | Delete an object.                                                                         |
| `list_objects`    | public bucket: none; private: bucket key | List objects with optional prefix filter. Max 1000 results.               |
| `list_buckets`    | master key (all) or bucket key (own only) | List configured buckets.                                                  |
| `object_info`     | public bucket: none; private: bucket key | Get metadata (size, content type, ETag, expiry) without downloading.     |
| `presign_url`     | bucket key or master key  | Generate a shareable URL. Plain URL for public buckets, signed+expiring for private ones. |

### Auth in tool calls

Each tool accepts an `auth_key` parameter — the bucket's private key or the master key. For the `uploads` bucket (public-read), reads need no `auth_key`. Writes always need it.

```
# example: upload via MCP
upload_object(bucket="uploads", key="images/photo.png", content="<base64>", auth_key="$HYBRIDS3_UPLOADS_KEY")

# example: public download — no auth needed
download_object(bucket="uploads", key="images/photo.png")

# example: generate presigned URL for a private object
presign_url(bucket="private-data", key="report.pdf", auth_key="$HYBRIDS3_MASTER_KEY", expires=3600)
```

## claudebox — 5 tools (OAuth or API key)

Agentic Claude Code backed by your Claude subscription or Anthropic API key. Each tool call runs through Claude Code's full agentic loop — it can read/write files, run shell commands, install packages, browse the web, and use tools within an isolated workspace. This is not a text generation call; it is a full agentic execution.

| Tool          | Description                                                                                                                                        |
| ------------- | -------------------------------------------------------------------------------------------------------------------------------------------------- |
| `claude_run`  | Run a prompt through Claude Code's full agentic loop. Returns the result text, session ID, token usage, and cost.                                  |
| `read_file`   | Read a file from the workspace.                                                                                                                    |
| `write_file`  | Write content to a file in the workspace (parent directories created automatically).                                                               |
| `list_files`  | List files and directories in the workspace.                                                                                                       |
| `delete_file` | Delete a file from the workspace.                                                                                                                  |

### claude_run parameters

| Parameter             | Type   | Description                                                              | Default         |
| --------------------- | ------ | ------------------------------------------------------------------------ | --------------- |
| `prompt`              | string | The prompt to send to Claude Code                                        | _(required)_    |
| `workspace`           | string | Workspace subpath (e.g., `myproject`) for isolation                      | default workspace |
| `model`               | string | `haiku`, `sonnet`, `opus`, or full model name                            | account default |
| `system_prompt`       | string | Replace the default system prompt entirely                               | _(none)_        |
| `append_system_prompt`| string | Append to the default system prompt without replacing it                 | _(none)_        |
| `json_schema`         | string | JSON Schema string — Claude returns JSON matching this schema            | _(none)_        |
| `effort`              | string | Reasoning effort: `low`, `medium`, `high`, `max`                        | _(none)_        |
| `no_continue`         | bool   | Start a fresh session instead of continuing the previous one             | `false`         |
| `resume`              | string | Resume a specific session by session ID                                  | _(none)_        |

### Workspace isolation

Each `workspace` value gets its own directory, file context, and conversation history. A workspace can only run one Claude process at a time — concurrent `claude_run` calls to the same workspace return an error. Use different workspace names for parallel work.

```
# safe: parallel execution in different workspaces
claude_run(prompt="analyze data.csv", workspace="data-analysis")
claude_run(prompt="write tests", workspace="test-gen")

# conflict: both calls hit the same workspace at the same time → one will error
claude_run(prompt="task A", workspace="shared")
claude_run(prompt="task B", workspace="shared")  # 409 if first is still running
```

## claudebox_zai — 5 tools (GLM via z.ai)

Same 5 tools as above, but backed by GLM models through [z.ai](https://z.ai)'s Anthropic-compatible API. Same workspace capabilities, same file operations, different underlying model. Use this when you want agentic execution without touching your Claude subscription or API key budget.

The z.ai instance routes through a separate claudebox container — workspaces between the two instances are not shared.
