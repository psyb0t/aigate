#!/bin/bash

# ── claudebox: gated on CLAUDEBOX=1 ────────────────────────────────────────

_claudebox_enabled() {
    [ "${CLAUDEBOX:-0}" = "1" ]
}

# ── claudebox chat completion via litellm ──────────────────────────────────

test_claudebox_chat() {
    _claudebox_enabled || { echo "  SKIP: CLAUDEBOX=0"; return 0; }
    local out
    out=$(post "$BASE_URL/chat/completions" \
        '{"model":"claudebox-haiku","messages":[{"role":"system","content":"You are a test echo bot. Reply with exactly what is asked, no commentary."},{"role":"user","content":"Reply with exactly: CBOXPONG7742"}]}')
    # claudebox returns 200 with auth error in content when OAuth token is bad
    if echo "$out" | grep -qi "authentication_error\|Failed to authenticate"; then
        echo "  FAIL: claudebox OAuth token rejected by Anthropic — refresh with: claude setup-token"
        return 1
    fi
    assert_contains "$out" "CBOXPONG7742" "claudebox-haiku responds" || return 1
    assert_contains "$out" "choices" "response has choices" || return 1
    echo "OK: claudebox_chat"
}

# ── claudebox direct API via nginx ─────────────────────────────────────────

# format: label|path|expected_in_body
CLAUDEBOX_DIRECT_CASES=(
    "health|/claudebox/healthz|ok"
    "status|/claudebox/status|busyWorkspaces"
)

test_claudebox_direct_api() {
    _claudebox_enabled || { echo "  SKIP: CLAUDEBOX=0"; return 0; }
    local entry label path expected
    for entry in "${CLAUDEBOX_DIRECT_CASES[@]}"; do
        IFS='|' read -r label path expected <<< "$entry"
        local out
        out=$(curl -sf "$BASE_URL$path" \
            -H "Authorization: Bearer $CLAUDEBOX_API_TOKEN" 2>/dev/null)
        assert_contains "$out" "$expected" "claudebox direct: $label" || return 1
    done
    echo "OK: claudebox_direct_api (${#CLAUDEBOX_DIRECT_CASES[@]} cases)"
}

# ── claudebox file operations via nginx ────────────────────────────────────

test_claudebox_file_ops() {
    _claudebox_enabled || { echo "  SKIP: CLAUDEBOX=0"; return 0; }
    local test_file="litellm-test-$(date +%s).txt"
    local test_content="test from litellm tests"

    local code
    code=$(curl -s -o /dev/null -w "%{http_code}" -X PUT \
        "$BASE_URL/claudebox/files/$test_file" \
        -H "Authorization: Bearer $CLAUDEBOX_API_TOKEN" \
        -d "$test_content")
    assert_eq "$code" "200" "upload file to claudebox" || return 1

    local body
    body=$(curl -sf "$BASE_URL/claudebox/files/$test_file" \
        -H "Authorization: Bearer $CLAUDEBOX_API_TOKEN")
    assert_eq "$body" "$test_content" "download file from claudebox" || return 1

    local list_out
    list_out=$(curl -sf "$BASE_URL/claudebox/files" \
        -H "Authorization: Bearer $CLAUDEBOX_API_TOKEN")
    assert_contains "$list_out" "$test_file" "file in listing" || return 1

    code=$(curl -s -o /dev/null -w "%{http_code}" -X DELETE \
        "$BASE_URL/claudebox/files/$test_file" \
        -H "Authorization: Bearer $CLAUDEBOX_API_TOKEN")
    assert_eq "$code" "200" "delete file from claudebox" || return 1

    echo "OK: claudebox_file_ops (4 operations)"
}

# ── OpenAI-compatible models endpoint ─────────────────────────────────────

test_claudebox_openai_models() {
    _claudebox_enabled || { echo "  SKIP: CLAUDEBOX=0"; return 0; }
    local out
    out=$(curl -sf "$BASE_URL/claudebox/openai/v1/models" \
        -H "Authorization: Bearer $CLAUDEBOX_API_TOKEN" 2>/dev/null)
    assert_contains "$out" '"object":"list"' "claudebox openai models returns list" || return 1
    assert_contains "$out" '"haiku"' "claudebox openai models has haiku" || return 1
    assert_contains "$out" '"sonnet"' "claudebox openai models has sonnet" || return 1
    assert_contains "$out" '"opus"' "claudebox openai models has opus" || return 1
    echo "OK: claudebox_openai_models"
}

ALL_TESTS+=(
    test_claudebox_chat
    test_claudebox_direct_api
    test_claudebox_file_ops
    test_claudebox_openai_models
)
