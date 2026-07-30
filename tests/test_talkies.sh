#!/bin/bash

# ── talkies: gated on TALKIES=1 or TALKIES_CUDA=1 ─────────────────────────────
#
# Raw upstream APIs are available through nginx at /talkies/ and
# /talkies-cuda/. These tests cover both direct routes and the service's
# internal surface. Multipart uploads use the internal path so they do not
# depend on LiteLLM aliases.

_talkies_enabled() {
    [ "${TALKIES:-0}" = "1" ] || [ "${TALKIES_CUDA:-0}" = "1" ]
}

_talkies_cpu_enabled() { [ "${TALKIES:-0}" = "1" ]; }
_talkies_cuda_enabled() { [ "${TALKIES_CUDA:-0}" = "1" ]; }

_talkies_token() {
    case "$1" in
        cpu) echo "${TALKIES_AUTH_TOKEN:-${AIGATE_TOKEN:-}}" ;;
        cuda) echo "${TALKIES_CUDA_AUTH_TOKEN:-${AIGATE_TOKEN:-}}" ;;
    esac
}

_talkies_host() {
    if [ "${TALKIES_CUDA:-0}" = "1" ]; then
        echo "talkies-cuda"
        return
    fi
    echo "talkies"
}

_talkies_models_for_mode() {
    if [ "${TALKIES_CUDA:-0}" = "1" ]; then
        echo "whisper-large-v3 whisper-large-v3-turbo parakeet-tdt-0.6b-v3 canary-180m-flash canary-1b-flash canary-qwen-2.5b"
        return
    fi
    echo "whisper-large-v3 whisper-large-v3-turbo canary-180m-flash"
}

_talkies_exec_get() {
    local host
    local token
    host=$(_talkies_host)
    token=$(_talkies_token "$([ "${TALKIES_CUDA:-0}" = "1" ] && echo cuda || echo cpu)")
    docker compose exec -T litellm python3 -c "
import sys, urllib.request
req = urllib.request.Request('http://${host}:8000$1', headers={'Authorization': 'Bearer ${token}'})
sys.stdout.write(urllib.request.urlopen(req, timeout=15).read().decode())
"
}

_talkies_exec_method() {
    local method="$1" path="$2"
    local host
    local token
    host=$(_talkies_host)
    token=$(_talkies_token "$([ "${TALKIES_CUDA:-0}" = "1" ] && echo cuda || echo cpu)")
    docker compose exec -T litellm python3 -c "
import sys, urllib.request
req = urllib.request.Request('http://${host}:8000${path}', method='${method}', headers={'Authorization': 'Bearer ${token}'})
sys.stdout.write(urllib.request.urlopen(req, timeout=15).read().decode())
" 2>/dev/null
}

_talkies_exec_status() {
    local method="$1" path="$2"
    local host
    local token
    host=$(_talkies_host)
    token=$(_talkies_token "$([ "${TALKIES_CUDA:-0}" = "1" ] && echo cuda || echo cpu)")
    docker compose exec -T litellm python3 -c "
import urllib.request, urllib.error
try:
    urllib.request.urlopen(urllib.request.Request('http://${host}:8000${path}', method='${method}', headers={'Authorization': 'Bearer ${token}'}), timeout=15)
    print(200)
except urllib.error.HTTPError as e:
    print(e.code)
except Exception as e:
    sys.stderr.write('exc: '+repr(e)+'\n'); print(0)
"
}

# Upload a multipart audio file to /v1/audio/transcriptions on the talkies
# service. Uses litellm container's python (urllib) over aigate-internal.
# Args: $1=model, $2=fixture path on host, $3=response_format (default json),
# $4..$N=extra "key=value" form fields (e.g. "timestamp_granularities[]=word")
_talkies_transcribe() {
    local model="$1" fixture="$2" response_format="${3:-json}"
    shift 3
    local extras=("$@")
    local host
    local token
    host=$(_talkies_host)
    token=$(_talkies_token "$([ "${TALKIES_CUDA:-0}" = "1" ] && echo cuda || echo cpu)")

    local fname
    fname=$(basename "$fixture")
    local content_type="application/octet-stream"
    case "$fname" in
        *.wav)  content_type="audio/wav" ;;
        *.mp3)  content_type="audio/mpeg" ;;
        *.m4a)  content_type="audio/mp4" ;;
        *.flac) content_type="audio/flac" ;;
        *.ogg)  content_type="audio/ogg" ;;
    esac

    local extras_json="["
    local sep=""
    for kv in "${extras[@]}"; do
        local k="${kv%%=*}" v="${kv#*=}"
        extras_json+="${sep}{\"k\":\"${k}\",\"v\":\"${v}\"}"
        sep=","
    done
    extras_json+="]"

    cat "$fixture" | docker compose exec -T litellm python3 -c "
