# MCP Tool Ecosystem

The [Model Context Protocol](https://modelcontextprotocol.io/) is what makes this gateway more than just an LLM router. Four MCP servers are registered in LiteLLM, exposing a total of 34 tools. Any model that supports tool use (function calling) can invoke these tools during a conversation — the model decides when and how to use them based on the user's request.

This means you can ask a Groq model to browse a website, take a screenshot, upload it to object storage, and return the public URL — and it will orchestrate all of that autonomously through MCP tool calls.

MCP server endpoint: `POST http://localhost:4000/mcp/` (requires `Authorization: Bearer $LITELLM_MASTER_KEY`)

```bash
# List all available MCP tools
curl -X POST http://localhost:4000/mcp/ \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}'
```

## stealthy_auto_browse — 17 tools

Stealth browser automation. Navigate pages, interact with elements using real mouse/keyboard input, extract content, and take screenshots. All interactions are undetectable by bot detection systems.

| Tool                       | Description                                                             |
| -------------------------- | ----------------------------------------------------------------------- |
| `goto`                     | Navigate to a URL                                                       |
| `get_text`                 | Extract all visible text from the current page (up to 10,000 chars)     |
| `get_html`                 | Get the full HTML source of the current page                            |
| `get_interactive_elements` | Find all clickable/interactive elements with their viewport coordinates |
| `screenshot`               | Capture the browser viewport or full desktop as PNG                     |
| `system_click`             | Click at specific viewport coordinates using OS-level mouse input       |
| `system_type`              | Type text using OS-level keyboard input                                 |
| `send_key`                 | Send a keyboard key (enter, tab, escape, etc.)                          |
| `click`                    | Click a CSS selector                                                    |
| `fill`                     | Fill a form field by CSS selector                                       |
| `scroll`                   | Scroll the page                                                         |
| `mouse_move`               | Move the mouse to specific coordinates                                  |
| `wait_for_element`         | Wait for a CSS selector to appear on the page                           |
| `wait_for_text`            | Wait for specific text to appear on the page                            |
| `eval_js`                  | Execute JavaScript in the browser context                               |
| `browser_action`           | Perform browser-level actions (back, forward, refresh)                  |
| `run_script`               | Execute a multi-step automation script atomically                       |

## hybrids3 — 7 tools

Object storage operations. Upload, download, list, and manage files in storage buckets. The `uploads` bucket is public-read, so uploaded files are immediately accessible via direct URL.

| Tool              | Description                                          |
| ----------------- | ---------------------------------------------------- |
| `upload_object`   | Upload a file to a bucket                            |
| `download_object` | Download a file from a bucket                        |
| `delete_object`   | Delete a file from a bucket                          |
| `list_objects`    | List all files in a bucket                           |
| `list_buckets`    | List all available buckets                           |
| `object_info`     | Get metadata (size, content type, expiry) for a file |
| `presign_url`     | Generate a pre-signed URL for time-limited access    |

## claudebox — 5 tools (OAuth or API key)

Agentic Claude Code backed by your Claude subscription or Anthropic API key. Each tool call runs through Claude Code's full agentic loop with shell access, file I/O, and tool use within an isolated workspace.

| Tool          | Description                                          |
| ------------- | ---------------------------------------------------- |
| `claude_run`  | Run a prompt through Claude Code's full agentic loop |
| `read_file`   | Read a file from the workspace                       |
| `write_file`  | Write a file to the workspace                        |
| `list_files`  | List files in the workspace                          |
| `delete_file` | Delete a file from the workspace                     |

## claudebox_zai — 5 tools (GLM via z.ai)

Same 5 tools as above, but backed by GLM models through [z.ai](https://z.ai)'s Anthropic-compatible API. Same workspace capabilities, different underlying model.
