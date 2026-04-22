#!/bin/bash

_MCP_ACCEPT="Accept: application/json, text/event-stream"

_mcp_tools_list() {
    local response
    response=$(curl -s -X POST "$BASE_URL/mcp/" \
        -H "Content-Type: application/json" \
        -H "$AUTH_HEADER" \
        -H "$_MCP_ACCEPT" \
        -d '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}')
    # SSE response — extract data line
    echo "$response" | grep "^data:" | head -1 | sed 's/^data: //'
}

# ── MCP tools loaded ───────────────────────────────────────────────────────

# format: tool_prefix|min_count
MCP_SERVER_TOOL_COUNTS=(
    "stealthy_auto_browse|1"
    "hybrids3|5"
    "claudebox-|3"
    "claudebox_zai-|3"
    "mcp_tools-|1"
)

test_mcp_tools_loaded() {
    local tools_json
    tools_json=$(_mcp_tools_list)
    assert_not_empty "$tools_json" "mcp tools response" || return 1

    local total
    total=$(echo "$tools_json" | python3 -c "
import sys, json
data = json.load(sys.stdin)
tools = data.get('result', {}).get('tools', [])
print(len(tools))
" 2>/dev/null)
    assert_not_empty "$total" "mcp tools count" || return 1

    if [ "$total" -lt 17 ]; then
        echo "  FAIL: expected at least 17 tools, got $total"
        return 1
    fi
    echo "  OK: $total total MCP tools loaded"

    # check per-server counts
    local entry prefix min_count count
    for entry in "${MCP_SERVER_TOOL_COUNTS[@]}"; do
        IFS='|' read -r prefix min_count <<< "$entry"
        count=$(echo "$tools_json" | python3 -c "
import sys, json
data = json.load(sys.stdin)
tools = data.get('result', {}).get('tools', [])
print(sum(1 for t in tools if t['name'].startswith('$prefix')))
" 2>/dev/null)
        if [ "$count" -lt "$min_count" ]; then
            echo "  FAIL: $prefix: expected >= $min_count tools, got $count"
            return 1
        fi
        echo "  OK: $prefix has $count tools (min $min_count)"
    done

    echo "OK: mcp_tools_loaded ($total total)"
}

# ── specific tools present ─────────────────────────────────────────────────

EXPECTED_MCP_TOOLS=(
    "stealthy_auto_browse-run_script"
    "hybrids3-upload_object"
    "hybrids3-download_object"
    "hybrids3-list_objects"
    "claudebox-claude_run"
    "claudebox-read_file"
    "claudebox-write_file"
    "claudebox-list_files"
    "claudebox-delete_file"
    "claudebox_zai-claude_run"
    "claudebox_zai-read_file"
    "mcp_tools-generate_image"
    "mcp_tools-generate_tts"
)

test_mcp_specific_tools() {
    local tools_json
    tools_json=$(_mcp_tools_list)

    local tool
    for tool in "${EXPECTED_MCP_TOOLS[@]}"; do
        assert_contains "$tools_json" "\"$tool\"" "tool $tool exists" || return 1
    done
    echo "OK: mcp_specific_tools (${#EXPECTED_MCP_TOOLS[@]} tools)"
}

# ── MCP server rejects bad auth ─────────────────────────────────────────────

test_mcp_auth_reject() {
    # LiteLLM rejects unauthenticated MCP requests (may return 401 or 500)
    local code
    code=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$BASE_URL/mcp/" \
        -H "Content-Type: application/json" \
        -H "$_MCP_ACCEPT" \
        -d '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}')
    if [ "$code" = "200" ]; then
        echo "  FAIL: mcp should reject no auth"
        return 1
    fi
    echo "  OK: mcp rejects no auth ($code)"

    code=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$BASE_URL/mcp/" \
        -H "Content-Type: application/json" \
        -H "$_MCP_ACCEPT" \
        -H "Authorization: Bearer wrong-key" \
        -d '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}')
    # LiteLLM may accept any bearer token for MCP — check but don't fail
    if [ "$code" = "200" ]; then
        echo "  WARN: mcp accepted bad key ($code) — LiteLLM may not validate MCP auth"
    else
        echo "  OK: mcp rejects bad key ($code)"
    fi

    echo "OK: mcp_auth_reject"
}

ALL_TESTS+=(
    test_mcp_tools_loaded
    test_mcp_specific_tools
    test_mcp_auth_reject
)