import json, os, sys, uuid, urllib.request, urllib.error
audio = sys.stdin.buffer.read()
boundary = uuid.uuid4().hex
parts = []
def add_field(name, value):
    parts.append(('--' + boundary + '\r\nContent-Disposition: form-data; name=\"' + name + '\"\r\n\r\n' + value + '\r\n').encode())
def add_file(name, filename, ctype, data):
    parts.append(('--' + boundary + '\r\nContent-Disposition: form-data; name=\"' + name + '\"; filename=\"' + filename + '\"\r\nContent-Type: ' + ctype + '\r\n\r\n').encode())
    parts.append(data)
    parts.append(b'\r\n')
add_field('model', '${model}')
add_field('response_format', '${response_format}')
for entry in json.loads('${extras_json}'):
    add_field(entry['k'], entry['v'])
add_file('file', '${fname}', '${content_type}', audio)
parts.append(('--' + boundary + '--\r\n').encode())
body = b''.join(parts)
req = urllib.request.Request(
    'http://${host}:8000/v1/audio/transcriptions',
    data=body,
    headers={'Content-Type': 'multipart/form-data; boundary=' + boundary, 'Authorization': 'Bearer ${token}'},
)
try:
    resp = urllib.request.urlopen(req, timeout=900)
    sys.stdout.write(resp.read().decode())
except urllib.error.HTTPError as e:
    sys.stderr.write('HTTP ' + str(e.code) + ': ' + e.read().decode() + '\n')
    sys.exit(1)
except Exception as e:
    sys.stderr.write('exc: ' + repr(e) + '\n')
    sys.exit(2)
"
}

_talkies_find_fixture() {
    local ext fixture=""
    for ext in wav mp3 m4a flac ogg; do
        if [ -f "tests/.fixtures/audio.${ext}" ]; then
            fixture="tests/.fixtures/audio.${ext}"
            break
        fi
    done
    echo "$fixture"
}

# ── Direct nginx routes — CPU/CUDA independently gated by profile ────────────

_talkies_test_direct_healthz() {
    local prefix="$1" tag="$2"
    local out
    out=$(curl -sf -m 30 "$BASE_URL${prefix}/healthz" 2>/dev/null) || {
        echo "  FAIL: ${tag} ${prefix}/healthz"; return 1
    }
    assert_contains "$out" '"ok":true' "${tag} direct healthz" || return 1
    echo "OK: ${tag} direct_healthz"
}

_talkies_test_direct_requires_auth() {
    local prefix="$1" tag="$2"
    local code
    code=$(curl -s -m 30 -o /dev/null -w "%{http_code}" "$BASE_URL${prefix}/v1/models")
    case "$code" in
        401|403) ;;
        *)
            echo "  FAIL: ${tag} ${prefix}/v1/models without auth expected 401/403, got $code"
            return 1
            ;;
    esac
    echo "OK: ${tag} direct_requires_auth (status=$code)"
}

_talkies_test_direct_models() {
    local prefix="$1" variant="$2" tag="$3"
    local token out
    token=$(_talkies_token "$variant")
    [ -n "$token" ] || { echo "  FAIL: ${tag} missing direct-route token"; return 1; }
    out=$(curl -sf -m 30 "$BASE_URL${prefix}/v1/models" \
        -H "Authorization: Bearer $token" 2>/dev/null) || {
        echo "  FAIL: ${tag} ${prefix}/v1/models with auth"; return 1
    }
    assert_contains "$out" '"object":"list"' "${tag} direct models OpenAI shape" || return 1
    assert_contains "$out" '"whisper-large-v3"' "${tag} direct models preserves upstream slug" || return 1
    echo "OK: ${tag} direct_models"
}

