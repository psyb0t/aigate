#!/bin/bash

_BROWSER_URL="$BASE_URL/stealthy-auto-browse"
_BROWSER_AUTH="${STEALTHY_AUTO_BROWSE_AUTH_TOKEN:-}"

_browser_call() {
    local action="$1"
    shift
    local body="{\"action\":\"$action\""
    if [ $# -gt 0 ]; then
        body="$body,$1"
    fi
    body="$body}"

    local auth_args=()
    if [ -n "$_BROWSER_AUTH" ]; then
        auth_args=(-H "Authorization: Bearer $_BROWSER_AUTH")
    fi

    curl -sf -X POST "$_BROWSER_URL/" \
        -H "Content-Type: application/json" \
        "${auth_args[@]}" \
        -b /tmp/sab_cookies.txt -c /tmp/sab_cookies.txt \
        -d "$body"
}

_browser_screenshot() {
    local auth_args=()
    if [ -n "$_BROWSER_AUTH" ]; then
        auth_args=(-H "Authorization: Bearer $_BROWSER_AUTH")
    fi
    curl -sf "$_BROWSER_URL/screenshot/browser" \
        "${auth_args[@]}" \
        -b /tmp/sab_cookies.txt -c /tmp/sab_cookies.txt \
        "$@"
}

test_browser_setup() {
    # clear cookies for session stickiness
    rm -f /tmp/sab_cookies.txt
}

# ── navigate and get text ──────────────────────────────────────────────────

test_browser_navigate() {
    test_browser_setup

    local out
    out=$(_browser_call "goto" "\"url\":\"https://example.com\"")
    assert_contains "$out" "success" "goto example.com" || return 1

    sleep 1

    out=$(_browser_call "get_text")
    assert_contains "$out" "Example Domain" "page has expected text" || return 1

    echo "OK: browser_navigate"
}

# ── get interactive elements ───────────────────────────────────────────────

test_browser_interactive_elements() {
    test_browser_setup

    _browser_call "goto" "\"url\":\"https://example.com\"" >/dev/null
    sleep 1

    local out
    out=$(_browser_call "get_interactive_elements" "\"visible_only\":true")
    assert_contains "$out" "success" "get_interactive_elements returns success" || return 1
    assert_contains "$out" "elements" "response has elements" || return 1

    echo "OK: browser_interactive_elements"
}

# ── screenshot ─────────────────────────────────────────────────────────────

test_browser_screenshot() {
    test_browser_setup

    _browser_call "goto" "\"url\":\"https://example.com\"" >/dev/null
    sleep 1

    local size
    size=$(_browser_screenshot -o /tmp/test_screenshot.png -w "%{size_download}")

    if [ "$size" -lt 1000 ]; then
        echo "  FAIL: screenshot too small: $size bytes"
        return 1
    fi
    echo "  OK: screenshot is $size bytes"

    rm -f /tmp/test_screenshot.png
    echo "OK: browser_screenshot"
}

# ── full flow: navigate → type → screenshot ────────────────────────────────

test_browser_full_flow() {
    test_browser_setup

    # navigate
    local out
    out=$(_browser_call "goto" "\"url\":\"https://duckduckgo.com\"")
    assert_contains "$out" "success" "goto duckduckgo" || return 1
    sleep 2

    # find interactive elements
    out=$(_browser_call "get_interactive_elements" "\"visible_only\":true")
    assert_contains "$out" "elements" "found elements on ddg" || return 1

    # find search input
    local search_x search_y
    read -r search_x search_y < <(echo "$out" | python3 -c "
import sys, json
data = json.load(sys.stdin)
for el in data.get('data', {}).get('elements', []):
    if el.get('tag') == 'input':
        print(el['x'], el['y'])
        break
" 2>/dev/null)

    if [ -z "$search_x" ]; then
        echo "  WARN: no input found, using center coords"
        search_x=640
        search_y=300
    fi

    # click search box
    _browser_call "system_click" "\"x\":$search_x,\"y\":$search_y" >/dev/null
    sleep 0.5

    # type query
    _browser_call "system_type" "\"text\":\"test query\"" >/dev/null
    sleep 0.5

    # take screenshot
    local size
    size=$(_browser_screenshot -o /dev/null -w "%{size_download}")

    if [ "$size" -lt 1000 ]; then
        echo "  FAIL: screenshot after typing too small: $size bytes"
        return 1
    fi
    echo "  OK: full flow screenshot $size bytes"

    echo "OK: browser_full_flow"
}

ALL_TESTS+=(
    test_browser_navigate
    test_browser_interactive_elements
    test_browser_screenshot
    test_browser_full_flow
)
