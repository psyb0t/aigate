#!/bin/bash

_MCP_ACCEPT="Accept: application/json, text/event-stream"

_mcp_call_tool() {
    local tool_name="$1" args_json="$2"
    local response
    response=$(curl -s -X POST "$BASE_URL/mcp/" \
        -H "Content-Type: application/json" \
        -H "$AUTH_HEADER" \
        -H "$_MCP_ACCEPT" \
        -d "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"$tool_name\",\"arguments\":$args_json}}")
    echo "$response" | grep "^data:" | head -1 | sed 's/^data: //'
}

_mcp_tool_description() {
    local tool_name="$1"
    local tools_json
    tools_json=$(_mcp_tools_list)
    echo "$tools_json" | python3 -c "
import sys, json
data = json.load(sys.stdin)
tools = data.get('result', {}).get('tools', [])
for t in tools:
    if t['name'] == '$tool_name':
        print(t.get('description', ''))
        break
" 2>/dev/null
}

# ── MCP media tools present ───────────────────────────────────────────────

_has_image_providers() {
    [ "${HUGGINGFACE:-}" = "1" ] || [ "${OPENAI:-}" = "1" ]
}

_has_tts_providers() {
    [ "${SPEACHES:-}" = "1" ] || [ "${CUDA:-}" = "1" ] || [ "${OPENAI:-}" = "1" ]
}

test_mcp_media_tools_present() {
    local tools_json
    tools_json=$(_mcp_tools_list)
    assert_not_empty "$tools_json" "mcp tools response" || return 1

    if _has_image_providers; then
        assert_contains "$tools_json" '"mcp_tools-generate_image"' \
            "generate_image tool present (image providers enabled)" || return 1
    else
        assert_not_contains "$tools_json" '"mcp_tools-generate_image"' \
            "generate_image tool absent (no image providers)" || return 1
    fi

    if _has_tts_providers; then
        assert_contains "$tools_json" '"mcp_tools-generate_tts"' \
            "generate_tts tool present (TTS providers enabled)" || return 1
    else
        assert_not_contains "$tools_json" '"mcp_tools-generate_tts"' \
            "generate_tts tool absent (no TTS providers)" || return 1
    fi

    echo "OK: mcp_media_tools_present"
}

# ── Tool descriptions list available models ───────────────────────────────

test_mcp_media_tool_descriptions() {
    if _has_image_providers; then
        local img_desc
        img_desc=$(_mcp_tool_description "mcp_tools-generate_image")
        assert_not_empty "$img_desc" "generate_image has description" || return 1

        if [ "${HUGGINGFACE:-}" = "1" ]; then
            assert_contains "$img_desc" "hf-flux-schnell" \
                "image description lists hf-flux-schnell (HUGGINGFACE=1)" || return 1
        fi
        if [ "${OPENAI:-}" = "1" ]; then
            assert_contains "$img_desc" "openai-dall-e-3" \
                "image description lists openai-dall-e-3 (OPENAI=1)" || return 1
        fi
    fi

    if _has_tts_providers; then
        local tts_desc
        tts_desc=$(_mcp_tool_description "mcp_tools-generate_tts")
        assert_not_empty "$tts_desc" "generate_tts has description" || return 1

        if [ "${SPEACHES:-}" = "1" ]; then
            assert_contains "$tts_desc" "local-speaches-kokoro-tts" \
                "tts description lists kokoro (SPEACHES=1)" || return 1
        fi
        if [ "${CUDA:-}" = "1" ]; then
            assert_contains "$tts_desc" "local-qwen3-cuda-tts" \
                "tts description lists qwen3-cuda (CUDA=1)" || return 1
        fi
        if [ "${OPENAI:-}" = "1" ]; then
            assert_contains "$tts_desc" "openai-tts-1" \
                "tts description lists openai-tts-1 (OPENAI=1)" || return 1
        fi
    fi

    echo "OK: mcp_media_tool_descriptions"
}

# ── Image generation with bad model ───────────────────────────────────────

test_mcp_media_image_bad_model() {
    if ! _has_image_providers; then
        echo "  SKIP: no image providers enabled"
        echo "OK: mcp_media_image_bad_model (skipped)"
        return 0
    fi

    local result
    result=$(_mcp_call_tool "mcp_tools-generate_image" \
        '{"prompt":"test","model":"nonexistent-model-xyz"}')
    assert_not_empty "$result" "got response for bad model" || return 1
    assert_contains "$result" "nonexistent-model-xyz" \
        "error mentions the bad model name" || return 1

    echo "OK: mcp_media_image_bad_model"
}

# ── TTS with bad model ───────────────────────────────────────────────────

test_mcp_media_tts_bad_model() {
    if ! _has_tts_providers; then
        echo "  SKIP: no TTS providers enabled"
        echo "OK: mcp_media_tts_bad_model (skipped)"
        return 0
    fi

    local result
    result=$(_mcp_call_tool "mcp_tools-generate_tts" \
        '{"text":"test","model":"nonexistent-tts-xyz"}')
    assert_not_empty "$result" "got response for bad model" || return 1
    assert_contains "$result" "nonexistent-tts-xyz" \
        "error mentions the bad model name" || return 1

    echo "OK: mcp_media_tts_bad_model"
}

# ── Image generation (actual call) ───────────────────────────────────────

test_mcp_media_generate_image() {
    if ! _has_image_providers; then
        echo "  SKIP: no image providers enabled"
        echo "OK: mcp_media_generate_image (skipped)"
        return 0
    fi

    local result
    result=$(_mcp_call_tool "mcp_tools-generate_image" \
        '{"prompt":"a solid red square on white background"}')
    assert_not_empty "$result" "got image response" || return 1

    local valid
    valid=$(echo "$result" | python3 -c "
import sys, json
data = json.load(sys.stdin)
content = data.get('result', {}).get('content', [])
for c in content:
    if c.get('type') != 'text':
        continue
    inner = json.loads(c['text'])
    if inner.get('prompt') and (inner.get('url') or inner.get('urls')):
        print('yes')
        sys.exit()
print('no')
" 2>/dev/null)
    assert_eq "$valid" "yes" \
        "response contains JSON with prompt and url" || return 1

    echo "OK: mcp_media_generate_image"
}

# ── TTS generation (actual call) ─────────────────────────────────────────

test_mcp_media_generate_tts() {
    if ! _has_tts_providers; then
        echo "  SKIP: no TTS providers enabled"
        echo "OK: mcp_media_generate_tts (skipped)"
        return 0
    fi

    local result
    result=$(_mcp_call_tool "mcp_tools-generate_tts" \
        '{"text":"hello world"}')
    assert_not_empty "$result" "got tts response" || return 1

    local valid
    valid=$(echo "$result" | python3 -c "
import sys, json
data = json.load(sys.stdin)
content = data.get('result', {}).get('content', [])
for c in content:
    if c.get('type') != 'text':
        continue
    inner = json.loads(c['text'])
    if inner.get('text') and inner.get('url') and inner.get('voice'):
        print('yes')
        sys.exit()
print('no')
" 2>/dev/null)
    assert_eq "$valid" "yes" "response contains JSON with text, voice, and url" || return 1

    echo "OK: mcp_media_generate_tts"
}

ALL_TESTS+=(
    test_mcp_media_tools_present
    test_mcp_media_tool_descriptions
    test_mcp_media_image_bad_model
    test_mcp_media_tts_bad_model
    test_mcp_media_generate_image
    test_mcp_media_generate_tts
)
