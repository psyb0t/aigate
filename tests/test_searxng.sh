#!/bin/bash

_MCP_ACCEPT="Accept: application/json, text/event-stream"

_has_searxng() {
    [ "${SEARXNG:-}" = "1" ]
}

# ── SearXNG health ────────────────────────────────────────────────────────────

test_searxng_health() {
    if ! _has_searxng; then
        echo "  SKIP: SEARXNG not enabled"
        echo "OK: searxng_health (skipped)"
        return 0
    fi

    assert_http_code "$BASE_URL/searxng/" "200" "searxng UI reachable" \
        -u "$(echo "$LITELLM_UI_BASIC_AUTH" | cut -d: -f1):$(echo "$LITELLM_UI_BASIC_AUTH" | cut -d: -f2-)" \
        || return 1

    echo "OK: searxng_health"
}

# ── search_web tool present in MCP ────────────────────────────────────────────

test_searxng_mcp_tool_present() {
    if ! _has_searxng; then
        echo "  SKIP: SEARXNG not enabled"
        echo "OK: searxng_mcp_tool_present (skipped)"
        return 0
    fi

    local tools_json
    tools_json=$(_mcp_tools_list)
    assert_not_empty "$tools_json" "mcp tools response" || return 1
    assert_contains "$tools_json" '"mcp_tools-search_web"' \
        "search_web tool present (SEARXNG=1)" || return 1

    echo "OK: searxng_mcp_tool_present"
}

# ── search_web tool absent when SEARXNG disabled ──────────────────────────────

test_searxng_mcp_tool_absent_when_disabled() {
    if _has_searxng; then
        echo "  SKIP: SEARXNG is enabled — can't test absence"
        echo "OK: searxng_mcp_tool_absent_when_disabled (skipped)"
        return 0
    fi

    local tools_json
    tools_json=$(_mcp_tools_list)
    assert_not_empty "$tools_json" "mcp tools response" || return 1
    assert_not_contains "$tools_json" '"mcp_tools-search_web"' \
        "search_web tool absent (SEARXNG not enabled)" || return 1

    echo "OK: searxng_mcp_tool_absent_when_disabled"
}

# ── search_web returns results ────────────────────────────────────────────────

test_searxng_search_web_returns_results() {
    if ! _has_searxng; then
        echo "  SKIP: SEARXNG not enabled"
        echo "OK: searxng_search_web_returns_results (skipped)"
        return 0
    fi

    local response
    response=$(curl -s -X POST "$BASE_URL/mcp/" \
        -H "Content-Type: application/json" \
        -H "$AUTH_HEADER" \
        -H "$_MCP_ACCEPT" \
        -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"mcp_tools-search_web","arguments":{"query":"python programming language","num_results":3}}}')
    assert_not_empty "$response" "got MCP response" || return 1

    local data
    data=$(echo "$response" | grep "^data:" | head -1 | sed 's/^data: //')
    assert_not_empty "$data" "got data line" || return 1

    local valid
    valid=$(echo "$data" | python3 -c "
import sys, json
data = json.load(sys.stdin)
content = data.get('result', {}).get('content', [])
for c in content:
    if c.get('type') != 'text':
        continue
    inner = json.loads(c['text'])
    results = inner.get('results', [])
    if results and inner.get('query') == 'python programming language':
        r = results[0]
        if r.get('title') and r.get('url') and 'snippet' in r:
            print('yes')
            sys.exit()
print('no')
" 2>/dev/null)
    assert_eq "$valid" "yes" \
        "response has query + results with title/url/snippet" || return 1

    echo "OK: searxng_search_web_returns_results"
}

# ── search_web num_results limit honored ──────────────────────────────────────

test_searxng_search_web_num_results() {
    if ! _has_searxng; then
        echo "  SKIP: SEARXNG not enabled"
        echo "OK: searxng_search_web_num_results (skipped)"
        return 0
    fi

    local response
    response=$(curl -s -X POST "$BASE_URL/mcp/" \
        -H "Content-Type: application/json" \
        -H "$AUTH_HEADER" \
        -H "$_MCP_ACCEPT" \
        -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"mcp_tools-search_web","arguments":{"query":"openai","num_results":2}}}')

    local data
    data=$(echo "$response" | grep "^data:" | head -1 | sed 's/^data: //')
    assert_not_empty "$data" "got data line" || return 1

    local count
    count=$(echo "$data" | python3 -c "
import sys, json
data = json.load(sys.stdin)
content = data.get('result', {}).get('content', [])
for c in content:
    if c.get('type') == 'text':
        inner = json.loads(c['text'])
        print(len(inner.get('results', [])))
        sys.exit()
print(0)
" 2>/dev/null)
    local ok
    [ "$count" -le 2 ] && ok="yes" || ok="no"
    assert_eq "$ok" "yes" "num_results=2 returns at most 2 results (got $count)" || return 1

    echo "OK: searxng_search_web_num_results"
}

ALL_TESTS+=(
    test_searxng_health
    test_searxng_mcp_tool_present
    test_searxng_mcp_tool_absent_when_disabled
    test_searxng_search_web_returns_results
    test_searxng_search_web_num_results
)
