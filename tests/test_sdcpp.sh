#!/bin/bash

# Skip entire file if SDCPP not enabled
if [ "${SDCPP:-}" != "1" ]; then
    return 0 2>/dev/null || true
fi

# ── helpers ────────────────────────────────────────────────────────────────────

_sdcpp_get() {
    local url="$1"
    local timeout="${2:-120}"
    docker compose -f "$WORKDIR/docker-compose.yml" exec -T litellm \
        python3 -c "
import urllib.request, os
r = urllib.request.urlopen('${url}', timeout=${timeout})
d = r.read()
os.write(1, d)
" 2>/dev/null
}

_sdcpp_post() {
    local url="$1"
    local timeout="${2:-120}"
    docker compose -f "$WORKDIR/docker-compose.yml" exec -T litellm \
        python3 -c "
import urllib.request, os
req = urllib.request.Request('${url}', data=b'', method='POST')
r = urllib.request.urlopen(req, timeout=${timeout})
d = r.read()
os.write(1, d)
" 2>/dev/null
}

_sdcpp_generate_direct() {
    local base_url="$1" model_key="$2" timeout="${3:-600}"
    docker compose -f "$WORKDIR/docker-compose.yml" exec -T litellm \
        python3 -c "
import urllib.request, urllib.error, json, os, sys
body = json.dumps({
    'model': '${model_key}',
    'prompt': 'a solid blue circle',
    'size': '256x256',
    'response_format': 'b64_json'
}).encode()
req = urllib.request.Request('${base_url}/v1/images/generations', data=body, method='POST', headers={'Content-Type': 'application/json'})
try:
    r = urllib.request.urlopen(req, timeout=${timeout})
    d = r.read()
except urllib.error.HTTPError as e:
    d = e.read()
except Exception as e:
    sys.stderr.write(str(e) + '\n')
    sys.exit(1)
os.write(1, d)
sys.stdout.flush()
" 2>/dev/null
}

_sdcpp_wait_idle() {
    local base_url="$1" max_wait="${2:-30}"
    local elapsed=0
    while [ "$elapsed" -lt "$max_wait" ]; do
        local status generating
        status=$(_sdcpp_get "$base_url/sdcpp/v1/status" 10)
        generating=$(echo "$status" | python3 -c "import sys,json; print(json.load(sys.stdin)['generating'])" 2>/dev/null)
        [ "$generating" = "False" ] && return 0
        sleep 2
        elapsed=$((elapsed + 2))
    done
    return 1
}

_sdcpp_force_unload() {
    local base_url="$1"
    local _try
    for _try in 1 2 3; do
        _sdcpp_post "$base_url/sdcpp/v1/cancel" 10 >/dev/null 2>&1
        _sdcpp_wait_idle "$base_url" 10
        _sdcpp_post "$base_url/sdcpp/v1/unload" 300 >/dev/null 2>&1
        local status loaded
        status=$(_sdcpp_get "$base_url/sdcpp/v1/status" 10)
        loaded=$(echo "$status" | python3 -c "import sys,json; print(json.load(sys.stdin)['loaded'])" 2>/dev/null)
        [ "$loaded" = "False" ] && return 0
        sleep 2
    done
    return 1
}

# ── shared test logic (called with variant-specific vars) ──────────────────────

_sdcpp_test_model_registered() {
    local prefix="$1" default_model="$2" label="$3"
    local models
    models=$(get "$BASE_URL/models")
    assert_contains "$models" "\"$default_model\"" \
        "$label model $default_model registered in LiteLLM" || return 1
    echo "OK: ${label}_model_registered ($default_model)"
}

_sdcpp_test_server_health() {
    local base_url="$1" label="$2"
    local out
    out=$(_sdcpp_get "$base_url/health")
    assert_not_empty "$out" "$label wrapper health responds" || return 1
    assert_contains "$out" '"ok"' "$label wrapper health returns ok" || return 1
    echo "OK: ${label}_server_health"
}

_sdcpp_test_models_list() {
    local base_url="$1" label="$2"
    shift 2
    local expected_models=("$@")

    local out
    out=$(_sdcpp_get "$base_url/v1/models")
    assert_not_empty "$out" "$label v1/models responds" || return 1

    for m in "${expected_models[@]}"; do
        assert_contains "$out" "\"$m\"" "$label models list contains $m" || return 1
    done
    echo "OK: ${label}_models_list"
}

