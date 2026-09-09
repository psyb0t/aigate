# Claudebox

### Chat (via LiteLLM)

Use claudebox models through the standard LiteLLM chat completions endpoint. Pass workspace via extra headers:

```bash
curl http://localhost:4000/chat/completions \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "claudebox-sonnet",
    "messages": [{"role": "user", "content": "analyze data.csv and summarize it"}],
    "extra_headers": {"X-Claude-Workspace": "myproject"}
  }'
```

Available models: `claudebox-haiku`, `claudebox-sonnet`, `claudebox-opus`, `pibox-zai-glm-5.3`, `pibox-zai-glm-5.3-flash`

### Direct API endpoints

Base URLs: `http://localhost:4000/claudebox/` (Claude Code via OAuth/API key) and `http://localhost:4000/pibox-zai/` (pi-coding-agent via z.ai/GLM).

`claudebox/*` requires `Authorization: Bearer $CLAUDEBOX_API_TOKEN`. `pibox-zai/*` requires `Authorization: Bearer $PIBOX_ZAI_API_TOKEN`. Health endpoints are open. Pibox uses `/healthz` (not `/health`); the rest of the path shape (`/run`, `/run/{id}`, `/v1/chat/completions`, `/mcp`, `/files/{path}`) is the same except `/files/` is workspace-rooted on pibox vs. workspace-prefixed on claudebox.

| Method | Path                                  | Description                                              |
| ------ | ------------------------------------- | -------------------------------------------------------- |
| `GET`  | `/claudebox/health`                   | Health check — no auth required                          |
| `GET`  | `/claudebox/status`                   | Returns which workspaces currently have running Claude processes |
| `POST` | `/claudebox/run`                      | Run a prompt through Claude Code                         |
| `POST` | `/claudebox/run/cancel?workspace=<x>` | Kill the running Claude process in a workspace           |
| `PUT`  | `/claudebox/files/<workspace>/<path>` | Upload a file to a workspace                             |
| `GET`  | `/claudebox/files/<workspace>/<path>` | Download a file from a workspace                         |
| `GET`  | `/claudebox/files/<workspace>`        | List files in a workspace                                |
| `GET`  | `/claudebox/files`                    | List files in the root workspace directory               |
| `DELETE`| `/claudebox/files/<workspace>/<path>`| Delete a file from a workspace                           |

### POST /claudebox/run — request body

| Field                | Type   | Description                                                              | Default         |
| -------------------- | ------ | ------------------------------------------------------------------------ | --------------- |
| `prompt`             | string | The prompt to send to Claude Code                                        | _(required)_    |
| `workspace`          | string | Subpath under `/workspaces` for isolation                                | default workspace |
| `model`              | string | `haiku`, `sonnet`, `opus`, or full model name                            | account default |
| `systemPrompt`       | string | Replace the default system prompt entirely                               | _(none)_        |
| `appendSystemPrompt` | string | Append to the default system prompt without replacing it                 | _(none)_        |
| `jsonSchema`         | string | JSON Schema string — Claude returns JSON matching this schema            | _(none)_        |
| `effort`             | string | Reasoning effort: `low`, `medium`, `high`, `max`                        | _(none)_        |
| `outputFormat`       | string | `json` or `json-verbose` (includes full tool call history)               | `json`          |
| `noContinue`         | bool   | Start a fresh session instead of continuing the previous one             | `false`         |
| `resume`             | string | Resume a specific session by session ID                                  | _(none)_        |
| `fireAndForget`      | bool   | Keep the Claude process running even if the HTTP client disconnects      | `false`         |

Returns **409 Conflict** if the workspace already has a running Claude process.

### Response format (json)

```json
{
  "type": "result",
  "subtype": "success",
  "isError": false,
  "result": "the response text",
  "numTurns": 3,
  "durationMs": 12400,
  "totalCostUsd": 0.049,
  "sessionId": "abc123-...",
  "usage": {
    "inputTokens": 312,
    "outputTokens": 87,
    "cacheReadInputTokens": 1024
  }
}
```

