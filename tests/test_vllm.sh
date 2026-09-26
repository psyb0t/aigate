#!/bin/bash

# ── vllm CPU + CUDA: gated on VLLM=1 / VLLM_CUDA=1 ───────────────────────
#
# Both variants run on the aigate-internal network only — no nginx route. The
# wrapper-introspection tests reach each upstream via `docker compose exec
# litellm` (also on aigate-internal). Live chat + embedding tests go through
# the public LiteLLM proxy at $BASE_URL using registered aliases.
#
# The introspection helpers are parameterized by upstream host (the compose
# service name resolves on aigate-internal) so both variants share one suite.

_vllm_cpu_enabled()  { [ "${VLLM:-0}" = "1" ]; }
_vllm_cuda_enabled() { [ "${VLLM_CUDA:-0}" = "1" ]; }

_vllm_wrap_exec() {
    local host="$1" path="$2"
    docker compose exec -T litellm python3 -c "
import sys, urllib.request
req = urllib.request.Request('http://${host}:8000${path}')
sys.stdout.write(urllib.request.urlopen(req, timeout=10).read().decode())
" 2>/dev/null
}

_vllm_wrap_exec_method() {
    local host="$1" method="$2" path="$3"
    docker compose exec -T litellm python3 -c "
import sys, urllib.request
req = urllib.request.Request('http://${host}:8000${path}', method='${method}')
sys.stdout.write(urllib.request.urlopen(req, timeout=10).read().decode())
" 2>/dev/null
}

_vllm_wrap_exec_status() {
    local host="$1" method="$2" path="$3"
    docker compose exec -T litellm python3 -c "
import urllib.request, urllib.error
try:
    urllib.request.urlopen(urllib.request.Request('http://${host}:8000${path}', method='${method}'), timeout=10)
    print(200)
except urllib.error.HTTPError as e:
    print(e.code)
except Exception:
    print(0)
" 2>/dev/null
}

# ── shared introspection assertions ───────────────────────────────────────

_vllm_test_healthz() {
    local host="$1" tag="$2"
    shift 2
    local out model
    out=$(_vllm_wrap_exec "$host" "/healthz") || {
        echo "  FAIL: ${tag} /healthz unreachable"; return 1
    }
    assert_contains "$out" "\"ok\":true" "${tag} /healthz ok=true" || return 1
    for model in "$@"; do
        assert_contains "$out" "$model" "${tag} /healthz lists ${model}" || return 1
    done
    echo "OK: ${tag} vllm_wrap_healthz"
}

_vllm_test_models_list() {
    local host="$1" tag="$2"
    shift 2
    local out model
    out=$(_vllm_wrap_exec "$host" "/v1/models") || {
        echo "  FAIL: ${tag} /v1/models unreachable"; return 1
    }
    assert_contains "$out" "\"object\":\"list\"" "${tag} /v1/models openai shape" || return 1
    for model in "$@"; do
        assert_contains "$out" "$model" "${tag} /v1/models has ${model}" || return 1
    done
    echo "OK: ${tag} vllm_wrap_models_list"
}

_vllm_test_api_ps() {
    local host="$1" tag="$2"
    local out
    out=$(_vllm_wrap_exec "$host" "/api/ps") || {
        echo "  FAIL: ${tag} /api/ps unreachable"; return 1
    }
    assert_contains "$out" "models" "${tag} /api/ps has models field" || return 1
    echo "OK: ${tag} vllm_wrap_api_ps"
}

_vllm_test_unload_all() {
    local host="$1" tag="$2"
    _vllm_wrap_exec_method "$host" POST "/unload" >/dev/null || {
        echo "  FAIL: ${tag} POST /unload"; return 1
    }
    echo "OK: ${tag} vllm_wrap_unload_all"
}

_vllm_test_delete_unknown_returns_404() {
    local host="$1" tag="$2"
    local code
    code=$(_vllm_wrap_exec_status "$host" DELETE "/api/ps/qwen3-0.6b")
    case "$code" in
        200|404) ;;
        *)
            echo "  FAIL: ${tag} DELETE /api/ps/qwen3-0.6b unexpected status=$code"
            return 1
            ;;
    esac
    echo "OK: ${tag} vllm_wrap_delete_unknown_returns_404 (status=$code)"
}

# ── shared live assertions ─────────────────────────────────────────────────

_vllm_test_embed_live() {
    local alias="$1" tag="$2"
    local out
    out=$(curl -sf -m 1800 -X POST "$BASE_URL/v1/embeddings" \
        -H "$AUTH_HEADER" \
        -H "Content-Type: application/json" \
        -d "{\"model\": \"${alias}\", \"input\": \"The quick brown fox jumps over the lazy dog\"}") || {
        echo "  FAIL: ${tag} POST /v1/embeddings"; return 1
    }
    assert_contains "$out" "\"data\"" "${tag} response has data field" || return 1
    assert_contains "$out" "\"embedding\"" "${tag} response has embedding field" || return 1
    local dim
    dim=$(echo "$out" | jq -r '.data[0].embedding | length' 2>/dev/null || echo 0)
    [ "$dim" -gt 0 ] || {
        echo "  FAIL: ${tag} embedding vector empty (dim=$dim)"; return 1
    }
    echo "OK: ${tag} embed_live ${alias} (dim=$dim)"
}

