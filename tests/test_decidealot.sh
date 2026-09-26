#!/bin/bash

# ── decidealot: gated on DECIDEALOT=1 / DECIDEALOT_CUDA=1 ─────────────────
#
# Two variants live side-by-side on distinct nginx routes:
#   /decidealot/        → CPU container (DECIDEALOT=1)
#   /decidealot-cuda/   → GPU container (DECIDEALOT_CUDA=1)
# Tools in the aggregated /mcp/ are namespaced `decidealot-<tool>` and
# `decidealot_cuda-<tool>`. The helpers take the route prefix and namespace so
# one suite covers both variants.
#
# The decision tests use `laya` only. A Laya/Von swap costs a cold model start,
# which on CPU runs past a minute.

_DECIDEALOT_MCP_ACCEPT="Accept: application/json, text/event-stream"
_DECIDEALOT_DECISION_TIMEOUT_SECONDS=600
_DECIDEALOT_REMOTE_HOST="aigate.example.net"
_DECIDEALOT_MCP_INIT='{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"aigate-test","version":"1"}}}'
_DECIDEALOT_NOUL_QUESTION='"q":{"type":"noul","criteria":{"true":"yes","false":"no"}}'
# One byte over decidealot's default DECIDEALOT_MAX_REQUEST_BYTES (1 MiB).
_DECIDEALOT_OVERSIZED_STATE_BYTES=1048577
_DECIDEALOT_STATUS_OK="200"
_DECIDEALOT_STATUS_UNAUTHORIZED="401"
_DECIDEALOT_STATUS_TOO_LARGE="413"
_DECIDEALOT_STATUS_INVALID="422"
# A cheap local embedding call routed through LiteLLM. Its group competes
# with decidealot on the same hardware, so the resource manager must evict
# decidealot's resident model before the embedding runs.
_DECIDEALOT_CUDA_EVICTION_TRIGGER_MODEL="local-ollama-cuda-bge-m3"
_DECIDEALOT_CPU_EVICTION_TRIGGER_MODEL="local-ollama-cpu-bge-m3"
_DECIDEALOT_EVICTION_TRIGGER_TIMEOUT_SECONDS=300
_DECIDEALOT_LOG_WINDOW_SLACK_SECONDS=5

_decidealot_cpu_enabled()  { [ "${DECIDEALOT:-0}" = "1" ]; }
_decidealot_cuda_enabled() { [ "${DECIDEALOT_CUDA:-0}" = "1" ]; }

_decidealot_token() {
    # DECIDEALOT_AUTH_TOKEN if explicitly set, else AIGATE_TOKEN (master chain).
    echo "${DECIDEALOT_AUTH_TOKEN:-${AIGATE_TOKEN:-}}"
}

# POST a body to /v1/systemone with the real token and print the status code.
# The body goes through stdin because the oversized case is past the kernel's
# 128 KiB limit on a single command-line argument.
_decidealot_systemone_status() {
    local prefix="$1" body="$2"
    printf '%s' "$body" | curl -s -o /dev/null -w "%{http_code}" -X POST "$BASE_URL${prefix}/v1/systemone" \
        -H "Authorization: Bearer $(_decidealot_token)" \
        -H "Content-Type: application/json" \
        --data-binary @-
}

# ── shared assertions, parameterised on route prefix + mcp namespace ─────

_decidealot_test_health() {
    local prefix="$1" tag="$2"
    local out
    out=$(curl -sf "$BASE_URL${prefix}/health")
    assert_contains "$out" '"status":"ok"' "${tag} ${prefix}/health ok without a token" || return 1
    assert_contains "$out" '"laya"' "${tag} health lists laya" || return 1
    assert_contains "$out" '"von"' "${tag} health lists von" || return 1
    echo "OK: ${tag} health"
}