### Response format (json-verbose)

Same as `json` but includes a `turns` array with every tool call, tool result, and assistant message:

```json
{
  "type": "result",
  "subtype": "success",
  "result": "Done. I created data_summary.md with statistics.",
  "turns": [
    {
      "role": "assistant",
      "content": [
        {"type": "tool_use", "id": "toolu_abc", "name": "Bash", "input": {"command": "head data.csv"}}
      ]
    },
    {
      "role": "tool_result",
      "content": [
        {"type": "toolResult", "toolUseId": "toolu_abc", "isError": false, "content": "id,name,value\n1,foo,42\n..."}
      ]
    }
  ],
  "numTurns": 5,
  "totalCostUsd": 0.089,
  "sessionId": "abc123-..."
}
```

### OpenAI-compatible endpoint

Claudebox also speaks OpenAI's `chat/completions` protocol directly. This is what LiteLLM uses internally, but you can also hit it directly:

| Method | Path                               | Description                      |
| ------ | ---------------------------------- | -------------------------------- |
| `GET`  | `/claudebox/openai/v1/models`      | List available models            |
| `POST` | `/claudebox/openai/v1/chat/completions` | Chat completions (streaming + non-streaming) |

Custom headers for workspace control:

| Header                          | Description                                                      |
| ------------------------------- | ---------------------------------------------------------------- |
| `X-Claude-Workspace`            | Workspace subpath to run in                                      |
| `X-Claude-Continue`             | Set to `1`, `true`, or `yes` to continue the previous session    |
| `X-Claude-Append-System-Prompt` | Text to append to the system prompt for this request             |

Note: `temperature`, `max_tokens`, `tools`, and other standard OpenAI fields are accepted but silently ignored — Claude Code manages these internally.

### MCP server

Claudebox exposes an MCP server at `/claudebox/mcp/`. Tools: `claude_run`, `read_file`, `write_file`, `list_files`, `delete_file`. See [mcp-tools.md](../mcp-tools.md) for full parameter reference.

### Workspace isolation

Each workspace subpath gets its own directory, file context, and conversation history. Only one Claude process can run per workspace at a time — concurrent requests return 409. Use different workspace names for parallel work:

```bash
# these run concurrently without conflicting
curl -X POST http://localhost:4000/claudebox/run \
  -H "Authorization: Bearer $CLAUDEBOX_API_TOKEN" \
  -d '{"prompt": "write a Go HTTP server", "workspace": "go-project"}'

curl -X POST http://localhost:4000/claudebox/run \
  -H "Authorization: Bearer $CLAUDEBOX_API_TOKEN" \
  -d '{"prompt": "write pytest tests", "workspace": "py-tests"}'
```

---


## Usage

### Agentic coding — Claudebox + Pibox-zai

Two agentic services wrap a coding agent in a Docker container and expose it as an API. Each request runs the agent's full loop — read/write files, run shell commands, install packages, browse the web, use tools, all within an isolated workspace.