_talkies_test_websocket_upgrade() {
    local prefix="$1" variant="$2" tag="$3"
    local token
    token=$(_talkies_token "$variant")
    [ -n "$token" ] || { echo "  FAIL: ${tag} missing WebSocket token"; return 1; }
    if ! TALKIES_TEST_URL="$BASE_URL${prefix}/v1/audio/transcriptions/stream" \
        TALKIES_TEST_TOKEN="$token" python3 - <<'PY'
import base64
import os
import socket
import ssl
from urllib.parse import urlsplit

url = urlsplit(os.environ["TALKIES_TEST_URL"])
scheme = url.scheme.lower()
if scheme not in {"http", "https", "ws", "wss"}:
    raise SystemExit(f"unsupported URL scheme: {scheme}")
port = url.port or (443 if scheme in {"https", "wss"} else 80)
path = (url.path or "/") + (f"?{url.query}" if url.query else "")
host = url.hostname
if not host:
    raise SystemExit("missing WebSocket host")
sock = socket.create_connection((host, port), timeout=15)
if scheme in {"https", "wss"}:
    context = ssl.create_default_context()
    sock = context.wrap_socket(sock, server_hostname=host)
key = base64.b64encode(os.urandom(16)).decode("ascii")
request = (
    f"GET {path} HTTP/1.1\r\n"
    f"Host: {url.netloc}\r\n"
    "Upgrade: websocket\r\n"
    "Connection: Upgrade\r\n"
    f"Sec-WebSocket-Key: {key}\r\n"
    "Sec-WebSocket-Version: 13\r\n"
    f"Authorization: Bearer {os.environ['TALKIES_TEST_TOKEN']}\r\n\r\n"
)
sock.sendall(request.encode("ascii"))
response = sock.recv(4096).decode("iso-8859-1", "replace")
sock.close()
status = response.split("\r\n", 1)[0]
if not status.startswith("HTTP/1.1 101 "):
    raise SystemExit(f"expected WebSocket 101, got {status}")
PY
    then
        echo "  FAIL: ${tag} live-ASR WebSocket upgrade"
        return 1
    fi
    echo "OK: ${tag} live_asr_websocket_upgrade"
}

_talkies_test_route_hidden() {
    local prefix="$1" tag="$2"
    local code
    code=$(curl -s -m 30 -o /dev/null -w "%{http_code}" "$BASE_URL${prefix}/healthz")
    [ "$code" = "404" ] || {
        echo "  FAIL: ${tag} disabled route expected 404, got $code"
        return 1
    }
    echo "OK: ${tag} disabled_route_hidden"
}

test_talkies_cpu_direct_healthz()          { _talkies_cpu_enabled || { echo "  SKIP: TALKIES not enabled"; return 0; }; _talkies_test_direct_healthz /talkies "talkies-cpu"; }
test_talkies_cpu_direct_requires_auth()    { _talkies_cpu_enabled || { echo "  SKIP: TALKIES not enabled"; return 0; }; _talkies_test_direct_requires_auth /talkies "talkies-cpu"; }
test_talkies_cpu_direct_models()           { _talkies_cpu_enabled || { echo "  SKIP: TALKIES not enabled"; return 0; }; _talkies_test_direct_models /talkies cpu "talkies-cpu"; }
test_talkies_cpu_live_asr_websocket()      { _talkies_cpu_enabled || { echo "  SKIP: TALKIES not enabled"; return 0; }; _talkies_test_websocket_upgrade /talkies cpu "talkies-cpu"; }
test_talkies_cpu_route_hidden_when_off()   { _talkies_cpu_enabled && { echo "  SKIP: TALKIES enabled"; return 0; }; _talkies_test_route_hidden /talkies "talkies-cpu"; }

