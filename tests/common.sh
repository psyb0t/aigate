#!/bin/bash

WORKDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ALL_TESTS=()

BASE_URL="${BASE_URL:-http://localhost:4000}"

# load .env
ENV_FILE="$WORKDIR/.env"
if [ ! -f "$ENV_FILE" ]; then
    echo ".env not found — copy .env.example and fill it in" >&2
    exit 1
fi
# shellcheck disable=SC1090
source "$ENV_FILE"

if [ -z "${LITELLM_MASTER_KEY:-}" ]; then
    echo "LITELLM_MASTER_KEY not set in .env" >&2
    exit 1
fi

AUTH_HEADER="Authorization: Bearer $LITELLM_MASTER_KEY"

# ── assertions ───────────────────────────────────────────────────────────────

assert_eq() {
    local actual="$1" expected="$2" name="$3"
    if [ "$actual" = "$expected" ]; then
        echo "  OK: $name"
        return 0
    fi
    echo "  FAIL: $name: expected '$expected', got '$actual'"
    return 1
}

assert_contains() {
    local actual="$1" expected="$2" name="$3"
    if [[ "$actual" == *"$expected"* ]]; then
        echo "  OK: $name"
        return 0
    fi
    echo "  FAIL: $name: expected to contain '$expected'"
    echo "  actual: ${actual:0:500}"
    return 1
}

assert_not_contains() {
    local actual="$1" unexpected="$2" name="$3"
    if [[ "$actual" != *"$unexpected"* ]]; then
        echo "  OK: $name"
        return 0
    fi
    echo "  FAIL: $name: should NOT contain '$unexpected'"
    echo "  actual: ${actual:0:500}"
    return 1
}

assert_not_empty() {
    local actual="$1" name="$2"
    if [ -n "$actual" ]; then
        echo "  OK: $name"
        return 0
    fi
    echo "  FAIL: $name: expected non-empty output"
    return 1
}

assert_contains_icase() {
    local actual="$1" expected="$2" name="$3"
    local actual_lower expected_lower
    actual_lower=$(echo "$actual" | tr '[:upper:]' '[:lower:]')
    expected_lower=$(echo "$expected" | tr '[:upper:]' '[:lower:]')
    if [[ "$actual_lower" == *"$expected_lower"* ]]; then
        echo "  OK: $name"
        return 0
    fi
    echo "  FAIL: $name: expected to contain '$expected' (case-insensitive)"
    echo "  actual: ${actual:0:500}"
    return 1
}

assert_exit_code() {
    local actual="$1" expected="$2" name="$3"
    assert_eq "$actual" "$expected" "$name (exit code)"
}

assert_http_code() {
    local url="$1" expected="$2" name="$3"
    shift 3
    local code
    code=$(curl -s -o /dev/null -w "%{http_code}" "$@" "$url")
    assert_eq "$code" "$expected" "$name"
}

assert_json_field() {
    local json="$1" field="$2" expected="$3" name="$4"
    local val
    val=$(echo "$json" | python3 -c "import sys,json; print(json.load(sys.stdin)$field)" 2>/dev/null)
    assert_eq "$val" "$expected" "$name"
}

# ── helpers ──────────────────────────────────────────────────────────────────

json_get() {
    python3 -c "import sys,json; print(json.load(sys.stdin)$1)"
}

post() {
    local url="$1" data="$2"
    curl -sf -X POST "$url" \
        -H "Content-Type: application/json" \
        -H "$AUTH_HEADER" \
        -d "$data"
}

get() {
    local url="$1"
    shift
    curl -sf "$url" -H "$AUTH_HEADER" "$@"
}

wait_for_http() {
    local url="$1" max="${2:-60}"
    for _ in $(seq 1 "$max"); do
        if curl -sf "$url" >/dev/null 2>&1; then
            return 0
        fi
        sleep 1
    done
    echo "  timeout waiting for $url"
    return 1
}

# ── setup / cleanup ─────────────────────────────────────────────────────────

setup() {
    echo "checking stack health..."
    wait_for_http "$BASE_URL/health/liveliness" 10 || {
        echo "stack not running — start with: docker compose up -d"
        exit 1
    }
}

cleanup() { :; }
test_setup() { :; }
test_teardown() { :; }

usage() {
    echo "usage: $0 [test_name ...]"
    echo ""
    echo "available tests:"
    for t in "${ALL_TESTS[@]}"; do
        echo "  $t"
    done
}