_decidealot_test_requires_auth() {
    local prefix="$1" tag="$2"
    assert_http_code "$BASE_URL${prefix}/v1/models" "$_DECIDEALOT_STATUS_UNAUTHORIZED" \
        "${tag} /v1/models rejects a missing token" || return 1
    assert_http_code "$BASE_URL${prefix}/v1/systemone" "$_DECIDEALOT_STATUS_UNAUTHORIZED" \
        "${tag} /v1/systemone rejects a wrong token" \
        -X POST -H "Authorization: Bearer not-the-token" -H "Content-Type: application/json" -d '{}' || return 1
    echo "OK: ${tag} requires_auth"
}

_decidealot_test_models_list() {
    local prefix="$1" tag="$2"
    local out
    out=$(curl -sf "$BASE_URL${prefix}/v1/models" \
        -H "Authorization: Bearer $(_decidealot_token)")
    assert_contains "$out" '"laya"' "${tag} models has laya" || return 1
    assert_contains "$out" '"laya-typed-decisions"' "${tag} models has laya-typed-decisions" || return 1
    assert_contains "$out" '"von-1.1"' "${tag} models has von-1.1" || return 1
    echo "OK: ${tag} models_list"
}

_decidealot_test_choice_decision() {
    local prefix="$1" tag="$2"
    local out
    out=$(curl -sf -X POST "$BASE_URL${prefix}/v1/systemone" \
        -H "Authorization: Bearer $(_decidealot_token)" \
        -H "Content-Type: application/json" \
        --max-time "$_DECIDEALOT_DECISION_TIMEOUT_SECONDS" \
        -d '{
            "model": "laya",
            "state": "A proposed action would permanently delete protected data.",
            "questions": {
                "handling": {
                    "type": "choice",
                    "criteria": {
                        "allow": "The action is reversible and does not affect protected data.",
                        "require_review": "The action is irreversible or affects protected data."
                    }
                },
                "needs_review": {
                    "type": "noul",
                    "criteria": {
                        "true": "Review is required before the operation.",
                        "false": "The operation may run without human review."
                    }
                }
            }
        }')
    assert_not_empty "$out" "${tag} systemone response" || return 1
    assert_json_field "$out" "['model']" "laya" "${tag} systemone echoes the model" || return 1
    assert_json_field "$out" "['answers']['handling']['type']" "choice" "${tag} choice answer type" || return 1
    assert_contains "$out" '"probabilities"' "${tag} choice carries probabilities" || return 1
    assert_json_field "$out" "['answers']['needs_review']['type']" "noul" "${tag} noul answer type" || return 1
    echo "OK: ${tag} choice_decision"
}

_decidealot_test_rejects_invalid_requests() {
    local prefix="$1" tag="$2"
    local oversized_state
    oversized_state=$(head -c "$_DECIDEALOT_OVERSIZED_STATE_BYTES" /dev/zero | tr '\0' 'a')
    local -a cases=(
        "unsupported model|$_DECIDEALOT_STATUS_INVALID|{\"model\":\"jev\",\"state\":\"x\",\"questions\":{$_DECIDEALOT_NOUL_QUESTION}}"
        "missing model|$_DECIDEALOT_STATUS_INVALID|{\"state\":\"x\",\"questions\":{$_DECIDEALOT_NOUL_QUESTION}}"
        "choice without criteria|$_DECIDEALOT_STATUS_INVALID|{\"model\":\"laya\",\"state\":\"x\",\"questions\":{\"q\":{\"type\":\"choice\"}}}"
        "malformed json|$_DECIDEALOT_STATUS_INVALID|{not json"
        "oversized body|$_DECIDEALOT_STATUS_TOO_LARGE|{\"model\":\"laya\",\"state\":\"$oversized_state\",\"questions\":{$_DECIDEALOT_NOUL_QUESTION}}"
    )
    local case name expected body code
    for case in "${cases[@]}"; do
        name="${case%%|*}"
        expected="${case#*|}"
        expected="${expected%%|*}"
        body="${case#*|*|}"
        code=$(_decidealot_systemone_status "$prefix" "$body")
        assert_eq "$code" "$expected" "${tag} ${name} is rejected" || return 1
    done
    echo "OK: ${tag} rejects_invalid_requests"
}

