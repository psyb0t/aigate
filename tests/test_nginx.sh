#!/bin/bash

# ── table: nginx routing ────────────────────────────────────────────────────

# format: label|path|expected_in_body
ROUTE_CASES=(
    "root to litellm|/health/liveliness|alive"
    "claudebox proxy|/claudebox/health|ok"
    "claudebox-zai proxy|/claudebox-zai/health|ok"
    "stealthy-auto-browse proxy|/stealthy-auto-browse/__queue/health|ok"
    "hybrids3 proxy|/storage/health|ok"
)

test_nginx_routing() {
    local entry label path expected
    for entry in "${ROUTE_CASES[@]}"; do
        IFS='|' read -r label path expected <<< "$entry"
        local out
        out=$(curl -sf "$BASE_URL$path" 2>/dev/null)
        assert_contains "$out" "$expected" "$label" || return 1
    done
    echo "OK: nginx_routing (${#ROUTE_CASES[@]} routes)"
}

# ── claudebox proxy passes requests ────────────────────────────────────────

test_nginx_claudebox_status() {
    local out
    out=$(curl -sf "$BASE_URL/claudebox/status" \
        -H "Authorization: Bearer $CLAUDEBOX_API_TOKEN" 2>/dev/null)
    assert_contains "$out" "busyWorkspaces" "claudebox status via nginx" || return 1
    echo "OK: nginx_claudebox_status"
}

test_nginx_claudebox_zai_status() {
    local out
    out=$(curl -sf "$BASE_URL/claudebox-zai/status" \
        -H "Authorization: Bearer $CLAUDEBOX_ZAI_API_TOKEN" 2>/dev/null)
    assert_contains "$out" "busyWorkspaces" "claudebox-zai status via nginx" || return 1
    echo "OK: nginx_claudebox_zai_status"
}

# ── stealthy-auto-browse queue status ──────────────────────────────────────

test_nginx_sab_queue_status() {
    local out
    out=$(curl -sf "$BASE_URL/stealthy-auto-browse/__queue/status" 2>/dev/null)
    assert_contains "$out" "num_replicas" "sab queue status has replica count" || return 1
    echo "OK: nginx_sab_queue_status"
}

ALL_TESTS+=(
    test_nginx_routing
    test_nginx_claudebox_status
    test_nginx_claudebox_zai_status
    test_nginx_sab_queue_status
)
