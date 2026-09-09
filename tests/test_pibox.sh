#!/bin/bash

# ── pibox-zai: gated on PIBOX_ZAI=1 ────────────────────────────────────────

_pibox_zai_enabled() {
    [ "${PIBOX_ZAI:-0}" = "1" ]
}

# ── pibox-zai reachable ────────────────────────────────────────────────────

test_pibox_zai_reachable() {
    _pibox_zai_enabled || { echo "  SKIP: PIBOX_ZAI=0"; return 0; }
    local out
    out=$(curl -sf "$BASE_URL/pibox-zai/status" \
        -H "Authorization: Bearer $PIBOX_ZAI_API_TOKEN" 2>/dev/null)
    assert_contains "$out" "busyWorkspaces" "pibox-zai status" || return 1
    echo "OK: pibox_zai_reachable"
}

# ── pibox-zai chat completion via litellm ──────────────────────────────────

test_pibox_zai_chat() {
    _pibox_zai_enabled || { echo "  SKIP: PIBOX_ZAI=0"; return 0; }
    # Use glm-4.7 (not glm-4.5-air). z.ai's glm-4.5-air returns empty
    # content roughly 80% of the time on this exact echo prompt — a
    # weakness of the smallest model, not a pibox bug. Surfaced when
    # pibox v0.10.0 added parse_output text_len=0 logging on the
    # PiAdapter layer. glm-4.7 follows the echo instruction reliably.
    local out
    out=$(post "$BASE_URL/chat/completions" \
        '{"model":"pibox-zai-glm-5.3-flash","messages":[{"role":"system","content":"You are a test echo bot. Reply with exactly what is asked, no commentary."},{"role":"user","content":"Reply with exactly: PIBOXPONG7742"}]}')
    if echo "$out" | grep -qi "authentication_error\|Failed to authenticate\|invalid api key"; then
        echo "  FAIL: pibox-zai z.ai token rejected — check PIBOX_ZAI_AUTH_TOKEN in .env"
        return 1
    fi
    assert_contains "$out" "PIBOXPONG7742" "pibox-zai-glm-5.3-flash responds" || return 1
    assert_contains "$out" "choices" "response has choices" || return 1
    echo "OK: pibox_zai_chat"
}

# ── pibox-zai direct API via nginx ─────────────────────────────────────────

# format: label|path|expected_in_body
PIBOX_ZAI_DIRECT_CASES=(
    "health|/pibox-zai/healthz|true"
    "status|/pibox-zai/status|busyWorkspaces"
)

test_pibox_zai_direct_api() {
    _pibox_zai_enabled || { echo "  SKIP: PIBOX_ZAI=0"; return 0; }
    local entry label path expected
    for entry in "${PIBOX_ZAI_DIRECT_CASES[@]}"; do
        IFS='|' read -r label path expected <<< "$entry"
        local out
        out=$(curl -sf "$BASE_URL$path" \
            -H "Authorization: Bearer $PIBOX_ZAI_API_TOKEN" 2>/dev/null)
        assert_contains "$out" "$expected" "pibox-zai direct: $label" || return 1
    done
    echo "OK: pibox_zai_direct_api (${#PIBOX_ZAI_DIRECT_CASES[@]} cases)"
}

# ── pibox-zai file operations ──────────────────────────────────────────────