test_talkies_cuda_direct_healthz()         { _talkies_cuda_enabled || { echo "  SKIP: TALKIES_CUDA not enabled"; return 0; }; _talkies_test_direct_healthz /talkies-cuda "talkies-cuda"; }
test_talkies_cuda_direct_requires_auth()   { _talkies_cuda_enabled || { echo "  SKIP: TALKIES_CUDA not enabled"; return 0; }; _talkies_test_direct_requires_auth /talkies-cuda "talkies-cuda"; }
test_talkies_cuda_direct_models()          { _talkies_cuda_enabled || { echo "  SKIP: TALKIES_CUDA not enabled"; return 0; }; _talkies_test_direct_models /talkies-cuda cuda "talkies-cuda"; }
test_talkies_cuda_live_asr_websocket()     { _talkies_cuda_enabled || { echo "  SKIP: TALKIES_CUDA not enabled"; return 0; }; _talkies_test_websocket_upgrade /talkies-cuda cuda "talkies-cuda"; }
test_talkies_cuda_route_hidden_when_off()  { _talkies_cuda_enabled && { echo "  SKIP: TALKIES_CUDA enabled"; return 0; }; _talkies_test_route_hidden /talkies-cuda "talkies-cuda"; }

# ── /healthz reachable, returns device + configured model_ids ─────────────────

test_talkies_healthz() {
    _talkies_enabled || { echo "  SKIP: TALKIES not enabled"; return 0; }
    local out
    out=$(_talkies_exec_get "/healthz") || { echo "  FAIL: /healthz unreachable"; return 1; }
    assert_contains "$out" "\"ok\":true" "/healthz ok=true" || return 1
    assert_contains "$out" "canary-180m-flash" "/healthz lists canary-180m-flash" || return 1
    assert_contains "$out" "whisper-large-v3" "/healthz lists whisper-large-v3" || return 1
    echo "OK: talkies_healthz"
}

# ── /v1/models lists every configured model_id ────────────────────────────────

test_talkies_models_list() {
    _talkies_enabled || { echo "  SKIP: TALKIES not enabled"; return 0; }
    local out mid
    out=$(_talkies_exec_get "/v1/models") || { echo "  FAIL: /v1/models unreachable"; return 1; }
    assert_contains "$out" "\"object\":\"list\"" "/v1/models openai shape" || return 1
    for mid in $(_talkies_models_for_mode); do
        assert_contains "$out" "\"$mid\"" "/v1/models has $mid" || return 1
    done
    echo "OK: talkies_models_list"
}

# ── /api/ps responds, may be empty before first request ───────────────────────

test_talkies_api_ps() {
    _talkies_enabled || { echo "  SKIP: TALKIES not enabled"; return 0; }
    local out
    out=$(_talkies_exec_get "/api/ps") || { echo "  FAIL: /api/ps unreachable"; return 1; }
    assert_contains "$out" "models" "/api/ps has models field (speaches-compat shape)" || return 1
    echo "OK: talkies_api_ps"
}

# ── POST /unload always 200 ───────────────────────────────────────────────────

test_talkies_unload_all() {
    _talkies_enabled || { echo "  SKIP: TALKIES not enabled"; return 0; }
    _talkies_exec_method POST "/unload" >/dev/null || { echo "  FAIL: POST /unload"; return 1; }
    echo "OK: talkies_unload_all"
}

# ── Per-model: plain json transcription returns non-empty text ────────────────

test_talkies_transcribe_each_model_json() {
    _talkies_enabled || { echo "  SKIP: TALKIES not enabled"; return 0; }
    local fixture
    fixture=$(_talkies_find_fixture)
    [ -n "$fixture" ] || { echo "  SKIP: tests/.fixtures/audio.* missing"; return 0; }

    local mid out text rc=0
    for mid in $(_talkies_models_for_mode); do
        out=$(_talkies_transcribe "$mid" "$fixture" "json") || {
            echo "  FAIL: $mid json transcribe"
            rc=1
            continue
        }
        text=$(echo "$out" | jq -r '.text' 2>/dev/null || echo "")
        if [ -z "$text" ] || [ "$text" = "null" ]; then
            echo "  FAIL: $mid empty text in json response"
            rc=1
            continue
        fi
        echo "  ok: $mid text=\"$(echo "$text" | head -c 80)\""
    done
    [ $rc -eq 0 ] && echo "OK: talkies_transcribe_each_model_json"
    return $rc
}

# ── verbose_json: backends that support timestamps return segments + words ────