_decidealot_test_models_unload() {
    local prefix="$1" tag="$2"
    local out
    out=$(curl -sf -X POST "$BASE_URL${prefix}/v1/models/unload" \
        -H "Authorization: Bearer $(_decidealot_token)")
    assert_json_field "$out" "['status']" "unloaded" "${tag} unload reports unloaded" || return 1
    assert_contains "$out" '"name":"laya"' "${tag} unload lists laya" || return 1
    assert_contains "$out" '"name":"von"' "${tag} unload lists von" || return 1
    echo "OK: ${tag} models_unload"
}

# Load laya, then send a LiteLLM request whose group competes on the same
# hardware. The resource manager must log that it evicted laya.
_decidealot_test_evicted_by_resource_manager() {
    local prefix="$1" tag="$2" group="$3" trigger_model="$4"
    local code
    code=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$BASE_URL${prefix}/v1/systemone" \
        -H "Authorization: Bearer $(_decidealot_token)" \
        -H "Content-Type: application/json" \
        --max-time "$_DECIDEALOT_DECISION_TIMEOUT_SECONDS" \
        -d "{\"model\":\"laya\",\"state\":\"x\",\"questions\":{$_DECIDEALOT_NOUL_QUESTION}}")
    assert_eq "$code" "$_DECIDEALOT_STATUS_OK" "${tag} laya loaded by a decision" || return 1

    local started
    started=$(date -u +%s)
    code=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$BASE_URL/v1/embeddings" \
        -H "$AUTH_HEADER" \
        -H "Content-Type: application/json" \
        --max-time "$_DECIDEALOT_EVICTION_TRIGGER_TIMEOUT_SECONDS" \
        -d "{\"model\":\"${trigger_model}\",\"input\":\"resource manager eviction check\"}")
    assert_eq "$code" "$_DECIDEALOT_STATUS_OK" "${tag} ${trigger_model} embedding" || return 1

    local window logs
    window=$(( $(date -u +%s) - started + _DECIDEALOT_LOG_WINDOW_SLACK_SECONDS ))
    # stderr dropped on purpose: compose prints project warnings there, and
    # only the LiteLLM log lines on stdout are asserted on.
    logs=$(docker compose -f "$WORKDIR/docker-compose.yml" logs --since "${window}s" litellm 2>/dev/null)
    assert_contains "$logs" "${group}: unloaded ['laya']" "${tag} resource manager evicted laya" || return 1
    echo "OK: ${tag} evicted_by_resource_manager"
}

# decidealot's MCP answers 421 to a Host outside its allowlist, so nginx pins
# the upstream Host to loopback. A caller on a tailnet or tunnel name must
# still get through.
_decidealot_test_mcp_remote_host() {
    local prefix="$1" tag="$2"
    local code
    code=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$BASE_URL${prefix}/mcp" \
        -H "Host: $_DECIDEALOT_REMOTE_HOST" \
        -H "Authorization: Bearer $(_decidealot_token)" \
        -H "Content-Type: application/json" \
        -H "$_DECIDEALOT_MCP_ACCEPT" \
        -d "$_DECIDEALOT_MCP_INIT")
    assert_eq "$code" "$_DECIDEALOT_STATUS_OK" "${tag} direct MCP initialize with a non-local Host" || return 1
    echo "OK: ${tag} mcp_remote_host"
}

# LiteLLM's MCP client calls each container by its service name, which only
# works while that name is in the container's DECIDEALOT_MCP_ALLOWED_HOSTS.
_decidealot_test_mcp_aggregated_call() {
    local namespace="$1" tag="$2"
    local result_json
    result_json=$(curl -s -X POST "$BASE_URL/mcp/" \
        -H "Content-Type: application/json" \
        -H "$AUTH_HEADER" \
        -H "$_DECIDEALOT_MCP_ACCEPT" \
        -d "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"${namespace}-list_models\",\"arguments\":{}}}" \
        | grep "^data:" | head -1 | sed 's/^data: //')
    assert_not_empty "$result_json" "${tag} aggregated ${namespace}-list_models response" || return 1
    assert_contains "$result_json" 'laya-typed-decisions' "${tag} aggregated ${namespace}-list_models returns the catalog" || return 1
    echo "OK: ${tag} mcp_aggregated_call"
}

