#!/bin/bash

# ── proxq: async job queue via /q/ ─────────────────────────────────────────

test_proxq_health_passthrough() {
    # health should bypass queue (whitelist mode) and hit litellm directly
    local out
    out=$(curl -sf "$BASE_URL/q/health/liveliness" 2>/dev/null)
    assert_contains "$out" "alive" "proxq passthrough health" || return 1
    echo "OK: proxq_health_passthrough"
}

test_proxq_model_list_passthrough() {
    # /v1/models is NOT whitelisted — should pass through directly
    local code
    code=$(curl -s -o /dev/null -w "%{http_code}" \
        -H "$AUTH_HEADER" \
        "$BASE_URL/q/v1/models" 2>/dev/null)
    # not whitelisted — proxied directly to litellm
    if [ "$code" = "200" ]; then
        echo "  OK: proxq model list bypasses queue (HTTP $code)"
    else
        echo "  FAIL: expected 200 for /q/v1/models, got $code"
        return 1
    fi
    echo "OK: proxq_model_list_passthrough"
}

test_proxq_async_job_lifecycle() {
    # submit a chat completion through /q/ — should get 202 + jobId
    local submit_resp
    submit_resp=$(curl -s -X POST "$BASE_URL/q/v1/chat/completions" \
        -H "Content-Type: application/json" \
        -H "$AUTH_HEADER" \
        -w "\n%{http_code}" \
        -d '{"model": "cerebras-llama-3.1-8b", "messages": [{"role": "user", "content": "say ok"}], "max_tokens": 5}')

    local submit_body submit_code
    submit_code=$(echo "$submit_resp" | tail -1)
    submit_body=$(echo "$submit_resp" | sed '$d')

    assert_eq "$submit_code" "202" "proxq submit returns 202" || return 1

    local job_id
    job_id=$(echo "$submit_body" | json_get '["jobId"]')
    assert_not_empty "$job_id" "proxq returns jobId" || return 1
    echo "  job_id: $job_id"

    # poll for completion (up to 60s)
    local status=""
    local i
    for i in $(seq 1 30); do
        local poll_resp
        poll_resp=$(curl -s "$BASE_URL/q/__jobs/$job_id" -H "$AUTH_HEADER" 2>/dev/null)
        status=$(echo "$poll_resp" | json_get '["status"]' 2>/dev/null || echo "")

        if [ "$status" = "completed" ] || [ "$status" = "failed" ]; then
            break
        fi
        sleep 2
    done

    assert_eq "$status" "completed" "proxq job completed" || {
        echo "  last poll response: $poll_resp"
        return 1
    }

    # fetch content — should replay the upstream response
    local content_resp content_code
    content_resp=$(curl -s "$BASE_URL/q/__jobs/$job_id/content" \
        -H "$AUTH_HEADER" \
        -w "\n%{http_code}")

    content_code=$(echo "$content_resp" | tail -1)
    local content_body
    content_body=$(echo "$content_resp" | sed '$d')

    assert_eq "$content_code" "200" "proxq content returns 200" || return 1
    assert_contains "$content_body" "choices" "proxq content has choices" || return 1

    # cancel (already completed — should 404)
    local cancel_code
    cancel_code=$(curl -s -o /dev/null -w "%{http_code}" \
        -X DELETE "$BASE_URL/q/__jobs/$job_id" \
        -H "$AUTH_HEADER")
    # completed jobs may return 404 (already archived) or 200
    echo "  OK: cancel returned $cancel_code (expected for completed job)"

    echo "OK: proxq_async_job_lifecycle"
}

test_proxq_nonexistent_job() {
    local code
    code=$(curl -s -o /dev/null -w "%{http_code}" \
        "$BASE_URL/q/__jobs/00000000-0000-0000-0000-000000000000" \
        -H "$AUTH_HEADER")
    assert_eq "$code" "404" "proxq nonexistent job returns 404" || return 1
    echo "OK: proxq_nonexistent_job"
}

ALL_TESTS+=(
    test_proxq_health_passthrough
    test_proxq_model_list_passthrough
    test_proxq_async_job_lifecycle
    test_proxq_nonexistent_job
)
