#!/bin/bash

# Skip entire file if OLLAMA not enabled
if [ "${OLLAMA:-}" != "1" ]; then
    return 0 2>/dev/null || true
fi

FIXTURES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.fixtures" && pwd)"

# ── models registered in LiteLLM ──────────────────────────────────────────

OLLAMA_EXPECTED_MODELS=(
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
        -d '{"model":"local-ollama-cpu-smollm2-1.7b","messages":[{"role":"user","content":"respond with exactly the word LOCALPONG and nothing else"}]}')

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
        -d '{"model":"local-ollama-cpu-bge-m3","input":"hello world"}')

    if echo "$out" | grep -qi "\"error\""; then
        echo "  FAIL: ollama embedding error: $(echo "$out" | python3 -c 'import sys,json; d=json.load(sys.stdin); print(d.get("error",{}).get("message","?"))' 2>/dev/null)"
        return 1
    fi

    assert_contains "$out" "data" "ollama embedding has data" || return 1
    assert_contains "$out" "embedding" "ollama embedding has embedding" || return 1
    echo "OK: ollama_embedding"
}

# ── vision: gemma4-e2b identifies cow in cow.jpg ───────────────────────────

test_ollama_gemma4_vision() {
    local fixture="$FIXTURES_DIR/cow.jpg"
    if [ ! -f "$fixture" ]; then
        echo "  SKIP: $fixture not found"
        echo "OK: ollama_gemma4-e2b_vision (skipped)"
        return 0
    fi

    local b64
    b64=$(base64 -w 0 "$fixture")

    local out
    out=$(curl -s --max-time 180 -X POST "$BASE_URL/chat/completions" \
        -H "Content-Type: application/json" \
        -H "$AUTH_HEADER" \
        -d "{\"model\":\"local-ollama-cpu-gemma4-e2b\",\"messages\":[{\"role\":\"user\",\"content\":[{\"type\":\"image_url\",\"image_url\":{\"url\":\"data:image/jpeg;base64,$b64\"}},{\"type\":\"text\",\"text\":\"What animal is in this image? Answer in one word.\"}]}]}")

    if echo "$out" | grep -qi "\"error\""; then
        echo "  FAIL: gemma4-e2b error: $(echo "$out" | python3 -c 'import sys,json; d=json.load(sys.stdin); print(d.get("error",{}).get("message","?"))' 2>/dev/null)"
        return 1
    fi

    local content
    content=$(echo "$out" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['choices'][0]['message']['content'])" 2>/dev/null)
    echo "  gemma4-e2b says: $content"

    assert_contains_icase "$content" "cow" "gemma4-e2b identifies cow in image" || return 1
    echo "OK: ollama_gemma4-e2b_vision"
}

# ── nuextract: unstructured text → structured JSON ────────────────────────

test_ollama_nuextract() {
    local out
    out=$(curl -s --max-time 180 -X POST "$BASE_URL/chat/completions" \
        -H "Content-Type: application/json" \
        -H "$AUTH_HEADER" \
        -d '{
            "model": "local-ollama-cpu-nuextract-v1.5",
            "messages": [
                {
                    "role": "user",
                    "content": "Extract the following fields as JSON: name, age, city.\n\nText: John Smith is 34 years old and lives in Berlin.\n\nRespond with valid JSON only."
                }
            ]
        }')

    if echo "$out" | grep -qi "\"error\""; then
        echo "  FAIL: nuextract error: $(echo "$out" | python3 -c 'import sys,json; d=json.load(sys.stdin); print(d.get("error",{}).get("message","?"))' 2>/dev/null)"
        return 1
    fi

    local content
    content=$(echo "$out" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['choices'][0]['message']['content'])" 2>/dev/null)
    echo "  nuextract says: $content"

    assert_contains_icase "$content" "john" "nuextract extracts name" || return 1
    assert_contains "$content" "34" "nuextract extracts age" || return 1
    assert_contains_icase "$content" "berlin" "nuextract extracts city" || return 1
    echo "OK: ollama_nuextract"
}

ALL_TESTS+=(
    test_ollama_models_registered
    test_ollama_chat_completion
    test_ollama_embedding
    test_ollama_gemma4_vision
    test_ollama_nuextract
)

# ── CUDA tests — only when OLLAMA_CUDA=1 ─────────────────────────────────

if [ "${OLLAMA_CUDA:-}" != "1" ]; then
    return 0 2>/dev/null || true
fi