_decidealot_test_mcp_tools_present() {
    local namespace="$1" tag="$2"
    local tools_json
    tools_json=$(curl -s -X POST "$BASE_URL/mcp/" \
        -H "Content-Type: application/json" \
        -H "$AUTH_HEADER" \
        -H "$_DECIDEALOT_MCP_ACCEPT" \
        -d '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}' \
        | grep "^data:" | head -1 | sed 's/^data: //')
    assert_not_empty "$tools_json" "${tag} mcp tools response" || return 1
    local tool
    for tool in system_one list_models unload_models; do
        assert_contains "$tools_json" "\"${namespace}-${tool}\"" "${tag} aggregated MCP has ${namespace}-${tool}" || return 1
    done
    echo "OK: ${tag} mcp_tools_present"
}

# ── CPU variant ────────────────────────────────────────────────────────────

test_decidealot_cpu_health()                  { _decidealot_cpu_enabled  || { echo "  SKIP: DECIDEALOT not enabled"; return 0; }; _decidealot_test_health                  /decidealot      "decidealot-cpu"; }
test_decidealot_cpu_requires_auth()           { _decidealot_cpu_enabled  || { echo "  SKIP: DECIDEALOT not enabled"; return 0; }; _decidealot_test_requires_auth           /decidealot      "decidealot-cpu"; }
test_decidealot_cpu_models_list()             { _decidealot_cpu_enabled  || { echo "  SKIP: DECIDEALOT not enabled"; return 0; }; _decidealot_test_models_list             /decidealot      "decidealot-cpu"; }
test_decidealot_cpu_choice_decision()         { _decidealot_cpu_enabled  || { echo "  SKIP: DECIDEALOT not enabled"; return 0; }; _decidealot_test_choice_decision         /decidealot      "decidealot-cpu"; }
test_decidealot_cpu_rejects_invalid_requests() { _decidealot_cpu_enabled || { echo "  SKIP: DECIDEALOT not enabled"; return 0; }; _decidealot_test_rejects_invalid_requests /decidealot      "decidealot-cpu"; }
test_decidealot_cpu_mcp_remote_host()         { _decidealot_cpu_enabled  || { echo "  SKIP: DECIDEALOT not enabled"; return 0; }; _decidealot_test_mcp_remote_host         /decidealot      "decidealot-cpu"; }
test_decidealot_cpu_mcp_tools_present()       { _decidealot_cpu_enabled  || { echo "  SKIP: DECIDEALOT not enabled"; return 0; }; _decidealot_test_mcp_tools_present       decidealot       "decidealot-cpu"; }
test_decidealot_cpu_mcp_aggregated_call()     { _decidealot_cpu_enabled  || { echo "  SKIP: DECIDEALOT not enabled"; return 0; }; _decidealot_test_mcp_aggregated_call     decidealot       "decidealot-cpu"; }
test_decidealot_cpu_models_unload()           { _decidealot_cpu_enabled  || { echo "  SKIP: DECIDEALOT not enabled"; return 0; }; _decidealot_test_models_unload           /decidealot      "decidealot-cpu"; }
test_decidealot_cpu_evicted_by_resource_manager() {
    _decidealot_cpu_enabled || { echo "  SKIP: DECIDEALOT not enabled"; return 0; }
    [ "${OLLAMA:-0}" = "1" ] || { echo "  SKIP: OLLAMA not enabled (eviction trigger)"; return 0; }
    _decidealot_test_evicted_by_resource_manager /decidealot "decidealot-cpu" cpu-decidealot "$_DECIDEALOT_CPU_EVICTION_TRIGGER_MODEL"
}

# ── CUDA variant ───────────────────────────────────────────────────────────

