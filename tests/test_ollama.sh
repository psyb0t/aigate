#!/bin/bash

# Skip entire file if OLLAMA not enabled
if [ "${OLLAMA:-}" != "1" ]; then
    return 0 2>/dev/null || true
fi

FIXTURES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.fixtures" && pwd)"

# ── models registered in LiteLLM ──────────────────────────────────────────

OLLAMA_EXPECTED_MODELS=(
    "ollama-cpu-llama3.2-3b"
    "ollama-cpu-qwen3-4b"
    "ollama-cpu-smollm2-1.7b"
    "ollama-cpu-qwen2.5-coder-1.5b"
    "ollama-cpu-qwen2.5-coder-3b"
    "ollama-cpu-phi3.5"
    "ollama-cpu-gemma3-4b"
    "ollama-cpu-nomic-embed"
    "ollama-cpu-bge-m3"
    "ollama-cpu-qwen3-embed-0.6b"
)

test_ollama_models_registered() {
    local models
    models=$(get "$BASE_URL/models")

    local m
    for m in "${OLLAMA_EXPECTED_MODELS[@]}"; do
        assert_contains "$models" "\"$m\"" "ollama model $m registered" || return 1
    done
    echo "OK: ollama_models_registered (${#OLLAMA_EXPECTED_MODELS[@]} models)"
}

# ── chat completion ────────────────────────────────────────────────────────

test_ollama_chat_completion() {
    local out
    out=$(curl -s --max-time 120 -X POST "$BASE_URL/chat/completions" \
        -H "Content-Type: application/json" \
        -H "$AUTH_HEADER" \
        -d '{"model":"ollama-cpu-smollm2-1.7b","messages":[{"role":"user","content":"respond with exactly the word LOCALPONG and nothing else"}]}')

    if echo "$out" | grep -qi "\"error\""; then
        echo "  FAIL: ollama chat error: $(echo "$out" | python3 -c 'import sys,json; d=json.load(sys.stdin); print(d.get("error",{}).get("message","?"))' 2>/dev/null)"
        return 1
    fi

    assert_contains "$out" "LOCALPONG" "ollama chat completion response" || return 1
    assert_contains "$out" "choices" "ollama chat has choices" || return 1
    assert_contains "$out" "usage" "ollama chat has usage" || return 1
    echo "OK: ollama_chat_completion"
}

# ── embedding ──────────────────────────────────────────────────────────────

test_ollama_embedding() {
    local out
    out=$(curl -s --max-time 120 -X POST "$BASE_URL/embeddings" \
        -H "Content-Type: application/json" \
        -H "$AUTH_HEADER" \
        -d '{"model":"ollama-cpu-nomic-embed","input":"hello world"}')

    if echo "$out" | grep -qi "\"error\""; then
        echo "  FAIL: ollama embedding error: $(echo "$out" | python3 -c 'import sys,json; d=json.load(sys.stdin); print(d.get("error",{}).get("message","?"))' 2>/dev/null)"
        return 1
    fi

    assert_contains "$out" "data" "ollama embedding has data" || return 1
    assert_contains "$out" "embedding" "ollama embedding has embedding" || return 1
    echo "OK: ollama_embedding"
}

# ── vision: gemma3-4b identifies cow in cow.jpg ───────────────────────────

test_ollama_gemma3_vision() {
    local fixture="$FIXTURES_DIR/cow.jpg"
    if [ ! -f "$fixture" ]; then
        echo "  SKIP: $fixture not found"
        echo "OK: ollama_gemma3-4b_vision (skipped)"
        return 0
    fi

    local b64
    b64=$(base64 -w 0 "$fixture")

    local out
    out=$(curl -s --max-time 180 -X POST "$BASE_URL/chat/completions" \
        -H "Content-Type: application/json" \
        -H "$AUTH_HEADER" \
        -d "{\"model\":\"ollama-cpu-gemma3-4b\",\"messages\":[{\"role\":\"user\",\"content\":[{\"type\":\"image_url\",\"image_url\":{\"url\":\"data:image/jpeg;base64,$b64\"}},{\"type\":\"text\",\"text\":\"What animal is in this image? Answer in one word.\"}]}]}")

    if echo "$out" | grep -qi "\"error\""; then
        echo "  FAIL: gemma3-4b error: $(echo "$out" | python3 -c 'import sys,json; d=json.load(sys.stdin); print(d.get("error",{}).get("message","?"))' 2>/dev/null)"
        return 1
    fi

    local content
    content=$(echo "$out" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['choices'][0]['message']['content'])" 2>/dev/null)
    echo "  gemma3-4b says: $content"

    assert_contains_icase "$content" "cow" "gemma3-4b identifies cow in image" || return 1
    echo "OK: ollama_gemma3-4b_vision"
}

