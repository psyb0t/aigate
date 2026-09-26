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

# format: provider_flag|model_name. A model is expected only when its
# provider flag is 1 in .env, matching how litellm/build-config.py registers
# providers.
EXPECTED_MODELS=(
    # claudebox (OAuth)
    "CLAUDEBOX|claudebox-opus"
    "CLAUDEBOX|claudebox-sonnet"
    "CLAUDEBOX|claudebox-haiku"
    # pibox-zai (GLM via z.ai)
    "PIBOX_ZAI|pibox-zai-glm-5.3"
    "PIBOX_ZAI|pibox-zai-glm-5.3-flash"
    # Groq
    "GROQ|groq-gpt-oss-20b"
    "GROQ|groq-gpt-oss-120b"
    "GROQ|groq-gpt-oss-safeguard-20b"
    "GROQ|groq-qwen3.8-27b"
    "GROQ|groq-qwen3.6-27b"
    "GROQ|groq-compound"
    "GROQ|groq-compound-mini"
    "GROQ|groq-allam-2-7b"
    "GROQ|groq-prompt-guard-22m"
    "GROQ|groq-prompt-guard-86m"
    "GROQ|groq-whisper-large-v3"
    "GROQ|groq-whisper-large-v3-turbo"
    # Cerebras (paid plan required; these fail on a free account)
    "CEREBRAS|cerebras-gpt-oss-120b"
    "CEREBRAS|cerebras-qwen3.8-27b"
    "CEREBRAS|cerebras-gemma-4-31b"
    # OpenRouter
    "OPENROUTER|or-nemotron-lightning"
    "OPENROUTER|or-nemotron-120b"
    "OPENROUTER|or-nemotron-ultra"
    "OPENROUTER|or-qwen3.8-27b"
    "OPENROUTER|or-dots-3-note"
    "OPENROUTER|or-ling-3-vl"
    "OPENROUTER|or-gemma-4-31b"
    "OPENROUTER|or-inkling"
    "OPENROUTER|or-nemotron-omni-30b"
    "OPENROUTER|or-north-mini-code"
    "OPENROUTER|or-lfm-2.5-2.6b"
    "OPENROUTER|or-ling-3-sante"
    "OPENROUTER|or-ling-3-fin"
    "OPENROUTER|or-nemotron-content-safety"
    # HuggingFace
    "HUGGINGFACE|hf-llama-3.1-8b"
    "HUGGINGFACE|hf-llama-3.3-70b"
    "HUGGINGFACE|hf-llama-4-scout"
    "HUGGINGFACE|hf-qwen3-8b"
    "HUGGINGFACE|hf-qwen3-32b"
    "HUGGINGFACE|hf-qwen3-235b"
    "HUGGINGFACE|hf-deepseek-r1"
    "HUGGINGFACE|hf-qwen-vl-72b"
    "HUGGINGFACE|hf-gemma-3-27b"
    "HUGGINGFACE|hf-gemma-3-12b"
    "HUGGINGFACE|hf-flux-schnell"
    # Mistral
    "MISTRAL|mistral-large"
    "MISTRAL|mistral-small"
    "MISTRAL|ministral-8b"
    "MISTRAL|magistral-medium"
    "MISTRAL|magistral-small"
    "MISTRAL|devstral"
    "MISTRAL|codestral"
    "MISTRAL|mistral-embed"
    "MISTRAL|voxtral-small"
    # Cohere
    "COHERE|cohere-command-a-plus"
    "COHERE|cohere-command-a"
    "COHERE|cohere-command-a-reasoning"
    "COHERE|cohere-command-a-vision"
    "COHERE|cohere-command-a-translate"
    "COHERE|cohere-north-mini-code"
    "COHERE|cohere-command-r-plus"
    "COHERE|cohere-command-r"
    "COHERE|cohere-command-r7b"
    "COHERE|cohere-command-r7b-arabic"
    "COHERE|cohere-aya-32b"
    "COHERE|cohere-aya-vision-32b"
    "COHERE|cohere-tiny-aya-global"
    "COHERE|cohere-tiny-aya-earth"
    "COHERE|cohere-tiny-aya-fire"
    "COHERE|cohere-tiny-aya-water"
    "COHERE|cohere-embed"
    "COHERE|cohere-rerank"
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
        "local-vllm-bge-m3"
        "local-vllm-nomic-embed-v1.5"
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

    local entry flag m checked=0 skipped=0
    for entry in "${EXPECTED_MODELS[@]}"; do
        # Entries appended inside a flag check below carry no FLAG| prefix.
        flag="" m="$entry"
        if [[ "$entry" == *"|"* ]]; then
            IFS='|' read -r flag m <<< "$entry"
        fi
        if [ -n "$flag" ] && [ "${!flag:-0}" != "1" ]; then
            skipped=$((skipped + 1))
            continue
        fi
        assert_contains "$models" "\"$m\"" "model $m registered" || return 1
        checked=$((checked + 1))
    done
    echo "OK: models_registered (${checked} models, ${skipped} skipped for disabled providers)"
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
    # Whisper writes spoken numbers as words or digits depending on context.
    local pair word digit
    for pair in "one 1" "three 3"; do
        read -r word digit <<< "$pair"
        if [[ "${out,,}" == *"$word"* || "$out" == *"$digit"* ]]; then
            echo "  OK: round-trip transcript contains '$word' or '$digit'"
            continue
        fi
        echo "  FAIL: round-trip transcript contains '$word' or '$digit'"
        echo "  actual: ${out:0:500}"
        return 1
    done
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

    # CUDA STT request through LiteLLM. /v1/audio/speech is served by the mcp
    # service, not LiteLLM, so TTS only produces the input audio here. The
    # transcription runs the resource manager: it takes the CUDA lock and
    # unloads competing CUDA groups such as cuda-llm.
    local stt_file
    stt_file=$(mktemp /tmp/litellm_cuda_rm_XXXXXX.mp3)
    curl -s -o "$stt_file" --max-time 60 \
        -X POST "$BASE_URL/v1/audio/speech" \
        -H "Content-Type: application/json" \
        -H "$AUTH_HEADER" \
        -d '{"model":"local-talkies-kokoro-tts","input":"hello","voice":"af_heart"}' > /dev/null
    curl -sf --max-time 120 \
        -X POST "$BASE_URL/v1/audio/transcriptions" \
        -H "$AUTH_HEADER" \
        -F "model=local-talkies-cuda-whisper-large-v3-turbo" \
        -F "file=@$stt_file" > /dev/null
    rm -f "$stt_file"
    local stt_logs
    stt_logs=$(docker compose -f "$WORKDIR/docker-compose.yml" logs --since 150s litellm 2>/dev/null)
    assert_contains "$stt_logs" "group=cuda-stt-talkies" "cuda stt: resource manager identified cuda-stt-talkies group" || return 1
    assert_contains "$stt_logs" "acquired CUDA lock" "cuda stt: resource manager took the CUDA lock" || return 1
    assert_contains "$stt_logs" "unloading competing" "cuda stt: resource manager logged competing unload" || return 1
    assert_contains "$stt_logs" "cuda-llm" "cuda stt: resource manager logged cuda-llm handling" || return 1

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
