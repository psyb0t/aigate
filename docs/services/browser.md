# Browser Cluster (stealthy-auto-browse)

| Endpoint             | URL                                                                 | Auth                         |
| -------------------- | ------------------------------------------------------------------- | ---------------------------- |
| Browser API          | `POST /stealthy-auto-browse/`                                       | optional bearer token        |
| Screenshot (browser) | `GET /stealthy-auto-browse/screenshot/browser`                      | optional bearer token        |
| Screenshot (desktop) | `GET /stealthy-auto-browse/screenshot/desktop`                      | optional bearer token        |
| MCP server           | `POST /stealthy-auto-browse/mcp/`                                   | optional bearer token        |
| Queue health         | `GET /stealthy-auto-browse/__queue/health`                          | none                         |
| Cluster status       | `GET /stealthy-auto-browse/__queue/status`                          | none                         |

Set `STEALTHY_AUTO_BROWSE_AUTH_TOKEN` in `.env` to set the bearer auth token. Defaults to `lulz-4-security` if unset — always change this in production.

### Cluster configuration

- 5 browser replicas by default — set `STEALTHY_AUTO_BROWSE_NUM_REPLICAS` to change
- Each replica defaults to 1 GiB RAM and 2 GiB total RAM plus swap, configured with `SAB_MEM_LIMIT` and `SAB_MEMSWAP_LIMIT`. A 256 MiB RAM cap can stall browser startup and leave the proxy returning 503.
- HAProxy routes requests to replicas and enforces session stickiness:
  - MCP requests: pinned by `Mcp-Session-Id` header
  - All other requests: pinned by `INSTANCEID` cookie, max 1 concurrent request per replica

### Browser API request body

```json
{
  "action": "goto",
  "url": "https://example.com"
}
```

Atomic actions: `goto`, `get_text`, `get_html`, `get_interactive_elements`, `screenshot`, `system_click`, `system_type`, `send_key`, `click`, `fill`, `scroll`, `mouse_move`, `wait_for_element`, `wait_for_text`, `eval_js`, `browser_action`.

`run_script` composes multiple actions into a single request — executes them sequentially on the same replica in a single HTTP round-trip:

```json
{
  "action": "run_script",
  "steps": [
    {"action": "goto", "url": "https://example.com"},
    {"action": "wait_for_element", "selector": "h1", "timeout": 5},
    {"action": "get_text"}
  ]
}
```

---


## Usage

### Browser Automation

The browser cluster can be used directly via the REST API, or indirectly by letting an LLM invoke browser tools through MCP.

### Direct REST API

```bash
# navigate to a page
curl -X POST http://localhost:4000/stealthy-auto-browse/ \
  -H "Authorization: Bearer $STEALTHY_AUTO_BROWSE_AUTH_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"action": "goto", "url": "https://example.com"}'

# get all visible text
curl -X POST http://localhost:4000/stealthy-auto-browse/ \
  -H "Authorization: Bearer $STEALTHY_AUTO_BROWSE_AUTH_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"action": "get_text"}'

# find all interactive elements with their coordinates
curl -X POST http://localhost:4000/stealthy-auto-browse/ \
  -H "Authorization: Bearer $STEALTHY_AUTO_BROWSE_AUTH_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"action": "get_interactive_elements", "visible_only": true}'

# click at coordinates (OS-level, undetectable)
curl -X POST http://localhost:4000/stealthy-auto-browse/ \
  -H "Authorization: Bearer $STEALTHY_AUTO_BROWSE_AUTH_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"action": "system_click", "x": 640, "y": 400}'

# type text (OS-level keyboard input)
curl -X POST http://localhost:4000/stealthy-auto-browse/ \
  -H "Authorization: Bearer $STEALTHY_AUTO_BROWSE_AUTH_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"action": "system_type", "text": "hello world"}'

# screenshot — returns raw PNG (1920x1080 by default, always resize)
curl -H "Authorization: Bearer $STEALTHY_AUTO_BROWSE_AUTH_TOKEN" \
  "http://localhost:4000/stealthy-auto-browse/screenshot/browser?whLargest=512" -o screenshot.png
curl -H "Authorization: Bearer $STEALTHY_AUTO_BROWSE_AUTH_TOKEN" \
  "http://localhost:4000/stealthy-auto-browse/screenshot/browser?width=800" -o screenshot.png

# run a multi-step script atomically (all steps on the same replica, single request)
curl -X POST http://localhost:4000/stealthy-auto-browse/ \
  -H "Authorization: Bearer $STEALTHY_AUTO_BROWSE_AUTH_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "action": "run_script",
    "steps": [
      {"action": "goto", "url": "https://duckduckgo.com"},
      {"action": "system_click", "x": 950, "y": 513},
      {"action": "system_type", "text": "what is groq?"},
      {"action": "send_key", "key": "enter"},
      {"action": "wait_for_element", "selector": "[data-testid='\''result'\'']", "timeout": 10},
      {"action": "get_text"}
    ]
  }'
```

Browser sessions are sticky via the `INSTANCEID` cookie. Use a persistent HTTP client to keep your session on the same replica across requests.

### Python — search, screenshot, upload, summarize

```python
import requests

session = requests.Session()  # sticky via INSTANCEID cookie
BASE = "http://localhost:4000"
SAB_AUTH = {"Authorization": f"Bearer {STEALTHY_AUTO_BROWSE_AUTH_TOKEN}"}

def browser(action, **kwargs):
    r = session.post(f"{BASE}/stealthy-auto-browse/", headers=SAB_AUTH, json={"action": action, **kwargs})
    r.raise_for_status()
    return r.json()["data"]

# navigate and search
browser("goto", url="https://duckduckgo.com")
browser("system_click", x=950, y=513)
browser("system_type", text="what is groq?")
browser("send_key", key="enter")
browser("wait_for_element", selector="[data-testid='result']", timeout=10000)
text = browser("get_text")["text"]

# screenshot and upload
screenshot = session.get(f"{BASE}/stealthy-auto-browse/screenshot/browser", headers=SAB_AUTH).content
requests.put(
    f"{BASE}/storage/uploads/search.png",
    headers={"Authorization": f"Bearer {HYBRIDS3_UPLOADS_KEY}", "Content-Type": "image/png"},
    data=screenshot,
)

# ask an LLM to summarize
r = requests.post(f"{BASE}/chat/completions",
    headers={"Authorization": f"Bearer {LITELLM_MASTER_KEY}", "Content-Type": "application/json"},
    json={"model": "cerebras-gpt-oss-120b", "messages": [
        {"role": "user", "content": f"Summarize these search results:\n\n{text[:8000]}"}
    ]})
print(r.json()["choices"][0]["message"]["content"])
```

---
