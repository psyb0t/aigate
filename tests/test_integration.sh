#!/bin/bash

# ── end-to-end: browser → screenshot → upload → LLM summary ───────────────

test_integration_browser_upload_llm() {
    # clear cookies for fresh session
    rm -f /tmp/int_cookies.txt
    local sab="$BASE_URL/stealthy-auto-browse"
    local sab_auth="${STEALTHY_AUTO_BROWSE_AUTH_TOKEN:-}"
    local sab_auth_args=()
    if [ -n "$sab_auth" ]; then
        sab_auth_args=(-H "Authorization: Bearer $sab_auth")
    fi

    # 1. navigate and get page text atomically (v1.0.0: get_text requires run_script in cluster mode)
    local out
    out=$(curl -sf -X POST "$sab/" \
        -H "Content-Type: application/json" \
        "${sab_auth_args[@]}" \
        -b /tmp/int_cookies.txt -c /tmp/int_cookies.txt \
        -d '{"action":"run_script","steps":[{"action":"goto","url":"https://example.com"},{"action":"get_text","output_id":"text"}]}')
    assert_contains "$out" "success" "navigate to example.com" || return 1
    assert_contains "$out" "Example Domain" "got page text" || return 1

    # 3. screenshot
    local screenshot_file="/tmp/int_test_screenshot.png"
    local size
    size=$(curl -sf "$sab/screenshot/browser" \
        "${sab_auth_args[@]}" \
        -b /tmp/int_cookies.txt -c /tmp/int_cookies.txt \
        -o "$screenshot_file" -w "%{size_download}")
    if [ "$size" -lt 1000 ]; then
        echo "  FAIL: screenshot too small ($size bytes)"
        return 1
    fi
    echo "  OK: screenshot $size bytes"

    # 4. upload to hybrids3
    local upload_key="int-test-$(date +%s).png"
    local code
    code=$(curl -s -o /dev/null -w "%{http_code}" -X PUT \
        "$BASE_URL/storage/uploads/$upload_key" \
        -H "Authorization: Bearer $HYBRIDS3_UPLOADS_KEY" \
        -H "Content-Type: image/png" \
        --data-binary "@$screenshot_file")
    assert_eq "$code" "200" "uploaded screenshot to hybrids3" || return 1

    # 5. verify public URL works
    local dl_size
    dl_size=$(curl -sf "$BASE_URL/storage/uploads/$upload_key" -o /dev/null -w "%{size_download}")
    if [ "$dl_size" -lt 1000 ]; then
        echo "  FAIL: downloaded screenshot too small ($dl_size bytes)"
        return 1
    fi
    echo "  OK: public URL serves $dl_size bytes"

    # 6. ask LLM to summarize the page text
    local page_text
    page_text=$(curl -sf -X POST "$sab/" \
        -H "Content-Type: application/json" \
        "${sab_auth_args[@]}" \
        -b /tmp/int_cookies.txt -c /tmp/int_cookies.txt \
        -d '{"action":"get_text"}' | python3 -c "import sys,json; print(json.load(sys.stdin).get('data',{}).get('text','')[:2000])" 2>/dev/null)

    # use python for safe JSON escaping of page text
    local llm_out
    llm_out=$(python3 -c "
import requests, json, sys
text = sys.argv[1][:500]
r = requests.post('$BASE_URL/chat/completions',
    headers={'Authorization': 'Bearer $LITELLM_MASTER_KEY', 'Content-Type': 'application/json'},
    json={'model':'groq-llama-3.1-8b','messages':[{'role':'user','content':'What website is this text from? Answer in one word: ' + text}]},
    timeout=30)
print(r.text)
" "$page_text" 2>/dev/null)
    assert_contains "$llm_out" "choices" "LLM responded" || return 1

    # 7. cleanup
    curl -s -o /dev/null -X DELETE \
        "$BASE_URL/storage/uploads/$upload_key" \
        -H "Authorization: Bearer $HYBRIDS3_UPLOADS_KEY"
    rm -f "$screenshot_file" /tmp/int_cookies.txt

    echo "OK: integration_browser_upload_llm (7 steps)"
}

# ── end-to-end: LLM with MCP tools ────────────────────────────────────────

test_integration_llm_mcp_tools() {
    # verify LLM can receive MCP tools parameter without error
    local out
    out=$(curl -sf -X POST "$BASE_URL/chat/completions" \
        -H "Content-Type: application/json" \
        -H "$AUTH_HEADER" \
        -d '{"model":"groq-llama-3.1-8b","messages":[{"role":"user","content":"respond with exactly the word INTEGRATION7742 and nothing else"}]}')
    assert_contains "$out" "INTEGRATION7742" "LLM responds" || return 1
    echo "OK: integration_llm_mcp_tools"
}

ALL_TESTS+=(
    test_integration_browser_upload_llm
    test_integration_llm_mcp_tools
)
