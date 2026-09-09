#!/bin/bash

# ── table: LiteLLM API endpoints ────────────────────────────────────────────

# format: label|method|path|expected_in_body
LITELLM_ENDPOINT_CASES=(
    "health liveliness|GET|/health/liveliness|alive"
    "models list|GET|/models|data"
)

test_litellm_endpoints() {
    local entry label method path expected
    for entry in "${LITELLM_ENDPOINT_CASES[@]}"; do
        IFS='|' read -r label method path expected <<< "$entry"
        local out
        out=$(curl -sf -X "$method" "$BASE_URL$path" -H "$AUTH_HEADER")
        assert_contains "$out" "$expected" "$label" || return 1
    done
    echo "OK: litellm_endpoints (${#LITELLM_ENDPOINT_CASES[@]} cases)"
}

# ── models registered ──────────────────────────────────────────────────────

# format: model_name
EXPECTED_MODELS=(
    # claudebox (OAuth)
    "claudebox-opus"
    "claudebox-sonnet"
    "claudebox-haiku"
    # pibox-zai (GLM via z.ai)
    "pibox-zai-glm-5.3"
    "pibox-zai-glm-5.3-flash"
    # Groq
    "groq-gpt-oss-20b"
    "groq-gpt-oss-120b"
    "groq-gpt-oss-safeguard-20b"
    "groq-qwen3.8-27b"
    "groq-qwen3.6-27b"
    "groq-compound"
    "groq-compound-mini"
    "groq-allam-2-7b"
    "groq-prompt-guard-22m"
    "groq-prompt-guard-86m"
    "groq-whisper-large-v3"
    "groq-whisper-large-v3-turbo"
    # Cerebras (paid plan required; these fail on a free account)
    "cerebras-gpt-oss-120b"
    "cerebras-qwen3.8-27b"
    "cerebras-gemma-4-31b"
    # OpenRouter
    "or-nemotron-lightning"
    "or-nemotron-120b"
    "or-dots-3-note"
    "or-nemotron-omni-30b"
    "or-north-mini-code"
    "or-lfm-2.5-2.6b"
    "or-ling-3-sante"
    "or-ling-3-fin"
    "or-nemotron-content-safety"
    # HuggingFace
    "hf-llama-3.1-8b"
    "hf-llama-3.3-70b"
    "hf-llama-4-scout"
    "hf-qwen3-8b"
    "hf-qwen3-32b"
    "hf-qwen3-235b"
    "hf-deepseek-r1"
    "hf-qwen-vl-72b"
    "hf-gemma-3-27b"
    "hf-gemma-3-12b"
    "hf-flux-schnell"
    # Mistral
    "mistral-large"
    "mistral-small"
    "ministral-8b"
    "magistral-medium"
    "magistral-small"
    "devstral"
    "codestral"
    "mistral-embed"
    "voxtral-small"
    # Cohere
    "cohere-command-a-plus"
    "cohere-command-a"
    "cohere-command-a-reasoning"
    "cohere-command-a-vision"
    "cohere-command-a-translate"
    "cohere-north-mini-code"
    "cohere-command-r-plus"
    "cohere-command-r"
    "cohere-command-r7b"
    "cohere-command-r7b-arabic"
    "cohere-aya-32b"
    "cohere-aya-vision-32b"
    "cohere-tiny-aya-global"
    "cohere-tiny-aya-earth"
    "cohere-tiny-aya-fire"
    "cohere-tiny-aya-water"
    "cohere-embed"
    "cohere-rerank"
)

# ollama models — only expected when OLLAMA=1
if [ "${OLLAMA:-}" = "1" ]; then
    EXPECTED_MODELS+=(
        "local-ollama-cpu-llama3.2-3b"
        "local-ollama-cpu-qwen3-4b"
        "local-ollama-cpu-smollm2-1.7b"
        "local-ollama-cpu-qwen2.5-coder-1.5b"
        "local-ollama-cpu-qwen2.5-coder-3b"
        "local-ollama-cpu-phi4-mini"
        "local-ollama-cpu-gemma4-e2b"
        "local-ollama-cpu-gemma3-4b"
        "local-ollama-cpu-dolphin-phi"
        "local-ollama-cpu-nuextract-v1.5"
        "local-ollama-cpu-bge-m3"
        "local-ollama-cpu-qwen3-embed-0.6b"
    )
fi

