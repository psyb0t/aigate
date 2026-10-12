#!/bin/bash

test_proxy_discovery_rejects_forged_headers() {
    local response issuer
    response=$(curl -fsS "$BASE_URL/.well-known/oauth-authorization-server" \
        -H "X-Forwarded-Host: forged.example.com" \
        -H "X-Forwarded-Proto: https" \
        -H "X-Forwarded-For: 127.0.0.1" \
        -H "CF-Connecting-IP: 127.0.0.1") || return 1
    issuer=$(printf '%s' "$response" | python3 -c 'import json,sys;print(json.load(sys.stdin)["issuer"])') || return 1
    assert_eq "$issuer" "${PROXY_BASE_URL:-${BASE_URL%/}}" "OAuth issuer ignores forged headers"
}

test_litellm_cross_worker_key_revocation() {
    BASE_URL="$BASE_URL" LITELLM_MASTER_KEY="$LITELLM_MASTER_KEY" \
        python3 "$WORKDIR/tests/integration/key_revocation.py"
}

ALL_TESTS+=(
    test_proxy_discovery_rejects_forged_headers
    test_litellm_cross_worker_key_revocation
)