_sdcpp_test_status() {
    local base_url="$1" label="$2"
    local out
    out=$(_sdcpp_get "$base_url/sdcpp/v1/status")
    assert_not_empty "$out" "$label status responds" || return 1
    assert_contains "$out" '"idle_timeout"' "$label status has idle_timeout" || return 1
    assert_contains "$out" '"supports_img"' "$label status has supports_img" || return 1
    assert_contains "$out" '"loaded"' "$label status has loaded field" || return 1
    assert_contains "$out" '"generating"' "$label status has generating field" || return 1
    assert_contains "$out" '"process_running"' "$label status has process_running" || return 1
    assert_contains "$out" '"process_pid"' "$label status has process_pid" || return 1
    assert_contains "$out" '"models"' "$label status has models field" || return 1
    echo "OK: ${label}_status"
}

_sdcpp_test_unload() {
    local base_url="$1" label="$2"
    _sdcpp_force_unload "$base_url"
    local status_out loaded
    status_out=$(_sdcpp_get "$base_url/sdcpp/v1/status")
    loaded=$(echo "$status_out" | python3 -c "import sys,json; print(json.load(sys.stdin)['loaded'])" 2>/dev/null)
    assert_eq "$loaded" "False" "$label ctx unloaded" || return 1
    echo "OK: ${label}_unload"
}

_sdcpp_test_double_unload() {
    local base_url="$1" label="$2"
    _sdcpp_force_unload "$base_url"
    local out
    out=$(_sdcpp_post "$base_url/sdcpp/v1/unload" 300)
    assert_contains "$out" '"already_unloaded"' "$label double unload idempotent" || return 1
    echo "OK: ${label}_double_unload"
}

_sdcpp_test_auto_load_on_generate() {
    local base_url="$1" default_model="$2" label="$3"
    # strip prefix so the wrapper can resolve the key directly
    local model_key="${default_model#*-cpu-}"
    model_key="${model_key#*-cuda-}"
    _sdcpp_force_unload "$base_url"
    # drain any orphaned requests from previous runs
    sleep 3
    _sdcpp_force_unload "$base_url"

    local status_before loaded_before
    status_before=$(_sdcpp_get "$base_url/sdcpp/v1/status")
    loaded_before=$(echo "$status_before" | python3 -c "import sys,json; print(json.load(sys.stdin)['loaded'])" 2>/dev/null)
    assert_eq "$loaded_before" "False" "$label starts unloaded" || return 1

    # Call the wrapper directly (not through LiteLLM) to avoid router retry storms
    # Retry once on transient errors (BAD_GATEWAY from orphaned requests killing sd-server)
    local out _gen_try
    for _gen_try in 1 2; do
        out=$(_sdcpp_generate_direct "$base_url" "$model_key" 600)
        _sdcpp_wait_idle "$base_url" 120
        if echo "$out" | grep -qi "BAD_GATEWAY"; then
            echo "  WARN: $label got BAD_GATEWAY (attempt $_gen_try), retrying..."
            _sdcpp_force_unload "$base_url"
            sleep 2
            continue
        fi
        break
    done

    if echo "$out" | grep -qi "\"error\""; then
        echo "  FAIL: $label generation error: $(echo "$out" | python3 -c 'import sys,json; d=json.load(sys.stdin); print(d.get("error",{}).get("message",d.get("error","?")))' 2>/dev/null)"
        return 1
    fi

    assert_contains "$out" '"b64_json"' "$label response contains b64_json" || return 1
    assert_contains "$out" '"data"' "$label response contains data array" || return 1

    local status_after loaded_after _try
    for _try in 1 2 3 4 5; do
        status_after=$(_sdcpp_get "$base_url/sdcpp/v1/status" 30)
        loaded_after=$(echo "$status_after" | python3 -c "import sys,json; print(json.load(sys.stdin)['loaded'])" 2>/dev/null)
        [ "$loaded_after" = "True" ] && break
        sleep 2
    done
    assert_eq "$loaded_after" "True" "$label ctx loaded after generation" || return 1
    echo "OK: ${label}_auto_load_on_generate"
}

