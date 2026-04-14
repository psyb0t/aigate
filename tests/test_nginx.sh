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

# ── /ui/ with optional basic auth ──────────────────────────────────────────

test_nginx_admin_auth() {
    if [ -z "${LITELLM_UI_BASIC_AUTH:-}" ]; then
        local code
        code=$(curl -s -o /dev/null -w "%{http_code}" "$BASE_URL/ui/")
        assert_eq "$code" "200" "/ui/ open when no auth configured" || return 1
        echo "OK: nginx_admin_auth (no auth)"
        return 0
    fi

    local user pass
    user="${LITELLM_UI_BASIC_AUTH%%:*}"
    pass="${LITELLM_UI_BASIC_AUTH#*:}"

    local code_no_creds code_bad_creds code_good_creds
    code_no_creds=$(curl -s -o /dev/null -w "%{http_code}" "$BASE_URL/ui/")
    code_bad_creds=$(curl -s -o /dev/null -w "%{http_code}" -u "wrong:wrong" "$BASE_URL/ui/")
    code_good_creds=$(curl -s -o /dev/null -w "%{http_code}" -u "$user:$pass" "$BASE_URL/ui/")

    assert_eq "$code_no_creds"  "401" "/ui/ rejected without creds" || return 1
    assert_eq "$code_bad_creds" "401" "/ui/ rejected with bad creds" || return 1
    assert_eq "$code_good_creds" "200" "/ui/ accepted with correct creds" || return 1
    echo "OK: nginx_admin_auth (basic auth enforced)"
}

# ── admin rate limiting (5 req/min, burst 5) ────────────────────────────────

test_nginx_admin_rate_limit() {
    local creds=()
    if [ -n "${LITELLM_UI_BASIC_AUTH:-}" ]; then
        creds=(-u "$LITELLM_UI_BASIC_AUTH")
    fi

    # fire 10 rapid requests — burst is 5, so at least some must be rejected
    local i code rejected=0
    for i in $(seq 1 10); do
        code=$(curl -s -o /dev/null -w "%{http_code}" "${creds[@]}" "$BASE_URL/ui/")
        [ "$code" = "503" ] || [ "$code" = "429" ] && rejected=$((rejected + 1))
    done

    if [ "$rejected" -eq 0 ]; then
        echo "  FAIL: admin rate limit: 10 rapid requests, none rejected"
        return 1
    fi
    echo "  OK: $rejected/10 requests rate limited"
    echo "OK: nginx_admin_rate_limit"
}

ALL_TESTS+=(
    test_nginx_routing
    test_nginx_claudebox_status
    test_nginx_claudebox_zai_status
    test_nginx_sab_queue_status
    test_nginx_admin_auth
    test_nginx_admin_rate_limit
)
