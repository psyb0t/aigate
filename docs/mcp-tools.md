# MCP Tool Ecosystem

The [Model Context Protocol](https://modelcontextprotocol.io/) is what makes this gateway more than just an LLM router. Multiple MCP servers can be registered in LiteLLM (all optional, enabled via `.env` flags). Any model that supports tool use (function calling) can invoke these tools during a conversation — the model decides when and how to use them based on the user's request.

This means you can ask a Groq model to browse a website, take a screenshot, upload it to object storage, and return the public URL ��� and it will orchestrate all of that autonomously through MCP tool calls.

## Connecting

The gateway exposes a single aggregated MCP endpoint that proxies every active MCP-capable server (which servers are active depends on which `.env` flags are set — see `active_mcp_servers()` in `litellm/build-config.py`):

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
| pibox-zai            | `http://localhost:4000/pibox-zai/mcp/`              |
| audiolla             | `http://localhost:4000/audiolla/v1/mcp`             |
| audiolla-cuda        | `http://localhost:4000/audiolla-cuda/v1/mcp`        |
| flickies             | `http://localhost:4000/flickies/v1/mcp`             |
| flickies-cuda        | `http://localhost:4000/flickies-cuda/v1/mcp`        |
| telethon             | `http://localhost:4000/telethon/mcp`                |
| predictalot          | `http://localhost:4000/predictalot/mcp`             |
| predictalot-cuda     | `http://localhost:4000/predictalot-cuda/mcp`        |
| mailbox              | `http://localhost:4000/mailbox/mcp`                 |
| mcp_tools            | via LiteLLM aggregation only (no direct nginx route)|

```bash
# list all available MCP tools
curl -X POST http://localhost:4000/mcp/ \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}'
```

## stealthy_auto_browse (`BROWSER=1`)

Stealth browser automation. All interactions are undetectable by bot detection systems (passes Cloudflare, CreepJS, BrowserScan, Pixelscan).

### run_script

Execute a multi-step browser automation script. Takes a `steps` array where each step is a browser action. All steps execute sequentially on the same replica in a single round-trip — no LiteLLM overhead between steps.

Available actions (each is one step within `run_script`):

| Action                     | Description                                                              |
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

### Usage notes

- Browser sessions are sticky — each MCP session is pinned to one replica by `Mcp-Session-Id` header. Maintain session continuity across tool calls within a conversation.
- `system_click` / `system_type` use OS-level input simulation (PyAutoGUI) — completely undetectable, as they bypass CDP entirely.
- For page parsing, `get_interactive_elements` returns coordinates alongside element metadata, so you can click by coordinates instead of guessing CSS selectors.
- The same actions are also available individually via the browser REST API at `/stealthy-auto-browse/` — see [the browser service page](services/browser.md) for REST API examples.

## hybrids3 (`HYBRIDS3=1`)

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

## claudebox (`CLAUDEBOX=1`)

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

## pibox_zai (`PIBOX_ZAI=1`)

[pi-coding-agent](https://github.com/earendil-works/pi-mono) wrapped by [pibox](https://github.com/psyb0t/docker-pibox) and pointed at [z.ai](https://z.ai)'s Anthropic-compatible API (GLM models). Same agentic capabilities and workspace-scoped file operations as `claudebox`, plus a `/files/*` CRUD API. Use this when you want agentic execution without touching your Claude subscription or API key budget.

The pibox-zai instance runs in a separate container — workspaces are not shared with claudebox.

## mcp_tools (auto-enabled with image/TTS/search providers)

Media generation and web search tools. Auto-enabled when any image, TTS, or search provider is active (HuggingFace, OpenAI, talkies, SDCPP, SearXNG). Discovers available models dynamically from LiteLLM at startup — tool descriptions include the list of available models and defaults. Auth via `MCP_TOOLS_AUTH_TOKEN`.

Image and TTS tools return structured JSON with all parameters used and a persistent URL to the result file (uploaded to HybridS3). No base64 blobs are sent to the LLM.

| Tool             | Description                                                                                                  |
| ---------------- | ------------------------------------------------------------------------------------------------------------ |
| `generate_image` | Generate an image from a text prompt. Returns JSON with `prompt`, `model`, `size`, and `url` (or `urls` + `revised_prompt` for OpenAI models). |
| `generate_tts`   | Generate speech audio from text. Returns JSON with `text`, `model`, `voice`, `speed`, and `url`.             |
| `search_web`     | Search the web via SearXNG (aggregates Google, Bing, DuckDuckGo, Wikipedia). Returns JSON with a `results` array of `title`, `url`, `snippet`, `engine`. Only available when `SEARXNG=1`. |

### generate_image parameters

| Parameter | Type   | Description                                          | Default                                |
| --------- | ------ | ---------------------------------------------------- | -------------------------------------- |
| `prompt`  | string | Text description of the image to generate            | _(required)_                           |
| `model`   | string | Which image model to use (listed in tool description)| first available (prefers hf-flux-schnell) |
| `size`    | string | Image dimensions (e.g. `1024x1024`)                  | `1024x1024`                            |

### generate_tts parameters

| Parameter | Type   | Description                                          | Default                                         |
| --------- | ------ | ---------------------------------------------------- | ----------------------------------------------- |
| `text`    | string | Text to convert to speech                            | _(required)_                                    |
| `model`   | string | Which TTS model to use (listed in tool description)  | first available (prefers local-talkies-cuda-kokoro-tts, then local-talkies-kokoro-tts) |
| `voice`   | string | Voice to use                                         | `af_heart`                                      |
| `speed`   | number | Speech speed multiplier                              | `1.0`                                           |

### search_web parameters

| Parameter     | Type   | Description                                          | Default |
| ------------- | ------ | ---------------------------------------------------- | ------- |
| `query`       | string | Search query                                         | _(required)_ |
| `num_results` | int    | Maximum number of results to return                  | `10`    |

### Error handling

If an invalid model is requested, the tool returns an error JSON with the list of available models:

```json
{"error": "Model 'nonexistent' not available", "available_models": ["hf-flux-schnell"]}
```

---

## telethon — Telegram client (`TELETHON=1`)

MCP server backed by [docker-telethon-plus](https://github.com/psyb0t/docker-telethon-plus). Gives any function-calling model full Telegram client access — read and send messages, manage groups, forward files.

Requires `TELETHON_API_ID`, `TELETHON_API_HASH`, and `TELETHON_SESSION` in `.env`. See [the Telethon service page](services/telethon.md) for setup.

All chat references accept: `@username`, phone number, `t.me/...` link, or numeric ID as a string.

### Tools

| Tool                | Description |
| ------------------- | ----------- |
| `get_me`            | Return the authorized account profile |
| `get_entity`        | Resolve a chat reference to a profile |
| `send_message`      | Send a text message to a chat |
| `get_messages`      | Read recent messages from a chat (newest first) |
| `get_dialogs`       | List your dialogs (chats, groups, channels) |
| `forward_messages`  | Forward one or more messages between chats |
| `delete_messages`   | Delete messages by ID |
| `edit_message`      | Edit a message you sent |
| `mark_read`         | Mark messages in a chat as read |
| `send_file`         | Download a file from an HTTPS URL and send it to a chat |
| `get_participants`  | List members of a group or channel |
| `create_group`      | Create a new supergroup or broadcast channel |
| `delete_chat`       | Delete a supergroup or channel you own |
| `join_chat`         | Join a public channel or supergroup |
| `leave_chat`        | Leave a channel or supergroup |

---

## predictalot — Time-series forecasting (`PREDICTALOT=1` or `PREDICTALOT_CUDA=1`)

MCP server backed by [docker-predictalot](https://github.com/psyb0t/docker-predictalot). Exposes five foundation forecasters across six forecast types: **univariate**, **multivariate**, **covariates_past**, **covariates_future**, **covariates_both**, **samples**. A model only has a tool under a type if it implements that modality (e.g. `timesfm-2.5` only appears under `univariate`; `chronos-2` is the only `covariates_future` member).

> **v1.0.0 surface note.** Upstream v1.0.0 also ships a tabular-ML family (`/v1/tabular/*` — 9 supervised backends + 3 meta-learners) but does NOT register those as MCP tools. The 26-tool catalog below is FM-only. Tabular work goes through direct REST against `/predictalot/v1/tabular/*` (see [the predictalot service page](services/predictalot.md#tabular-ml--train-a-direction-classifier-and-forecast) for the train + forecast shape).

**26 tools total**, in three families:
- `forecast_<type>_<model>` — single-model forecast for a specific (type, model) cell. 18 of these (5+3+2+1+1+2 across types).
- `forecast_<type>_ensemble` — per-type weighted-mean ensemble across all the type's members. 6 of these.
- `list_<type>_models` — per-type listing of member slugs + loaded/unloaded status. 6 of these.

Naming convention: model slug dashes/dots become underscores (`sundial-base-128m` → `sundial_base_128m`, `timesfm-2.5` → `timesfm_2_5`). Each `forecast_<type>_<model>` argument shape mirrors the HTTP body flattened to kwargs:
- quantile types: `context`, `horizon`, `quantile_levels=None`, `context_length=None`, `unload=False` (covariate variants add `past_covariates` and/or `future_covariates`).
- samples type: `context`, `horizon`, `num_samples=None`, `context_length=None`, `unload=False`.
- `forecast_<type>_ensemble`: same as the per-model tool minus `model`, plus `weights: dict[str, float] | None = None`. Weight 0 disables that member; omitted entries default to 1.

See [the predictalot service page](services/predictalot.md) for per-model trade-offs and accuracy benchmarks.

### Tools by forecast type

| Type | Per-model tools | Ensemble | Listing |
|---|---|---|---|
| univariate | `forecast_univariate_chronos_2`, `forecast_univariate_timesfm_2_5`, `forecast_univariate_moirai_2`, `forecast_univariate_toto_1`, `forecast_univariate_sundial_base_128m` | `forecast_univariate_ensemble` | `list_univariate_models` |
| multivariate | `forecast_multivariate_chronos_2`, `forecast_multivariate_moirai_2`, `forecast_multivariate_toto_1` | `forecast_multivariate_ensemble` | `list_multivariate_models` |
| covariates_past | `forecast_covariates_past_chronos_2`, `forecast_covariates_past_moirai_2` | `forecast_covariates_past_ensemble` | `list_covariates_past_models` |
| covariates_future | `forecast_covariates_future_chronos_2` | `forecast_covariates_future_ensemble` | `list_covariates_future_models` |
| covariates_both (past + future) | `forecast_covariates_both_chronos_2` | `forecast_covariates_both_ensemble` | `list_covariates_both_models` |
| samples (raw paths) | `forecast_samples_toto_1`, `forecast_samples_sundial_base_128m` | `forecast_samples_ensemble` | `list_samples_models` |

Via LiteLLM's `/mcp/` aggregator each tool is prefixed `predictalot-` (e.g. `predictalot-forecast_univariate_chronos_2`). Direct calls to `/predictalot/mcp` see the raw, unprefixed names.

### Common args

| Arg               | Type                | Description                                                        | Default            |
| ----------------- | ------------------- | ------------------------------------------------------------------ | ------------------ |
| `context`         | `list[list[float]]` | One inner list per series (single-series = `[[...]]`)              | _(required)_       |
| `horizon`         | int                 | Steps into the future to forecast                                  | _(required)_       |
| `quantile_levels` | `list[float]`       | Subset of `{0.1, 0.2, ..., 0.9}`                                   | `[0.1, 0.5, 0.9]`  |
| `context_length`  | int                 | Max history points to feed the model (per-model defaults differ)   | per-model          |
| `unload`          | bool                | Tear the model down after this call to free RAM/VRAM               | `false`            |

`forecast_ensemble` additionally accepts a `weights: {slug: float}` map — weight `0` disables a model, omitted entries default to `1.0`.

---

## mailbox — IMAP+SMTP gateway (`MAILBOX=1`)

MCP server backed by [docker-mailbox](https://github.com/psyb0t/docker-mailbox). Flat tool set across all configured accounts — every per-account tool takes a `mailbox` argument (name or address). Same bearer/HTTP wire shape, one MCP catalog regardless of how many inboxes are configured.

See [the mailbox service page](services/mailbox.md) for the full setup (config schema, credentials handling, host bind-mount).

### Tools

| Tool             | Description |
| ---------------- | ----------- |
| `mailboxes`      | List configured accounts + their IMAP/SMTP capabilities |
| `inbox`          | Unified inbox across all accounts (or a filtered subset) |
| `list_messages`  | List messages in a specific account/folder |
| `get_message`    | Fetch a single message (headers + body; optional reader mode strips HTML) |
| `search`         | Search a mailbox by header/body terms |
| `send`           | Send a message via the account's SMTP |
| `mark_seen`      | Flag messages as read |
| `mark_unseen`    | Flag messages as unread |
| `move`           | Move messages between folders |
| `delete`         | Delete messages |

### Common args

| Arg          | Type                  | Description                                                          | Default       |
| ------------ | --------------------- | -------------------------------------------------------------------- | ------------- |
| `mailbox`    | `str` or `list[str]`  | Account name (from config) or address. List = multi-account scope    | _(required for per-account tools)_ |
| `folder`    | `str`                 | IMAP folder name                                                     | `INBOX`       |
| `limit`     | int                   | Max messages to return                                               | 50            |
| `unseen`    | bool                  | Only unseen messages                                                 | `false`       |
| `from`      | `str`                 | Filter by sender                                                     | —             |
| `reader`    | bool                  | Strip HTML body to clean text/markdown (html2text)                   | `false`       |

See the [docker-mailbox README](https://github.com/psyb0t/docker-mailbox) for the full per-tool parameter shape, including `send`'s `to`/`cc`/`bcc`/`subject`/`body`/`attachments` and bulk-update semantics.

---

## flickies — Video toolkit (`FLICKIES=1` or `FLICKIES_CUDA=1`)

MCP server backed by [docker-flickies](https://github.com/psyb0t/docker-flickies). Sibling of audiolla (audio) and talkies (speech) — lipsync, face restore, and ffmpeg ops behind one wire format.

**11 tools, three families:**

- **Lipsync** — `lipsync`. Engines: `latentsync-1.5` (Apache-2.0, CUDA-only, ~8 GB VRAM, default), `wav2lip` / `wav2lip-gan` (LRS2 non-commercial, gated on `FLICKIES_ENABLE_NONCOMMERCIAL=1`).
- **Face restore** — `restore`. Engine: `gfpgan` (GFPGAN v1.4, Apache-2.0, CUDA-only). Chains after Wav2Lip to fix the soft 96×96 mouth crop, or stand-alone on any video.
- **ffmpeg ops** (CPU, no GPU needed) — `trim`, `concat`, `transcode` (mp4 / mov / webm / gif + fps + codec change), `scale`, `mux_audio`, `extract_audio`, `thumbnail_grid`.
- **Info** — `info` (ffprobe metadata), `list_engines` (configured engines + load state).

Same JSON-body contract as audiolla — every tool takes a request body; **the only multipart route is `PUT /v1/files/{path}` for staging raw bytes**. Video-producing tools require `output_path` (server stages under `${DATA_DIR_FLICKIES}/files` — fetch via `GET /v1/files/<path>`) XOR `output_url` (server PUTs to a presigned URL). Input is `file_path` (FILES_DIR-relative, after staging) XOR `file_url` (server fetches, subject to `FLICKIES_ALLOW_PRIVATE_FETCH`).

Via LiteLLM's `/mcp/` aggregator each tool is prefixed `flickies-` (e.g. `flickies-lipsync`) on the CPU variant and `flickies_cuda-` on the CUDA variant. Direct calls to `/flickies/v1/mcp/` see the raw, unprefixed names.

Hot-swap eviction: one engine resident at a time per container — different model requested → current model evicted. Idle longer than `FLICKIES_IDLE_UNLOAD_SECS` (default 600) → unloaded by the sweeper.

| Tool             | Description |
| ---------------- | ----------- |
| `list_engines`   | Configured engines + their loaded/unloaded state + license posture |
| `info`           | ffprobe metadata — duration, codec, fps, dimensions, bitrate |
| `lipsync`        | Sync mouth to new audio (LatentSync 1.5 default, Wav2Lip / -GAN behind the noncommercial gate) |
| `restore`        | GFPGAN face restoration — sharpens / de-blurs faces frame-by-frame |
| `transcode`      | Codec / format / fps / bitrate change. Handles gif output. |
| `trim`           | Cut by start_sec / end_sec |
| `concat`         | Concatenate N inputs (re-encode or stream copy) |
| `scale`          | Resize to target W × H |
| `mux_audio`      | Replace or overlay the audio track on a video |
| `extract_audio`  | Strip audio to a standalone file (any codec ffmpeg supports) |
| `thumbnail_grid` | Tiled grid of evenly-spaced thumbnails |

See the [docker-flickies README](https://github.com/psyb0t/docker-flickies) for the full per-tool parameter shape and the canonical `openapi.yaml`.
