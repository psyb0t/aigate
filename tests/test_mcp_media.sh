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
    [ "${HUGGINGFACE:-}" = "1" ] || [ "${OPENAI:-}" = "1" ] || [ "${SDCPP:-}" = "1" ]
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
        if [ "${SDCPP:-}" = "1" ]; then
            assert_contains "$img_desc" "local-sdcpp-cpu-sd-turbo" \
                "image description lists local-sdcpp-cpu-sd-turbo (SDCPP=1)" || return 1
        fi
        if [ "${SDCPP:-}" = "1" ] && [ "${CUDA:-}" = "1" ]; then
            assert_contains "$img_desc" "local-sdcpp-cuda-sd-turbo" \
                "image description lists local-sdcpp-cuda-sd-turbo (SDCPP+CUDA)" || return 1
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

# ── Image generation via sdcpp-cuda (through LiteLLM + resource manager) ─

test_mcp_media_generate_image_sdcpp_cuda() {
    if [ "${SDCPP:-}" != "1" ] || [ "${CUDA:-}" != "1" ]; then
        echo "  SKIP: SDCPP+CUDA not enabled"
        echo "OK: mcp_media_generate_image_sdcpp_cuda (skipped)"
        return 0
    fi

    local result
    result=$(_mcp_call_tool "mcp_tools-generate_image" \
        '{"prompt":"a solid blue circle on white background","model":"local-sdcpp-cuda-sd-turbo","size":"512x512"}')
    assert_not_empty "$result" "got sdcpp-cuda image response" || return 1

    local valid
    valid=$(echo "$result" | python3 -c "
import sys, json
data = json.load(sys.stdin)
content = data.get('result', {}).get('content', [])
for c in content:
    if c.get('type') != 'text':
        continue
    inner = json.loads(c['text'])
    if inner.get('prompt') and inner.get('model') == 'local-sdcpp-cuda-sd-turbo' and (inner.get('url') or inner.get('urls')):
        print('yes')
        sys.exit()
print('no')
" 2>/dev/null)
    assert_eq "$valid" "yes" \
        "sdcpp-cuda response has prompt, correct model, and url" || return 1

    echo "OK: mcp_media_generate_image_sdcpp_cuda"
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

# ── E2E: LLM → tool_call → MCP image gen → LLM response ────────────────

test_mcp_media_e2e_llm_image_gen() {
    if [ "${SDCPP:-}" != "1" ] || [ "${CUDA:-}" != "1" ]; then
        echo "  SKIP: SDCPP+CUDA not enabled"
        echo "OK: mcp_media_e2e_llm_image_gen (skipped)"
        return 0
    fi

    local llm_model="local-ollama-cuda-qwen3-8b"
    local img_model="local-sdcpp-cuda-sd-turbo"

    # Step 1: Ask LLM to generate an image, forcing tool use
    local step1
    step1=$(curl -s -X POST "$BASE_URL/v1/chat/completions" \
        -H "Content-Type: application/json" \
        -H "$AUTH_HEADER" \
        -d "$(cat <<EOJSON
{
    "model": "$llm_model",
    "messages": [{"role":"user","content":"Generate an image of a red cat using the $img_model model. Use the generate_image tool."}],
    "tools": [{
        "type": "function",
        "function": {
            "name": "generate_image",
            "description": "Generate an image from a text prompt",
            "parameters": {
                "type": "object",
                "properties": {
                    "prompt": {"type":"string","description":"image description"},
                    "model": {"type":"string"},
                    "size": {"type":"string","default":"512x512"}
                },
                "required": ["prompt"]
            }
        }
    }],
    "tool_choice": {"type":"function","function":{"name":"generate_image"}},
    "extra_body": {"chat_template_kwargs": {"enable_thinking": false}}
}
EOJSON
)")
    assert_not_empty "$step1" "step1: LLM responded" || return 1

    # Extract tool call
    local tool_call_id tool_args
    tool_call_id=$(echo "$step1" | python3 -c "
import sys, json
data = json.load(sys.stdin)
tc = data['choices'][0]['message'].get('tool_calls', [])
print(tc[0]['id'] if tc else '')
" 2>/dev/null)
    assert_not_empty "$tool_call_id" "step1: LLM returned tool_call" || return 1

    tool_args=$(echo "$step1" | python3 -c "
import sys, json
data = json.load(sys.stdin)
tc = data['choices'][0]['message']['tool_calls'][0]
print(tc['function']['arguments'])
" 2>/dev/null)
    assert_not_empty "$tool_args" "step1: tool_call has arguments" || return 1
    echo "  OK: step1: LLM wants to call generate_image with: $tool_args"

    # Step 2: Execute the tool via MCP
    local mcp_result
    mcp_result=$(_mcp_call_tool "mcp_tools-generate_image" "$tool_args")
    assert_not_empty "$mcp_result" "step2: MCP returned result" || return 1

    # Extract the text content from MCP response
    local tool_output
    tool_output=$(echo "$mcp_result" | python3 -c "
import sys, json
data = json.load(sys.stdin)
content = data.get('result', {}).get('content', [])
for c in content:
    if c.get('type') == 'text':
        print(c['text'])
        break
" 2>/dev/null)
    assert_not_empty "$tool_output" "step2: MCP tool returned content" || return 1

    # Verify image was actually generated
    local has_url
    has_url=$(echo "$tool_output" | python3 -c "
import sys, json
d = json.load(sys.stdin)
print('yes' if d.get('url') or d.get('urls') else 'no')
" 2>/dev/null)
    assert_eq "$has_url" "yes" "step2: image has url" || return 1
    echo "  OK: step2: MCP generated image"

    # Step 3: Send tool result back to LLM, get final response
    local tmpfile
    tmpfile=$(mktemp)
    python3 -c "
import json, sys

step1 = json.loads(sys.stdin.read())
assistant_msg = step1['choices'][0]['message']
clean_msg = {'role': assistant_msg['role']}
if assistant_msg.get('tool_calls'):
    clean_msg['tool_calls'] = assistant_msg['tool_calls']
if assistant_msg.get('content'):
    clean_msg['content'] = assistant_msg['content']

payload = {
    'model': '$llm_model',
    'messages': [
        {'role': 'user', 'content': 'Generate an image of a red cat using the $img_model model. Use the generate_image tool.'},
        clean_msg,
        {'role': 'tool', 'tool_call_id': '$tool_call_id', 'content': $(echo "$tool_output" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))")}
    ]
}
print(json.dumps(payload))
" <<< "$step1" > "$tmpfile" 2>/dev/null

    local step3
    step3=$(curl -s -X POST "$BASE_URL/v1/chat/completions" \
        -H "Content-Type: application/json" \
        -H "$AUTH_HEADER" \
        -d @"$tmpfile")
    rm -f "$tmpfile"
    assert_not_empty "$step3" "step3: LLM responded to tool result" || return 1

    local final_content
    final_content=$(echo "$step3" | python3 -c "
import sys, json
data = json.load(sys.stdin)
msg = data.get('choices',[{}])[0].get('message',{})
# accept either content or tool_calls (some models echo tool results)
content = msg.get('content','') or ''
has_tool_calls = bool(msg.get('tool_calls'))
if content or has_tool_calls:
    print(content if content else '(tool_call response)')
" 2>/dev/null)
    assert_not_empty "$final_content" "step3: LLM gave final response" || return 1
    echo "  OK: step3: LLM final response: ${final_content:0:200}"

    echo "OK: mcp_media_e2e_llm_image_gen"
}

ALL_TESTS+=(
    test_mcp_media_tools_present
    test_mcp_media_tool_descriptions
    test_mcp_media_image_bad_model
    test_mcp_media_tts_bad_model
    test_mcp_media_generate_image
    test_mcp_media_generate_image_sdcpp_cuda
    test_mcp_media_generate_tts
    test_mcp_media_e2e_llm_image_gen
)
