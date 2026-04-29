#!/bin/bash

_MCP_ACCEPT="Accept: application/json, text/event-stream"

_has_telethon() {
    [ "${TELETHON:-}" = "1" ]
}

_telethon_call() {
    local tool_name="$1" args_json="$2"
    local response
    response=$(curl -s -X POST "$BASE_URL/mcp/" \
        -H "Content-Type: application/json" \
        -H "$AUTH_HEADER" \
        -H "$_MCP_ACCEPT" \
        -d "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"telethon-$tool_name\",\"arguments\":$args_json}}")
    echo "$response" | grep "^data:" | head -1 | sed 's/^data: //'
}

# ── health ────────────────────────────────────────────────────────────────────

test_telethon_health() {
    if ! _has_telethon; then
        echo "  SKIP: TELETHON not enabled"
        echo "OK: telethon_health (skipped)"
        return 0
    fi

    local me_data
    me_data=$(_telethon_call "get_me" '{}')
    assert_not_empty "$me_data" "telethon get_me response" || return 1

    local authorized
    authorized=$(echo "$me_data" | python3 -c "
import sys, json
data = json.load(sys.stdin)
content = data.get('result', {}).get('content', [])
for c in content:
    if c.get('type') == 'text':
        inner = json.loads(c['text'])
        if inner.get('id'):
            print('yes')
            sys.exit()
print('no')
" 2>/dev/null)
    assert_eq "$authorized" "yes" "telethon authorized and returns own profile" || return 1

    echo "OK: telethon_health"
}

# ── MCP tools present ─────────────────────────────────────────────────────────

test_telethon_mcp_tools_present() {
    if ! _has_telethon; then
        echo "  SKIP: TELETHON not enabled"
        echo "OK: telethon_mcp_tools_present (skipped)"
        return 0
    fi

    local tools_json
    tools_json=$(curl -s -X POST "$BASE_URL/mcp/" \
        -H "Content-Type: application/json" \
        -H "$AUTH_HEADER" \
        -H "$_MCP_ACCEPT" \
        -d '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}' \
        | grep "^data:" | head -1 | sed 's/^data: //')
    assert_not_empty "$tools_json" "mcp tools response" || return 1

    local count
    count=$(echo "$tools_json" | python3 -c "
import sys, json
data = json.load(sys.stdin)
tools = data.get('result', {}).get('tools', [])
print(sum(1 for t in tools if t['name'].startswith('telethon-')))
" 2>/dev/null)
    if [ "${count:-0}" -lt 10 ]; then
        echo "  FAIL: expected >= 10 telethon tools, got ${count:-0}"
        return 1
    fi
    echo "  OK: $count telethon MCP tools present"

    echo "OK: telethon_mcp_tools_present"
}

# ── LLM sends to self, we verify, LLM deletes ────────────────────────────────

test_telethon_llm_send_verify_delete() {
    if ! _has_telethon; then
        echo "  SKIP: TELETHON not enabled"
        echo "OK: telethon_llm_send_verify_delete (skipped)"
        return 0
    fi

    local marker
    marker="aigate-test-$(date +%s)"

    local result
    result=$(python3 - "$BASE_URL" "$LITELLM_MASTER_KEY" "$marker" <<'PYEOF'
import sys, json, requests

base_url, auth_key, marker = sys.argv[1], sys.argv[2], sys.argv[3]
headers = {"Authorization": f"Bearer {auth_key}", "Content-Type": "application/json"}
mcp_accept = "application/json, text/event-stream"

def mcp_call(tool_name, arguments):
    r = requests.post(f"{base_url}/mcp/", headers={**headers, "Accept": mcp_accept},
        json={"jsonrpc": "2.0", "id": 1, "method": "tools/call",
              "params": {"name": tool_name, "arguments": arguments}}, timeout=30)
    for line in r.text.splitlines():
        if line.startswith("data: "):
            return json.loads(line[6:])
    return {}

def mcp_content_text(data):
    parts = []
    for c in data.get("result", {}).get("content", []):
        if c.get("type") == "text":
            parts.append(c["text"])
    return "\n".join(parts)

# fetch telethon tools from MCP
r = requests.post(f"{base_url}/mcp/", headers={**headers, "Accept": mcp_accept},
    json={"jsonrpc": "2.0", "id": 1, "method": "tools/list", "params": {}}, timeout=15)
tools_data = {}
for line in r.text.splitlines():
    if line.startswith("data: "):
        tools_data = json.loads(line[6:])
        break

all_tools = tools_data.get("result", {}).get("tools", [])
# only pass the tools we need to keep the context small
needed = {"telethon-get_me", "telethon-send_message", "telethon-get_messages", "telethon-delete_messages"}
tools = [{"type": "function", "function": {
    "name": t["name"],
    "description": t.get("description", ""),
    "parameters": t.get("inputSchema", {"type": "object", "properties": {}})
}} for t in all_tools if t["name"] in needed]

if not tools:
    print("FAIL: no telethon tools found in MCP")
    sys.exit(1)

messages = [{"role": "user", "content":
    f"Use the Telegram tools to: "
    f"1. Get your own user ID with get_me. "
    f"2. Send the message '{marker}' to yourself (your own user ID = Saved Messages). "
    f"3. Read back your last 5 messages with get_messages to confirm the message is there. "
    f"4. Delete the message you just sent using delete_messages. "
    f"Do all steps. When done, say DONE."}]

# agentic loop — max 10 turns
for turn in range(10):
    r = requests.post(f"{base_url}/v1/chat/completions", headers=headers,
        json={"model": "groq-llama-3.3-70b", "messages": messages,
              "tools": tools, "tool_choice": "auto"}, timeout=60)
    resp = r.json()
    if "error" in resp:
        print(f"FAIL: LLM error: {resp['error']}")
        sys.exit(1)

    msg = resp["choices"][0]["message"]
    messages.append(msg)

    tool_calls = msg.get("tool_calls") or []
    if not tool_calls:
        content = msg.get("content", "")
        if "DONE" in content.upper():
            print(f"OK: LLM completed task: {content[:200]}")
        else:
            print(f"OK: LLM response: {content[:200]}")
        break

    # execute tool calls and feed results back
    for tc in tool_calls:
        fn = tc["function"]
        tool_name = fn["name"]
        args = json.loads(fn.get("arguments", "{}"))
        print(f"  TOOL: {tool_name}({json.dumps(args)})", flush=True)
        result_data = mcp_call(tool_name, args)
        tool_result = mcp_content_text(result_data)
        messages.append({"role": "tool", "tool_call_id": tc["id"], "content": tool_result})

print("SUCCESS")
PYEOF
    )

    echo "$result" | while IFS= read -r line; do echo "  $line"; done

    if echo "$result" | grep -q "^FAIL:"; then
        echo "FAIL: $(echo "$result" | grep '^FAIL:')"
        return 1
    fi

    if ! echo "$result" | grep -q "SUCCESS"; then
        echo "  FAIL: LLM did not complete the task"
        return 1
    fi

    # verify message was actually deleted — clean up if LLM got the ID wrong
    local my_id msgs_data still_there msg_id_to_del
    my_id=$(_telethon_call "get_me" '{}' | python3 -c "
import sys,json
data=json.load(sys.stdin)
for c in data.get('result',{}).get('content',[]):
    if c.get('type')=='text':
        print(json.loads(c['text']).get('id',''))
        break
" 2>/dev/null)

    msgs_data=$(_telethon_call "get_messages" "{\"chat\":\"$my_id\",\"limit\":10}")
    msg_id_to_del=$(echo "$msgs_data" | python3 -c "
import sys,json
data=json.load(sys.stdin)
marker='$marker'
for c in data.get('result',{}).get('content',[]):
    if c.get('type')!='text': continue
    try:
        msg=json.loads(c['text'])
        if marker in str(msg.get('text','')):
            print(msg.get('id',''))
            sys.exit()
    except Exception: pass
" 2>/dev/null)

    if [ -n "$msg_id_to_del" ]; then
        # LLM failed to delete it — clean up and fail
        _telethon_call "delete_messages" "{\"chat\":\"$my_id\",\"message_ids\":[$msg_id_to_del]}" >/dev/null 2>&1
        echo "  FAIL: message '$marker' still in Saved Messages after LLM claimed to delete it (ID $msg_id_to_del) — cleaned up"
        return 1
    fi

    echo "  OK: message confirmed deleted from Saved Messages"
    echo "OK: telethon_llm_send_verify_delete"
}

ALL_TESTS+=(
    test_telethon_health
    test_telethon_mcp_tools_present
    test_telethon_llm_send_verify_delete
)