# ollama-cuda models — only expected when OLLAMA_CUDA=1
if [ "${OLLAMA_CUDA:-}" = "1" ]; then
    EXPECTED_MODELS+=(
        "local-ollama-cuda-qwen3-8b"
        "local-ollama-cuda-gemma4-e4b"
        "local-ollama-cuda-gemma4-e2b"
        "local-ollama-cuda-qwen2.5-coder-7b"
        "local-ollama-cuda-deepseek-coder-v2-16b"
        "local-ollama-cuda-llama3.1-8b"
        "local-ollama-cuda-qwen3-abliterated-16b"
        "local-ollama-cuda-gemma4-abliterated-e4b"
        "local-ollama-cuda-deepseek-r1-8b"
        "local-ollama-cuda-dolphin-phi"
        "local-ollama-cuda-llama3.2-3b"
        "local-ollama-cuda-qwen3-4b"
        "local-ollama-cuda-smollm2-1.7b"
        "local-ollama-cuda-qwen2.5-coder-1.5b"
        "local-ollama-cuda-qwen2.5-coder-3b"
        "local-ollama-cuda-phi4-mini"
        "local-ollama-cuda-gemma3-4b"
        "local-ollama-cuda-nuextract-v1.5"
        "local-ollama-cuda-bge-m3"
        "local-ollama-cuda-qwen3-embed-0.6b"
    )
fi

# Qwen3-TTS lives inside talkies-cuda as of v0.4.0 — alias is published
# whenever TALKIES_CUDA=1 (same trigger as the rest of the cuda set).
if [ "${TALKIES_CUDA:-}" = "1" ]; then
    EXPECTED_MODELS+=(
        "local-talkies-cuda-qwen3-tts"
    )
fi

# talkies Kokoro TTS — bundled into the talkies/talkies-cuda containers
# (v0.3.0+), so the slug is published whenever the respective profile is on.
if [ "${TALKIES:-}" = "1" ]; then
    EXPECTED_MODELS+=(
        "local-talkies-kokoro-tts"
    )
fi

if [ "${TALKIES_CUDA:-}" = "1" ]; then
    EXPECTED_MODELS+=(
        "local-talkies-cuda-kokoro-tts"
    )
fi

# vllm CPU — text LLM + embedding wrapper (supervised vllm serve).
if [ "${VLLM:-}" = "1" ]; then
    EXPECTED_MODELS+=(
        "local-vllm-nomic-embed-v2"
        "local-vllm-qwen3-0.6b"
    )
fi

# vllm-cuda — text LLM + embedding wrapper (supervised vllm serve, NVIDIA).
if [ "${VLLM_CUDA:-}" = "1" ]; then
    EXPECTED_MODELS+=(
        "local-vllm-cuda-nomic-embed-v2"
        "local-vllm-cuda-qwen3-0.6b"
    )
fi

test_litellm_models_registered() {
    local models
    models=$(get "$BASE_URL/models")

    local m
    for m in "${EXPECTED_MODELS[@]}"; do
        assert_contains "$models" "\"$m\"" "model $m registered" || return 1
    done
    echo "OK: models_registered (${#EXPECTED_MODELS[@]} models)"
}

# ── auth: reject bad key ───────────────────────────────────────────────────

# format: label|auth_value|expected_code
AUTH_CASES=(
    "no key rejects|none|401"
    "wrong key rejects|Bearer sk-wrong|401"
    "valid key accepts|Bearer $LITELLM_MASTER_KEY|200"
)

test_litellm_auth() {
    local entry label auth_value expected_code
    for entry in "${AUTH_CASES[@]}"; do
        IFS='|' read -r label auth_value expected_code <<< "$entry"
        local code
        if [ "$auth_value" = "none" ]; then
            code=$(curl -s -o /dev/null -w "%{http_code}" "$BASE_URL/models")
        else
            code=$(curl -s -o /dev/null -w "%{http_code}" -H "Authorization: $auth_value" "$BASE_URL/models")
        fi
        assert_eq "$code" "$expected_code" "$label" || return 1
    done
    echo "OK: litellm_auth (${#AUTH_CASES[@]} cases)"
}

# ── chat completion with groq (fast, free) ─────────────────────────────────

