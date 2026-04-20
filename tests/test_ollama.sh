#!/bin/bash

# Skip entire file if OLLAMA not enabled
if [ "${OLLAMA:-}" != "1" ]; then
    return 0 2>/dev/null || true
fi

FIXTURES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.fixtures" && pwd)"

# ── models registered in LiteLLM ──────────────────────────────────────────

OLLAMA_EXPECTED_MODELS=(
    "local-ollama-llama3.2-3b"
    "local-ollama-qwen3-4b"
    "local-ollama-smollm2-1.7b"
    "local-ollama-qwen2.5-coder-1.5b"
    "local-ollama-qwen2.5-coder-3b"
    "local-ollama-phi3.5"
    "local-ollama-gemma3-4b"
    "local-ollama-nomic-embed"
    "local-ollama-bge-m3"
    "local-ollama-qwen3-embed-0.6b"
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
        -d '{"model":"local-ollama-smollm2-1.7b","messages":[{"role":"user","content":"respond with exactly the word LOCALPONG and nothing else"}]}')

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
        -d '{"model":"local-ollama-nomic-embed","input":"hello world"}')

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
        -d "{\"model\":\"local-ollama-gemma3-4b\",\"messages\":[{\"role\":\"user\",\"content\":[{\"type\":\"image_url\",\"image_url\":{\"url\":\"data:image/jpeg;base64,$b64\"}},{\"type\":\"text\",\"text\":\"What animal is in this image? Answer in one word.\"}]}]}")

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