_vllm_test_chat_live() {
    local alias="$1" tag="$2"
    local out
    out=$(curl -sf -m 1800 -X POST "$BASE_URL/v1/chat/completions" \
        -H "$AUTH_HEADER" \
        -H "Content-Type: application/json" \
        -d "{\"model\": \"${alias}\", \"messages\": [{\"role\": \"user\", \"content\": \"Reply with the single word PONG and nothing else.\"}], \"max_tokens\": 16}") || {
        echo "  FAIL: ${tag} POST /v1/chat/completions"; return 1
    }
    assert_contains "$out" "\"choices\"" "${tag} response has choices" || return 1
    local content
    content=$(echo "$out" | jq -r '.choices[0].message.content' 2>/dev/null || echo "")
    [ -n "$content" ] && [ "$content" != "null" ] || {
        echo "  FAIL: ${tag} empty chat content"; return 1
    }
    echo "OK: ${tag} chat_qwen3_live (content=\"${content:0:120}\")"
}

_VLLM_CPU_MODELS=(bge-m3 nomic-embed-v1.5 qwen3-0.6b)
_VLLM_CUDA_MODELS=(nomic-embed-v2 qwen3-0.6b)

# ── CPU variant ────────────────────────────────────────────────────────────

test_vllm_cpu_healthz()                       { _vllm_cpu_enabled || { echo "  SKIP: VLLM not enabled"; return 0; }; _vllm_test_healthz vllm "vllm-cpu" "${_VLLM_CPU_MODELS[@]}"; }
test_vllm_cpu_models_list()                   { _vllm_cpu_enabled || { echo "  SKIP: VLLM not enabled"; return 0; }; _vllm_test_models_list vllm "vllm-cpu" "${_VLLM_CPU_MODELS[@]}"; }
test_vllm_cpu_api_ps()                        { _vllm_cpu_enabled || { echo "  SKIP: VLLM not enabled"; return 0; }; _vllm_test_api_ps vllm "vllm-cpu"; }
test_vllm_cpu_unload_all()                    { _vllm_cpu_enabled || { echo "  SKIP: VLLM not enabled"; return 0; }; _vllm_test_unload_all vllm "vllm-cpu"; }
test_vllm_cpu_delete_unknown_returns_404()    { _vllm_cpu_enabled || { echo "  SKIP: VLLM not enabled"; return 0; }; _vllm_test_delete_unknown_returns_404 vllm "vllm-cpu"; }
test_vllm_cpu_embed_bge_m3_live()             { _vllm_cpu_enabled || { echo "  SKIP: VLLM not enabled"; return 0; }; _vllm_test_embed_live local-vllm-bge-m3 "vllm-cpu"; }
test_vllm_cpu_embed_nomic_v15_live()          { _vllm_cpu_enabled || { echo "  SKIP: VLLM not enabled"; return 0; }; _vllm_test_embed_live local-vllm-nomic-embed-v1.5 "vllm-cpu"; }
test_vllm_cpu_chat_qwen3_live()               { _vllm_cpu_enabled || { echo "  SKIP: VLLM not enabled"; return 0; }; _vllm_test_chat_live  local-vllm-qwen3-0.6b "vllm-cpu"; }

# ── CUDA variant ───────────────────────────────────────────────────────────

test_vllm_cuda_healthz()                      { _vllm_cuda_enabled || { echo "  SKIP: VLLM_CUDA not enabled"; return 0; }; _vllm_test_healthz vllm-cuda "vllm-cuda" "${_VLLM_CUDA_MODELS[@]}"; }
test_vllm_cuda_models_list()                  { _vllm_cuda_enabled || { echo "  SKIP: VLLM_CUDA not enabled"; return 0; }; _vllm_test_models_list vllm-cuda "vllm-cuda" "${_VLLM_CUDA_MODELS[@]}"; }
test_vllm_cuda_api_ps()                       { _vllm_cuda_enabled || { echo "  SKIP: VLLM_CUDA not enabled"; return 0; }; _vllm_test_api_ps vllm-cuda "vllm-cuda"; }
test_vllm_cuda_unload_all()                   { _vllm_cuda_enabled || { echo "  SKIP: VLLM_CUDA not enabled"; return 0; }; _vllm_test_unload_all vllm-cuda "vllm-cuda"; }
test_vllm_cuda_delete_unknown_returns_404()   { _vllm_cuda_enabled || { echo "  SKIP: VLLM_CUDA not enabled"; return 0; }; _vllm_test_delete_unknown_returns_404 vllm-cuda "vllm-cuda"; }
test_vllm_cuda_embed_nomic_live()             { _vllm_cuda_enabled || { echo "  SKIP: VLLM_CUDA not enabled"; return 0; }; _vllm_test_embed_live local-vllm-cuda-nomic-embed-v2 "vllm-cuda"; }
test_vllm_cuda_chat_qwen3_live()              { _vllm_cuda_enabled || { echo "  SKIP: VLLM_CUDA not enabled"; return 0; }; _vllm_test_chat_live  local-vllm-cuda-qwen3-0.6b "vllm-cuda"; }

ALL_TESTS+=(
    test_vllm_cpu_healthz
    test_vllm_cpu_models_list
    test_vllm_cpu_api_ps
    test_vllm_cpu_unload_all
    test_vllm_cpu_delete_unknown_returns_404
    test_vllm_cpu_embed_bge_m3_live
    test_vllm_cpu_embed_nomic_v15_live
    test_vllm_cpu_chat_qwen3_live
    test_vllm_cuda_healthz
    test_vllm_cuda_models_list
    test_vllm_cuda_api_ps
    test_vllm_cuda_unload_all
    test_vllm_cuda_delete_unknown_returns_404
    test_vllm_cuda_embed_nomic_live
    test_vllm_cuda_chat_qwen3_live
)