test_talkies_transcribe_each_model_verbose_json() {
    _talkies_enabled || { echo "  SKIP: TALKIES not enabled"; return 0; }
    local fixture
    fixture=$(_talkies_find_fixture)
    [ -n "$fixture" ] || { echo "  SKIP: tests/.fixtures/audio.* missing"; return 0; }

    local mid out rc=0 segs words
    for mid in $(_talkies_models_for_mode); do
        out=$(_talkies_transcribe "$mid" "$fixture" "verbose_json" \
            "timestamp_granularities[]=segment" "timestamp_granularities[]=word") || {
            echo "  FAIL: $mid verbose_json transcribe"
            rc=1
            continue
        }
        assert_contains "$out" "\"task\":" "$mid verbose_json has task" || { rc=1; continue; }
        assert_contains "$out" "\"language\":" "$mid verbose_json has language" || { rc=1; continue; }
        assert_contains "$out" "\"duration\":" "$mid verbose_json has duration" || { rc=1; continue; }
        assert_contains "$out" "\"segments\":" "$mid verbose_json has segments" || { rc=1; continue; }
        assert_contains "$out" "\"words\":" "$mid verbose_json has words" || { rc=1; continue; }
        segs=$(echo "$out" | jq '.segments | length' 2>/dev/null || echo 0)
        words=$(echo "$out" | jq '.words | length' 2>/dev/null || echo 0)
        # canary-qwen-2.5b (SALM) has no timestamp head: empty arrays OK, schema must still validate.
        if [ "$mid" = "canary-qwen-2.5b" ]; then
            echo "  ok: $mid (SALM, segments=$segs words=$words)"
            continue
        fi
        if [ "$segs" -lt 1 ]; then
            echo "  FAIL: $mid expected >=1 segment, got $segs"
            rc=1
            continue
        fi
        echo "  ok: $mid segments=$segs words=$words"
    done
    [ $rc -eq 0 ] && echo "OK: talkies_transcribe_each_model_verbose_json"
    return $rc
}

# ── srt subtitle format works for every backend ───────────────────────────────

test_talkies_transcribe_each_model_srt() {
    _talkies_enabled || { echo "  SKIP: TALKIES not enabled"; return 0; }
    local fixture
    fixture=$(_talkies_find_fixture)
    [ -n "$fixture" ] || { echo "  SKIP: tests/.fixtures/audio.* missing"; return 0; }

    local mid out rc=0
    for mid in $(_talkies_models_for_mode); do
        out=$(_talkies_transcribe "$mid" "$fixture" "srt") || {
            echo "  FAIL: $mid srt transcribe"
            rc=1
            continue
        }
        if ! echo "$out" | grep -q -- "-->"; then
            echo "  FAIL: $mid srt missing timestamp arrows"
            rc=1
            continue
        fi
        echo "  ok: $mid srt"
    done
    [ $rc -eq 0 ] && echo "OK: talkies_transcribe_each_model_srt"
    return $rc
}

# ── DELETE /api/ps/{unknown} returns 404 ─────────────────────────────────────

test_talkies_delete_unknown_returns_404() {
    _talkies_enabled || { echo "  SKIP: TALKIES not enabled"; return 0; }
    local code
    code=$(_talkies_exec_status DELETE "/api/ps/nonexistent-model")
    case "$code" in
        404) ;;
        *)
            echo "  FAIL: DELETE /api/ps/nonexistent-model expected 404, got $code"
            return 1
            ;;
    esac
    echo "OK: talkies_delete_unknown_returns_404"
}

ALL_TESTS+=(
    test_talkies_cpu_direct_healthz
    test_talkies_cpu_direct_requires_auth
    test_talkies_cpu_direct_models
    test_talkies_cpu_live_asr_websocket
    test_talkies_cpu_route_hidden_when_off
    test_talkies_cuda_direct_healthz
    test_talkies_cuda_direct_requires_auth
    test_talkies_cuda_direct_models
    test_talkies_cuda_live_asr_websocket
    test_talkies_cuda_route_hidden_when_off
    test_talkies_healthz
    test_talkies_models_list
    test_talkies_api_ps
    test_talkies_unload_all
    test_talkies_delete_unknown_returns_404
    test_talkies_transcribe_each_model_json
    test_talkies_transcribe_each_model_verbose_json
    test_talkies_transcribe_each_model_srt
)
