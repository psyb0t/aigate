#!/bin/bash

# ── table: service health endpoints ─────────────────────────────────────────

# format: label|url|expected_in_body
HEALTH_CASES=(
    "litellm liveliness|$BASE_URL/health/liveliness|alive"
    "claudebox health|$BASE_URL/claudebox/health|ok"
    "claudebox-zai health|$BASE_URL/claudebox-zai/health|ok"
    "stealthy-auto-browse health|$BASE_URL/stealthy-auto-browse/__queue/health|ok"
    "hybrids3 health|$BASE_URL/storage/health|ok"
)

test_health_endpoints() {
    local entry label url expected
    for entry in "${HEALTH_CASES[@]}"; do
        IFS='|' read -r label url expected <<< "$entry"
        local out
        out=$(curl -sf "$url" 2>/dev/null)
        assert_contains "$out" "$expected" "$label" || return 1
    done
    echo "OK: health_endpoints (${#HEALTH_CASES[@]} endpoints)"
}

# ── docker compose services all healthy ─────────────────────────────────────

REQUIRED_SERVICES=(
    "claudebox"
    "claudebox-zai"
    "hybrids3"
    "litellm"
    "nginx"
    "postgres"
    "redis"
    "stealthy-auto-browse-proxy"
    "stealthy-auto-browse-redis"
)

test_health_compose_services() {
    local status
    status=$(docker compose ps --format '{{.Name}} {{.Status}}' 2>/dev/null)

    local svc
    for svc in "${REQUIRED_SERVICES[@]}"; do
        local line
        line=$(echo "$status" | grep "$svc" | head -1)
        assert_not_empty "$line" "service $svc exists" || return 1
        assert_contains "$line" "Up" "service $svc is up" || return 1
    done

    # stealthy-auto-browse replicas (at least 1)
    local sab_count
    sab_count=$(echo "$status" | grep -c "stealthy-auto-browse-[0-9]" || true)
    if [ "$sab_count" -lt 1 ]; then
        echo "  FAIL: expected at least 1 stealthy-auto-browse replica, got $sab_count"
        return 1
    fi
    echo "  OK: $sab_count stealthy-auto-browse replicas running"

    echo "OK: compose_services (${#REQUIRED_SERVICES[@]} services + $sab_count browser replicas)"
}

ALL_TESTS+=(
    test_health_endpoints
    test_health_compose_services
)