test_decidealot_cuda_health()                  { _decidealot_cuda_enabled || { echo "  SKIP: DECIDEALOT_CUDA not enabled"; return 0; }; _decidealot_test_health                  /decidealot-cuda "decidealot-cuda"; }
test_decidealot_cuda_requires_auth()           { _decidealot_cuda_enabled || { echo "  SKIP: DECIDEALOT_CUDA not enabled"; return 0; }; _decidealot_test_requires_auth           /decidealot-cuda "decidealot-cuda"; }
test_decidealot_cuda_models_list()             { _decidealot_cuda_enabled || { echo "  SKIP: DECIDEALOT_CUDA not enabled"; return 0; }; _decidealot_test_models_list             /decidealot-cuda "decidealot-cuda"; }
test_decidealot_cuda_choice_decision()         { _decidealot_cuda_enabled || { echo "  SKIP: DECIDEALOT_CUDA not enabled"; return 0; }; _decidealot_test_choice_decision         /decidealot-cuda "decidealot-cuda"; }
test_decidealot_cuda_rejects_invalid_requests() { _decidealot_cuda_enabled || { echo "  SKIP: DECIDEALOT_CUDA not enabled"; return 0; }; _decidealot_test_rejects_invalid_requests /decidealot-cuda "decidealot-cuda"; }
test_decidealot_cuda_mcp_remote_host()         { _decidealot_cuda_enabled || { echo "  SKIP: DECIDEALOT_CUDA not enabled"; return 0; }; _decidealot_test_mcp_remote_host         /decidealot-cuda "decidealot-cuda"; }
test_decidealot_cuda_mcp_tools_present()       { _decidealot_cuda_enabled || { echo "  SKIP: DECIDEALOT_CUDA not enabled"; return 0; }; _decidealot_test_mcp_tools_present       decidealot_cuda  "decidealot-cuda"; }
test_decidealot_cuda_mcp_aggregated_call()     { _decidealot_cuda_enabled || { echo "  SKIP: DECIDEALOT_CUDA not enabled"; return 0; }; _decidealot_test_mcp_aggregated_call     decidealot_cuda  "decidealot-cuda"; }
test_decidealot_cuda_models_unload()           { _decidealot_cuda_enabled || { echo "  SKIP: DECIDEALOT_CUDA not enabled"; return 0; }; _decidealot_test_models_unload           /decidealot-cuda "decidealot-cuda"; }
test_decidealot_cuda_evicted_by_resource_manager() {
    _decidealot_cuda_enabled || { echo "  SKIP: DECIDEALOT_CUDA not enabled"; return 0; }
    [ "${OLLAMA_CUDA:-0}" = "1" ] || { echo "  SKIP: OLLAMA_CUDA not enabled (eviction trigger)"; return 0; }
    _decidealot_test_evicted_by_resource_manager /decidealot-cuda "decidealot-cuda" cuda-decidealot "$_DECIDEALOT_CUDA_EVICTION_TRIGGER_MODEL"
}

ALL_TESTS+=(
    test_decidealot_cpu_health
    test_decidealot_cpu_requires_auth
    test_decidealot_cpu_models_list
    test_decidealot_cpu_choice_decision
    test_decidealot_cpu_rejects_invalid_requests
    test_decidealot_cpu_mcp_remote_host
    test_decidealot_cpu_mcp_tools_present
    test_decidealot_cpu_mcp_aggregated_call
    test_decidealot_cpu_models_unload
    test_decidealot_cpu_evicted_by_resource_manager
    test_decidealot_cuda_health
    test_decidealot_cuda_requires_auth
    test_decidealot_cuda_models_list
    test_decidealot_cuda_choice_decision
    test_decidealot_cuda_rejects_invalid_requests
    test_decidealot_cuda_mcp_remote_host
    test_decidealot_cuda_mcp_tools_present
    test_decidealot_cuda_mcp_aggregated_call
    test_decidealot_cuda_models_unload
    test_decidealot_cuda_evicted_by_resource_manager
)