ALL_TESTS+=(
    test_ollama_models_registered
    test_ollama_chat_completion
    test_ollama_embedding
    test_ollama_gemma3_vision
)

# ── GPU tests — only when GPU_NVIDIA=1 ───────────────────────────────────

if [ "${GPU_NVIDIA:-}" != "1" ]; then
    return 0 2>/dev/null || true
fi

OLLAMA_GPU_EXPECTED_MODELS=(
    "ollama-gpu-dolphin-mistral-7b"
    "ollama-gpu-qwen3-8b"
    "ollama-gpu-gemma3-12b"
    "ollama-gpu-qwen2.5-coder-7b"
    "ollama-gpu-llama3.1-8b"
)

test_ollama_gpu_models_registered() {
    local models
    models=$(get "$BASE_URL/models")

    local m
    for m in "${OLLAMA_GPU_EXPECTED_MODELS[@]}"; do
        assert_contains "$models" "\"$m\"" "ollama-gpu model $m registered" || return 1
    done
    echo "OK: ollama_gpu_models_registered (${#OLLAMA_GPU_EXPECTED_MODELS[@]} models)"
}

test_ollama_gpu_chat_completion() {
    local out
    out=$(curl -s --max-time 120 -X POST "$BASE_URL/chat/completions" \
        -H "Content-Type: application/json" \
        -H "$AUTH_HEADER" \
        -d '{"model":"ollama-gpu-llama3.1-8b","messages":[{"role":"user","content":"respond with exactly the word GPUPONG and nothing else"}]}')

    if echo "$out" | grep -qi "\"error\""; then
        echo "  FAIL: ollama-gpu chat error: $(echo "$out" | python3 -c 'import sys,json; d=json.load(sys.stdin); print(d.get("error",{}).get("message","?"))' 2>/dev/null)"
        return 1
    fi

    assert_contains "$out" "GPUPONG" "ollama-gpu chat completion response" || return 1
    assert_contains "$out" "choices" "ollama-gpu chat has choices" || return 1
    assert_contains "$out" "usage" "ollama-gpu chat has usage" || return 1
    echo "OK: ollama_gpu_chat_completion"
}

test_ollama_gpu_uncensored() {
    local out
    out=$(curl -s --max-time 120 -X POST "$BASE_URL/chat/completions" \
        -H "Content-Type: application/json" \
        -H "$AUTH_HEADER" \
        -d '{"model":"ollama-gpu-dolphin-mistral-7b","messages":[{"role":"user","content":"respond with exactly the word DOLPHINPONG and nothing else"}]}')

    if echo "$out" | grep -qi "\"error\""; then
        echo "  FAIL: dolphin-mistral error: $(echo "$out" | python3 -c 'import sys,json; d=json.load(sys.stdin); print(d.get("error",{}).get("message","?"))' 2>/dev/null)"
        return 1
    fi

    assert_contains_icase "$out" "DOLPHINPONG" "dolphin-mistral response" || return 1
    assert_contains "$out" "choices" "dolphin-mistral has choices" || return 1
    echo "OK: ollama_gpu_uncensored"
}

test_ollama_gpu_gemma3_vision() {
    local fixture="$FIXTURES_DIR/cow.jpg"
    if [ ! -f "$fixture" ]; then
        echo "  SKIP: $fixture not found"
        echo "OK: ollama_gpu_gemma3-12b_vision (skipped)"
        return 0
    fi

    local b64
    b64=$(base64 -w 0 "$fixture")

    local out
    out=$(curl -s --max-time 180 -X POST "$BASE_URL/chat/completions" \
        -H "Content-Type: application/json" \
        -H "$AUTH_HEADER" \
        -d "{\"model\":\"ollama-gpu-gemma3-12b\",\"messages\":[{\"role\":\"user\",\"content\":[{\"type\":\"image_url\",\"image_url\":{\"url\":\"data:image/jpeg;base64,$b64\"}},{\"type\":\"text\",\"text\":\"What animal is in this image? Answer in one word.\"}]}]}")

    if echo "$out" | grep -qi "\"error\""; then
        echo "  FAIL: gemma3-12b error: $(echo "$out" | python3 -c 'import sys,json; d=json.load(sys.stdin); print(d.get("error",{}).get("message","?"))' 2>/dev/null)"
        return 1
    fi

    local content
    content=$(echo "$out" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['choices'][0]['message']['content'])" 2>/dev/null)
    echo "  gemma3-12b says: $content"

    assert_contains_icase "$content" "cow" "gemma3-12b identifies cow in image" || return 1
    echo "OK: ollama_gpu_gemma3-12b_vision"
}

ALL_TESTS+=(
    test_ollama_gpu_models_registered
    test_ollama_gpu_chat_completion
    test_ollama_gpu_uncensored
    test_ollama_gpu_gemma3_vision
)