- **[Claudebox](https://github.com/psyb0t/docker-claudebox)** — Claude Code, OAuth token or Anthropic API key. Models: `claudebox-haiku`, `claudebox-sonnet`, `claudebox-opus`.
- **[Pibox-zai](https://github.com/psyb0t/docker-pibox)** — [pi-coding-agent](https://github.com/earendil-works/pi-mono) on a GLM Coding Plan. Models: `pibox-zai-glm-5.3`, `pibox-zai-glm-5.3-flash`. Adds `/files/*` CRUD plus optional Telegram + cron modes.

Both speak the Anthropic wire protocol and expose the same shape of API (sync + async `/run`, OpenAI-compatible `/v1/chat/completions`, MCP server).

### Via LiteLLM chat completions

The simplest way — just use claudebox models in the standard chat API:

```bash
curl http://localhost:4000/chat/completions \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "claudebox-sonnet",
    "messages": [{"role": "user", "content": "list all Python files in this workspace"}],
    "extra_headers": {"X-Claude-Workspace": "myproject"}
  }'
```

### Via direct API

More control: structured output formats, session resumption, fire-and-forget, tool call history.

```bash
# basic run
curl -X POST http://localhost:4000/claudebox/run \
  -H "Authorization: Bearer $CLAUDEBOX_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"prompt": "write a Go HTTP server", "workspace": "go-project"}'

# with structured JSON output
curl -X POST http://localhost:4000/claudebox/run \
  -H "Authorization: Bearer $CLAUDEBOX_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "prompt": "extract the name and version from package.json",
    "workspace": "myproject",
    "jsonSchema": "{\"type\":\"object\",\"properties\":{\"name\":{\"type\":\"string\"},\"version\":{\"type\":\"string\"}},\"required\":[\"name\",\"version\"]}"
  }'

# with full tool call history
curl -X POST http://localhost:4000/claudebox/run \
  -H "Authorization: Bearer $CLAUDEBOX_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"prompt": "build the project and run tests", "workspace": "myapp", "outputFormat": "json-verbose"}'

# check which workspaces are busy
curl http://localhost:4000/claudebox/status \
  -H "Authorization: Bearer $CLAUDEBOX_API_TOKEN"

# cancel a running task
curl -X POST "http://localhost:4000/claudebox/run/cancel?workspace=myapp" \
  -H "Authorization: Bearer $CLAUDEBOX_API_TOKEN"
```

### File operations

```bash
# upload a file to a workspace
curl -X PUT http://localhost:4000/claudebox/files/myproject/data.csv \
  -H "Authorization: Bearer $CLAUDEBOX_API_TOKEN" \
  --data-binary @data.csv

# list files in a workspace
curl http://localhost:4000/claudebox/files/myproject \
  -H "Authorization: Bearer $CLAUDEBOX_API_TOKEN"

# download a file from a workspace
curl http://localhost:4000/claudebox/files/myproject/results.json \
  -H "Authorization: Bearer $CLAUDEBOX_API_TOKEN" \
  -o results.json

# delete a file
curl -X DELETE http://localhost:4000/claudebox/files/myproject/old.log \
  -H "Authorization: Bearer $CLAUDEBOX_API_TOKEN"
```

### File + task workflow

```bash
# 1. upload input data
curl -X PUT http://localhost:4000/claudebox/files/analysis/sales.csv \
  -H "Authorization: Bearer $CLAUDEBOX_API_TOKEN" \
  --data-binary @sales.csv

# 2. run analysis (Claude reads the file, writes a report)
curl -X POST http://localhost:4000/claudebox/run \
  -H "Authorization: Bearer $CLAUDEBOX_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"prompt": "analyze sales.csv, compute monthly totals and trends, write a report to report.md", "workspace": "analysis"}'

# 3. download the report
curl http://localhost:4000/claudebox/files/analysis/report.md \
  -H "Authorization: Bearer $CLAUDEBOX_API_TOKEN"
```

### Always-active skills

Drop a `SKILL.md` file into a named subdirectory under `.data/claudebox/config/.always-skills/` — it will be injected into the system prompt of every Claude invocation automatically. No restarts needed. Applies to API, MCP, chat, everything.

```
.data/claudebox/config/.always-skills/
└── coding-rules/
    └── SKILL.md   ← injected into every session
```

Example `SKILL.md`:

```markdown
When writing Go code, always use slog for structured logging, never fmt.Println.
When writing Python, always use pathlib for file paths, never os.path.
Always write tests alongside implementations.
```

Skills stack — every `SKILL.md` found is appended in alphabetical order by directory name. Per-request `appendSystemPrompt` or `X-Claude-Append-System-Prompt` is appended after always-skills, so per-request instructions take precedence.

---