_sdcpp_test_image_generation() {
    local base_url="$1" default_model="$2" label="$3"
    # strip prefix to get wrapper key (e.g. local-sdcpp-cpu-sd-turbo → sd-turbo)
    local model_key="${default_model#*-cpu-}"
    model_key="${model_key#*-cuda-}"

    _sdcpp_wait_idle "$base_url" 120
    local out
    out=$(_sdcpp_generate_direct "$base_url" "$model_key" 600)
    _sdcpp_wait_idle "$base_url" 120

    if echo "$out" | grep -qi "\"error\""; then
        echo "  FAIL: $label generation error: $(echo "$out" | python3 -c 'import sys,json; d=json.load(sys.stdin); print(d.get("error",{}).get("message",d.get("error","?")))' 2>/dev/null)"
        return 1
    fi

    assert_contains "$out" '"b64_json"' "$label response has b64_json" || return 1

    local b64_len
    b64_len=$(echo "$out" | python3 -c "
import sys, json
d = json.load(sys.stdin)
data = d.get('data', [])
if data:
    print(len(data[0].get('b64_json', '')))
else:
    print(0)
" 2>/dev/null)

    if [ "${b64_len:-0}" -lt 1000 ]; then
        echo "  FAIL: $label b64_json too short ($b64_len chars)"
        return 1
    fi
    echo "  OK: b64_json length=$b64_len"
    echo "OK: ${label}_image_generation"
}

_sdcpp_test_model_swap() {
    local base_url="$1" alt_model="$2" alt_key="$3" label="$4"

    _sdcpp_wait_idle "$base_url" 120
    local out
    out=$(_sdcpp_generate_direct "$base_url" "$alt_key" 600)
    _sdcpp_wait_idle "$base_url" 120

    if echo "$out" | grep -qi "\"error\""; then
        echo "  FAIL: $label swap error: $(echo "$out" | python3 -c 'import sys,json; d=json.load(sys.stdin); print(d.get("error",{}).get("message",d.get("error","?")))' 2>/dev/null)"
        return 1
    fi

    assert_contains "$out" '"b64_json"' "$label swap response has b64_json" || return 1
    echo "OK: ${label}_model_swap"
}

_sdcpp_test_double_load() {
    local base_url="$1" label="$2" default_model="$3"
    local out
    out=$(_sdcpp_post "$base_url/sdcpp/v1/load?model=$default_model" 300)
    assert_not_empty "$out" "$label load responds" || return 1

    local out2
    out2=$(_sdcpp_post "$base_url/sdcpp/v1/load?model=$default_model" 60)
    assert_contains "$out2" '"already_loaded"' "$label double load idempotent" || return 1
    echo "OK: ${label}_double_load"
}

_sdcpp_test_cleanup_unload() {
    local base_url="$1" label="$2"
    _sdcpp_force_unload "$base_url"

    local status_out loaded
    status_out=$(_sdcpp_get "$base_url/sdcpp/v1/status")
    loaded=$(echo "$status_out" | python3 -c "import sys,json; print(json.load(sys.stdin)['loaded'])" 2>/dev/null)
    assert_eq "$loaded" "False" "$label ctx unloaded after cleanup" || return 1
    echo "OK: ${label}_cleanup_unload"
}

# ── CPU variant ────────────────────────────────────────────────────────────────

SDCPP_CPU_URL="http://sdcpp:7234"
SDCPP_CPU_PREFIX="local-sdcpp-cpu-"
SDCPP_CPU_DEFAULT="${SDCPP_CPU_PREFIX}sd-turbo"
SDCPP_CPU_ALT="${SDCPP_CPU_PREFIX}sdxl-turbo"
SDCPP_CPU_MODELS=(
    "${SDCPP_CPU_PREFIX}sdxl-turbo"
    "${SDCPP_CPU_PREFIX}sd-turbo"
)

test_sdcpp_cpu_model_registered()      { _sdcpp_test_model_registered "$SDCPP_CPU_PREFIX" "$SDCPP_CPU_DEFAULT" "sdcpp-cpu"; }
test_sdcpp_cpu_server_health()         { _sdcpp_test_server_health "$SDCPP_CPU_URL" "sdcpp-cpu"; }
test_sdcpp_cpu_models_list()           { _sdcpp_test_models_list "$SDCPP_CPU_URL" "sdcpp-cpu" "${SDCPP_CPU_MODELS[@]}"; }
test_sdcpp_cpu_status()                { _sdcpp_test_status "$SDCPP_CPU_URL" "sdcpp-cpu"; }
test_sdcpp_cpu_unload()                { _sdcpp_test_unload "$SDCPP_CPU_URL" "sdcpp-cpu"; }
test_sdcpp_cpu_double_unload()         { _sdcpp_test_double_unload "$SDCPP_CPU_URL" "sdcpp-cpu"; }
test_sdcpp_cpu_auto_load_on_generate() { _sdcpp_test_auto_load_on_generate "$SDCPP_CPU_URL" "$SDCPP_CPU_DEFAULT" "sdcpp-cpu"; }
test_sdcpp_cpu_image_generation()      { _sdcpp_test_image_generation "$SDCPP_CPU_URL" "$SDCPP_CPU_DEFAULT" "sdcpp-cpu"; }
test_sdcpp_cpu_model_swap()            { _sdcpp_test_model_swap "$SDCPP_CPU_URL" "$SDCPP_CPU_ALT" "sdxl-turbo" "sdcpp-cpu"; }
test_sdcpp_cpu_double_load()           { _sdcpp_test_double_load "$SDCPP_CPU_URL" "sdcpp-cpu" "sd-turbo"; }
test_sdcpp_cpu_cleanup_unload()        { _sdcpp_test_cleanup_unload "$SDCPP_CPU_URL" "sdcpp-cpu"; }

ALL_TESTS+=(
    test_sdcpp_cpu_model_registered
    test_sdcpp_cpu_server_health
    test_sdcpp_cpu_models_list
    test_sdcpp_cpu_status
    test_sdcpp_cpu_unload
    test_sdcpp_cpu_double_unload
    test_sdcpp_cpu_auto_load_on_generate
    test_sdcpp_cpu_image_generation
    test_sdcpp_cpu_model_swap
    test_sdcpp_cpu_double_load
    test_sdcpp_cpu_cleanup_unload
)

# ── CUDA variant (only when SDCPP_CUDA=1) ─────────────────────────────────────

if [ "${SDCPP_CUDA:-}" = "1" ]; then

SDCPP_CUDA_URL="http://sdcpp-cuda:7234"
SDCPP_CUDA_PREFIX="local-sdcpp-cuda-"
SDCPP_CUDA_DEFAULT="${SDCPP_CUDA_PREFIX}sd-turbo"
SDCPP_CUDA_ALT="${SDCPP_CUDA_PREFIX}sdxl-turbo"
SDCPP_CUDA_MODELS=(
    "${SDCPP_CUDA_PREFIX}flux-schnell"
    "${SDCPP_CUDA_PREFIX}sdxl-lightning"
    "${SDCPP_CUDA_PREFIX}sdxl-turbo"
    "${SDCPP_CUDA_PREFIX}sd-turbo"
    "${SDCPP_CUDA_PREFIX}juggernaut-xi"
)

test_sdcpp_cuda_model_registered()      { _sdcpp_test_model_registered "$SDCPP_CUDA_PREFIX" "$SDCPP_CUDA_DEFAULT" "sdcpp-cuda"; }
test_sdcpp_cuda_server_health()         { _sdcpp_test_server_health "$SDCPP_CUDA_URL" "sdcpp-cuda"; }
test_sdcpp_cuda_models_list()           { _sdcpp_test_models_list "$SDCPP_CUDA_URL" "sdcpp-cuda" "${SDCPP_CUDA_MODELS[@]}"; }
test_sdcpp_cuda_status()                { _sdcpp_test_status "$SDCPP_CUDA_URL" "sdcpp-cuda"; }
test_sdcpp_cuda_unload()                { _sdcpp_test_unload "$SDCPP_CUDA_URL" "sdcpp-cuda"; }
test_sdcpp_cuda_double_unload()         { _sdcpp_test_double_unload "$SDCPP_CUDA_URL" "sdcpp-cuda"; }
test_sdcpp_cuda_auto_load_on_generate() { _sdcpp_test_auto_load_on_generate "$SDCPP_CUDA_URL" "$SDCPP_CUDA_DEFAULT" "sdcpp-cuda"; }
test_sdcpp_cuda_image_generation()      { _sdcpp_test_image_generation "$SDCPP_CUDA_URL" "$SDCPP_CUDA_DEFAULT" "sdcpp-cuda"; }
test_sdcpp_cuda_model_swap()            { _sdcpp_test_model_swap "$SDCPP_CUDA_URL" "$SDCPP_CUDA_ALT" "sdxl-turbo" "sdcpp-cuda"; }
test_sdcpp_cuda_double_load()           { _sdcpp_test_double_load "$SDCPP_CUDA_URL" "sdcpp-cuda" "sd-turbo"; }
test_sdcpp_cuda_cleanup_unload()        { _sdcpp_test_cleanup_unload "$SDCPP_CUDA_URL" "sdcpp-cuda"; }

ALL_TESTS+=(
    test_sdcpp_cuda_model_registered
    test_sdcpp_cuda_server_health
    test_sdcpp_cuda_models_list
    test_sdcpp_cuda_status
    test_sdcpp_cuda_unload
    test_sdcpp_cuda_double_unload
    test_sdcpp_cuda_auto_load_on_generate
    test_sdcpp_cuda_image_generation
    test_sdcpp_cuda_model_swap
    test_sdcpp_cuda_double_load
    test_sdcpp_cuda_cleanup_unload
)

fi