test_pibox_zai_file_ops() {
    _pibox_zai_enabled || { echo "  SKIP: PIBOX_ZAI=0"; return 0; }
    local test_file="pibox-zai-test-$(date +%s).txt"
    local test_content="test from pibox-zai tests"

    local code
    code=$(curl -s -o /dev/null -w "%{http_code}" -X PUT \
        "$BASE_URL/pibox-zai/files/$test_file" \
        -H "Authorization: Bearer $PIBOX_ZAI_API_TOKEN" \
        -d "$test_content")
    assert_eq "$code" "200" "upload file to pibox-zai" || return 1

    local body
    body=$(curl -sf "$BASE_URL/pibox-zai/files/$test_file" \
        -H "Authorization: Bearer $PIBOX_ZAI_API_TOKEN")
    assert_eq "$body" "$test_content" "download file from pibox-zai" || return 1

    local list_out
    list_out=$(curl -sf "$BASE_URL/pibox-zai/files" \
        -H "Authorization: Bearer $PIBOX_ZAI_API_TOKEN")
    assert_contains "$list_out" "$test_file" "file in listing" || return 1

    code=$(curl -s -o /dev/null -w "%{http_code}" -X DELETE \
        "$BASE_URL/pibox-zai/files/$test_file" \
        -H "Authorization: Bearer $PIBOX_ZAI_API_TOKEN")
    assert_eq "$code" "200" "delete file from pibox-zai" || return 1

    echo "OK: pibox_zai_file_ops (4 operations)"
}

# ── pibox-zai OpenAI-compatible models endpoint ───────────────────────────
# aicodebox /openai/v1/models lists the PIBOX_AVAILABLE_MODELS entries with
# owned_by="aicodebox". (Pre-aicodebox-v0.8.x, owned_by used to be the
# adapter name "pi"; aicodebox v0.8.0+ — surfaced by pibox v0.9.0 — now
# tags every entry as "aicodebox" instead.) The configured models surface
# through LiteLLM's top-level /v1/models too — checked separately via
# test_pibox_zai_via_litellm_models.

test_pibox_zai_openai_models() {
    _pibox_zai_enabled || { echo "  SKIP: PIBOX_ZAI=0"; return 0; }
    local out
    out=$(curl -sf "$BASE_URL/pibox-zai/openai/v1/models" \
        -H "Authorization: Bearer $PIBOX_ZAI_API_TOKEN" 2>/dev/null)
    assert_contains "$out" '"object":"list"' "pibox-zai openai models returns list" || return 1
    assert_contains "$out" '"owned_by":"aicodebox"' "pibox-zai openai models entries tagged owned_by=aicodebox" || return 1
    assert_contains "$out" '"glm-4.7"' "pibox-zai openai models lists glm-4.7" || return 1
    echo "OK: pibox_zai_openai_models"
}

# ── pibox-zai models exposed via LiteLLM ──────────────────────────────────

test_pibox_zai_via_litellm_models() {
    _pibox_zai_enabled || { echo "  SKIP: PIBOX_ZAI=0"; return 0; }
    local out
    out=$(get "$BASE_URL/v1/models")
    assert_contains "$out" "pibox-zai-glm-5.3" "litellm registers pibox-zai-glm-5.3" || return 1
    assert_contains "$out" "pibox-zai-glm-5.3-flash" "litellm registers pibox-zai-glm-5.3-flash" || return 1
    echo "OK: pibox_zai_via_litellm_models"
}

# ── pibox-zai /run sync endpoint ──────────────────────────────────────────

test_pibox_zai_run_sync() {
    _pibox_zai_enabled || { echo "  SKIP: PIBOX_ZAI=0"; return 0; }
    local out
    out=$(curl -sf -X POST "$BASE_URL/pibox-zai/run" \
        -H "Authorization: Bearer $PIBOX_ZAI_API_TOKEN" \
        -H "Content-Type: application/json" \
        --max-time 120 \
        -d '{"prompt":"Reply with exactly: PIBOXRUN9988. No commentary.","noTools":true}' 2>/dev/null)
    if echo "$out" | grep -qi "authentication_error\|invalid api key"; then
        echo "  FAIL: pibox-zai /run — z.ai token rejected"
        return 1
    fi
    assert_contains "$out" "PIBOXRUN9988" "pibox-zai /run returns expected text" || return 1
    assert_contains "$out" "exitCode" "pibox-zai /run response shape" || return 1
    echo "OK: pibox_zai_run_sync"
}

ALL_TESTS+=(
    test_pibox_zai_reachable
    test_pibox_zai_direct_api
    test_pibox_zai_file_ops
    test_pibox_zai_openai_models
    test_pibox_zai_via_litellm_models
    test_pibox_zai_chat
    test_pibox_zai_run_sync
)