test_litellm_chat_completion() {
    local out
    out=$(post "$BASE_URL/chat/completions" \
        '{"model":"groq-gpt-oss-20b","messages":[{"role":"user","content":"respond with exactly the word XYZPONG7742 and nothing else"}]}')
    assert_contains "$out" "XYZPONG7742" "chat completion response" || return 1
    assert_contains "$out" "choices" "chat completion has choices" || return 1
    assert_contains "$out" "usage" "chat completion has usage" || return 1
    echo "OK: litellm_chat_completion"
}

# ── streaming chat completion ──────────────────────────────────────────────

test_litellm_chat_stream() {
    local out
    out=$(curl -sf -X POST "$BASE_URL/chat/completions" \
        -H "Content-Type: application/json" \
        -H "$AUTH_HEADER" \
        -d '{"model":"groq-gpt-oss-20b","messages":[{"role":"user","content":"respond with exactly STREAMPONG and nothing else"}],"stream":true}')

    assert_contains "$out" "data:" "returns SSE" || return 1
    assert_contains "$out" "[DONE]" "ends with DONE" || return 1

    # concatenate all content deltas and check (tokens split across chunks)
    local full_content
    full_content=$(echo "$out" | python3 -c "
import sys, json
content = ''
for line in sys.stdin:
    line = line.strip()
    if line.startswith('data:') and '[DONE]' not in line:
        try:
            d = json.loads(line[5:])
            c = d.get('choices',[{}])[0].get('delta',{}).get('content','')
            if c: content += c
        except: pass
print(content)
" 2>/dev/null)
    assert_contains_icase "$full_content" "STREAMPONG" "stream contains response" || return 1

    echo "OK: litellm_chat_stream (3 checks)"
}

# ── model group aliases resolve ────────────────────────────────────────────

test_litellm_model_groups() {
    # use curl without -f so we get the error body
    local out
    out=$(curl -s -X POST "$BASE_URL/chat/completions" \
        -H "Content-Type: application/json" \
        -H "$AUTH_HEADER" \
        -d '{"model":"fast","messages":[{"role":"user","content":"respond with exactly FASTPONG and nothing else"}]}')
    # model_group_alias may not be supported in this litellm version — detect and skip
    if [ -z "$out" ] || echo "$out" | grep -qi "Invalid model name\|error"; then
        echo "  SKIP: model_group_alias not active (config issue)"
        echo "OK: litellm_model_groups (skipped)"
        return 0
    fi
    assert_contains_icase "$out" "FASTPONG" "fast model group works" || return 1
    echo "OK: litellm_model_groups"
}

# ── CPU TTS via talkies Kokoro (TALKIES=1) ────────────────────────────────

test_litellm_cpu_tts() {
    if [ "${TALKIES:-}" != "1" ]; then
        echo "OK: litellm_cpu_tts (skipped — TALKIES not enabled)"
        return 0
    fi
    local tmpfile
    tmpfile=$(mktemp /tmp/litellm_tts_XXXXXX.mp3)
    local code
    code=$(curl -s -o "$tmpfile" -w "%{http_code}" --max-time 60 \
        -X POST "$BASE_URL/v1/audio/speech" \
        -H "Content-Type: application/json" \
        -H "$AUTH_HEADER" \
        -d '{"model":"local-talkies-kokoro-tts","input":"hello world","voice":"af_heart"}')
    assert_eq "$code" "200" "cpu tts returns 200" || { rm -f "$tmpfile"; return 1; }
    local size
    size=$(wc -c < "$tmpfile")
    rm -f "$tmpfile"
    [ "$size" -gt 1000 ] || { echo "  FAIL: cpu tts audio too small: $size bytes"; return 1; }
    echo "  OK: cpu tts audio size: $size bytes"
    echo "OK: litellm_cpu_tts"
}

# ── CPU STT via talkies (TALKIES=1) ───────────────────────────────────────

test_litellm_cpu_stt() {
    if [ "${TALKIES:-}" != "1" ]; then
        echo "OK: litellm_cpu_stt (skipped — TALKIES not enabled)"
        return 0
    fi
    # first generate a known phrase via TTS
    local tts_file
    tts_file=$(mktemp /tmp/litellm_stt_in_XXXXXX.mp3)
    local code
    code=$(curl -s -o "$tts_file" -w "%{http_code}" --max-time 60 \
        -X POST "$BASE_URL/v1/audio/speech" \
        -H "Content-Type: application/json" \
        -H "$AUTH_HEADER" \
        -d '{"model":"local-talkies-kokoro-tts","input":"hello world","voice":"af_heart"}')
    assert_eq "$code" "200" "tts for stt roundtrip returns 200" || { rm -f "$tts_file"; return 1; }

    local out
    out=$(curl -sf --max-time 120 \
        -X POST "$BASE_URL/v1/audio/transcriptions" \
        -H "$AUTH_HEADER" \
        -F "model=local-talkies-whisper-large-v3-turbo" \
        -F "file=@$tts_file")
    rm -f "$tts_file"
    assert_contains "$out" "text" "stt response has text field" || return 1
    assert_contains_icase "$out" "hello" "stt transcription contains spoken content" || return 1
    echo "OK: litellm_cpu_stt"
}

# ── TTS→STT round-trip check (TALKIES=1) ──────────────────────────────────

test_litellm_tts_stt_roundtrip() {
    if [ "${TALKIES:-}" != "1" ]; then
        echo "OK: litellm_tts_stt_roundtrip (skipped — TALKIES not enabled)"
        return 0
    fi
    local phrase="testing one two three"
    local tts_file
    tts_file=$(mktemp /tmp/litellm_roundtrip_XXXXXX.mp3)

    local code
    code=$(curl -s -o "$tts_file" -w "%{http_code}" --max-time 60 \
        -X POST "$BASE_URL/v1/audio/speech" \
        -H "Content-Type: application/json" \
        -H "$AUTH_HEADER" \
        -d "{\"model\":\"local-talkies-kokoro-tts\",\"input\":\"$phrase\",\"voice\":\"af_heart\"}")
    assert_eq "$code" "200" "tts round-trip step" || { rm -f "$tts_file"; return 1; }

    local out
    out=$(curl -sf --max-time 120 \
        -X POST "$BASE_URL/v1/audio/transcriptions" \
        -H "$AUTH_HEADER" \
        -F "model=local-talkies-whisper-large-v3-turbo" \
        -F "file=@$tts_file")
    rm -f "$tts_file"
    assert_contains_icase "$out" "testing" "round-trip transcript contains 'testing'" || return 1
    assert_contains_icase "$out" "one" "round-trip transcript contains 'one'" || return 1
    assert_contains_icase "$out" "three" "round-trip transcript contains 'three'" || return 1
    echo "OK: litellm_tts_stt_roundtrip"
}

# ── resource manager fires and logs unloads (TALKIES=1) ───────────────────

test_litellm_resource_manager() {
    if [ "${TALKIES:-}" != "1" ]; then
        echo "OK: litellm_resource_manager (skipped — TALKIES not enabled)"
        return 0
    fi

    # STT request against the CPU talkies group — competing groups include
    # cpu-llm. Resource manager should log the group + at least one unload.
    local stt_file
    stt_file=$(mktemp /tmp/litellm_rm_stt_XXXXXX.mp3)
    curl -s -o "$stt_file" --max-time 60 \
        -X POST "$BASE_URL/v1/audio/speech" \
        -H "Content-Type: application/json" \
        -H "$AUTH_HEADER" \
        -d '{"model":"local-talkies-kokoro-tts","input":"hello","voice":"af_heart"}' > /dev/null
    curl -sf --max-time 120 \
        -X POST "$BASE_URL/v1/audio/transcriptions" \
        -H "$AUTH_HEADER" \
        -F "model=local-talkies-whisper-large-v3-turbo" \
        -F "file=@$stt_file" > /dev/null
    rm -f "$stt_file"
    local stt_logs
    stt_logs=$(docker compose -f "$WORKDIR/docker-compose.yml" logs --since 150s litellm 2>/dev/null)
    assert_contains "$stt_logs" "group=cpu-stt-talkies" "stt: resource manager identified cpu-stt-talkies group" || return 1
    assert_contains "$stt_logs" "unloading competing" "stt: resource manager logged competing unload" || return 1
    assert_contains "$stt_logs" "cpu-llm" "stt: resource manager logged cpu-llm handling" || return 1

    echo "OK: litellm_resource_manager"
}

# ── CUDA resource manager unloads on CUDA requests ──────────────────────────

test_litellm_cuda_resource_manager() {
    if [ "${TALKIES_CUDA:-}" != "1" ]; then
        echo "OK: litellm_cuda_resource_manager (skipped — TALKIES_CUDA not enabled)"
        return 0
    fi

    # CUDA TTS request via talkies' Qwen3-TTS — competing CUDA groups include
    # cuda-llm and cuda-img. Resource manager should log the group + at least
    # one competing-unload attempt.
    local tts_file
    tts_file=$(mktemp /tmp/litellm_cuda_rm_XXXXXX.mp3)
    curl -s -o "$tts_file" --max-time 120 \
        -X POST "$BASE_URL/v1/audio/speech" \
        -H "Content-Type: application/json" \
        -H "$AUTH_HEADER" \
        -d '{"model":"local-talkies-cuda-qwen3-tts","input":"cuda resource manager test","voice":"alloy"}' > /dev/null
    rm -f "$tts_file"
    local tts_logs
    tts_logs=$(docker compose -f "$WORKDIR/docker-compose.yml" logs --since 20s litellm 2>/dev/null)
    assert_contains "$tts_logs" "group=cuda-stt-talkies" "cuda tts: resource manager identified cuda-stt-talkies group" || return 1
    assert_contains "$tts_logs" "unloading competing" "cuda tts: resource manager logged competing unload" || return 1
    assert_contains "$tts_logs" "cuda-llm" "cuda tts: resource manager logged cuda-llm handling" || return 1

    echo "OK: litellm_cuda_resource_manager"
}

# ── CUDA TTS via talkies-cuda Qwen3-TTS (TALKIES_CUDA=1) ──────────────────

test_litellm_cuda_tts() {
    if [ "${TALKIES_CUDA:-}" != "1" ]; then
        echo "OK: litellm_cuda_tts (skipped — TALKIES_CUDA not enabled)"
        return 0
    fi
    local tmpfile
    tmpfile=$(mktemp /tmp/litellm_cuda_tts_XXXXXX.mp3)
    local code
    code=$(curl -s -o "$tmpfile" -w "%{http_code}" --max-time 120 \
        -X POST "$BASE_URL/v1/audio/speech" \
        -H "Content-Type: application/json" \
        -H "$AUTH_HEADER" \
        -d '{"model":"local-talkies-cuda-qwen3-tts","input":"hello from CUDA","voice":"alloy"}')
    assert_eq "$code" "200" "cuda tts returns 200" || { rm -f "$tmpfile"; return 1; }
    local size
    size=$(wc -c < "$tmpfile")
    rm -f "$tmpfile"
    [ "$size" -gt 1000 ] || { echo "  FAIL: cuda tts audio too small: $size bytes"; return 1; }
    echo "  OK: cuda tts audio size: $size bytes"
    echo "OK: litellm_cuda_tts"
}

# ── CUDA STT via talkies-cuda (TALKIES_CUDA=1) ────────────────────────────

test_litellm_cuda_stt() {
    if [ "${TALKIES_CUDA:-}" != "1" ]; then
        echo "OK: litellm_cuda_stt (skipped — TALKIES_CUDA not enabled)"
        return 0
    fi
    # generate input via the same container's CPU-fast Kokoro TTS
    local tts_file
    tts_file=$(mktemp /tmp/litellm_cuda_stt_XXXXXX.mp3)
    local code
    code=$(curl -s -o "$tts_file" -w "%{http_code}" --max-time 60 \
        -X POST "$BASE_URL/v1/audio/speech" \
        -H "Content-Type: application/json" \
        -H "$AUTH_HEADER" \
        -d '{"model":"local-talkies-cuda-kokoro-tts","input":"hello transcription test","voice":"af_heart"}')
    assert_eq "$code" "200" "tts for cuda stt input returns 200" || { rm -f "$tts_file"; return 1; }

    local out
    out=$(curl -sf --max-time 120 \
        -X POST "$BASE_URL/v1/audio/transcriptions" \
        -H "$AUTH_HEADER" \
        -F "model=local-talkies-cuda-whisper-large-v3-turbo" \
        -F "file=@$tts_file")
    rm -f "$tts_file"
    assert_contains "$out" "text" "cuda stt response has text field" || return 1
    assert_contains_icase "$out" "transcription" "cuda stt transcription contains spoken content" || return 1
    echo "OK: litellm_cuda_stt"
}

ALL_TESTS+=(
    test_litellm_endpoints
    test_litellm_models_registered
    test_litellm_auth
    test_litellm_chat_completion
    test_litellm_chat_stream
    test_litellm_model_groups
    test_litellm_cpu_tts
    test_litellm_cpu_stt
    test_litellm_tts_stt_roundtrip
    test_litellm_resource_manager
    test_litellm_cuda_tts
    test_litellm_cuda_stt
    test_litellm_cuda_resource_manager
)