OLLAMA_CUDA_EXPECTED_MODELS=(
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

test_ollama_cuda_models_registered() {
    local models
    models=$(get "$BASE_URL/models")

    local m
    for m in "${OLLAMA_CUDA_EXPECTED_MODELS[@]}"; do
        assert_contains "$models" "\"$m\"" "ollama-cuda model $m registered" || return 1
    done
    echo "OK: ollama_cuda_models_registered (${#OLLAMA_CUDA_EXPECTED_MODELS[@]} models)"
}

test_ollama_cuda_chat_completion() {
    local out
    out=$(curl -s --max-time 120 -X POST "$BASE_URL/chat/completions" \
        -H "Content-Type: application/json" \
        -H "$AUTH_HEADER" \
        -d '{"model":"local-ollama-cuda-dolphin-phi","messages":[{"role":"user","content":"respond with exactly the word CUDAPONG and nothing else"}]}')

    if echo "$out" | grep -qi "\"error\""; then
        echo "  FAIL: ollama-cuda chat error: $(echo "$out" | python3 -c 'import sys,json; d=json.load(sys.stdin); print(d.get("error",{}).get("message","?"))' 2>/dev/null)"
        return 1
    fi

    assert_contains "$out" "CUDAPONG" "ollama-cuda chat completion response" || return 1
    assert_contains "$out" "choices" "ollama-cuda chat has choices" || return 1
    assert_contains "$out" "usage" "ollama-cuda chat has usage" || return 1
    echo "OK: ollama_cuda_chat_completion"
}

test_ollama_cuda_uncensored() {
    local out
    out=$(curl -s --max-time 120 -X POST "$BASE_URL/chat/completions" \
        -H "Content-Type: application/json" \
        -H "$AUTH_HEADER" \
        -d '{"model":"local-ollama-cuda-qwen3-abliterated-16b","messages":[{"role":"user","content":"respond with exactly the word ABLITPONG and nothing else"}]}')

    if echo "$out" | grep -qi "\"error\""; then
        echo "  FAIL: qwen3-abliterated error: $(echo "$out" | python3 -c 'import sys,json; d=json.load(sys.stdin); print(d.get("error",{}).get("message","?"))' 2>/dev/null)"
        return 1
    fi

    assert_contains_icase "$out" "ABLITPONG" "qwen3-abliterated response" || return 1
    assert_contains "$out" "choices" "qwen3-abliterated has choices" || return 1
    echo "OK: ollama_cuda_uncensored"
}

test_ollama_cuda_dolphin_phi() {
    local out
    out=$(curl -s --max-time 120 -X POST "$BASE_URL/chat/completions" \
        -H "Content-Type: application/json" \
        -H "$AUTH_HEADER" \
        -d '{"model":"local-ollama-cuda-dolphin-phi","messages":[{"role":"user","content":"say hello"}]}')

    if echo "$out" | grep -qi "\"error\""; then
        echo "  FAIL: dolphin-phi error: $(echo "$out" | python3 -c 'import sys,json; d=json.load(sys.stdin); print(d.get("error",{}).get("message","?"))' 2>/dev/null)"
        return 1
    fi

    assert_contains "$out" "choices" "dolphin-phi responds" || return 1
    echo "OK: ollama_cuda_dolphin_phi"
}

test_ollama_cuda_gemma4_vision() {
    local fixture="$FIXTURES_DIR/cow.jpg"
    if [ ! -f "$fixture" ]; then
        echo "  SKIP: $fixture not found"
        echo "OK: ollama_cuda_gemma4-e2b_vision (skipped)"
        return 0
    fi

    local b64
    b64=$(base64 -w 0 "$fixture")

    local out
    out=$(curl -s --max-time 180 -X POST "$BASE_URL/chat/completions" \
        -H "Content-Type: application/json" \
        -H "$AUTH_HEADER" \
        -d "{\"model\":\"local-ollama-cuda-gemma4-e2b\",\"messages\":[{\"role\":\"user\",\"content\":[{\"type\":\"image_url\",\"image_url\":{\"url\":\"data:image/jpeg;base64,$b64\"}},{\"type\":\"text\",\"text\":\"What animal is in this image? Answer in one word.\"}]}]}")

    if echo "$out" | grep -qi "\"error\""; then
        echo "  FAIL: gemma4-e2b error: $(echo "$out" | python3 -c 'import sys,json; d=json.load(sys.stdin); print(d.get("error",{}).get("message","?"))' 2>/dev/null)"
        return 1
    fi

    local content
    content=$(echo "$out" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['choices'][0]['message']['content'])" 2>/dev/null)
    echo "  gemma4-e2b says: $content"

    assert_contains_icase "$content" "cow" "gemma4-e2b identifies cow in image" || return 1
    echo "OK: ollama_cuda_gemma4-e2b_vision"
}

ALL_TESTS+=(
    test_ollama_cuda_models_registered
    test_ollama_cuda_chat_completion
    test_ollama_cuda_uncensored
    test_ollama_cuda_dolphin_phi
    test_ollama_cuda_gemma4_vision
)
