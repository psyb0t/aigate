#!/bin/bash

_UPLOAD_KEY="${HYBRIDS3_UPLOADS_KEY}"
_STORAGE_URL="$BASE_URL/storage"

# ── table: hybrids3 file operations ────────────────────────────────────────

# format: label|step_function
# These run sequentially as they depend on each other

test_hybrids3_crud() {
    local test_key="test-$(date +%s).txt"
    local test_content="hello from tests at $(date)"

    # upload
    local code
    code=$(curl -s -o /dev/null -w "%{http_code}" -X PUT \
        "$_STORAGE_URL/uploads/$test_key" \
        -H "Authorization: Bearer $_UPLOAD_KEY" \
        -H "Content-Type: text/plain" \
        -d "$test_content")
    assert_eq "$code" "200" "upload file" || return 1

    # download (public bucket — no auth needed)
    local body
    body=$(curl -sf "$_STORAGE_URL/uploads/$test_key")
    assert_eq "$body" "$test_content" "download matches upload" || return 1

    # list (no trailing slash)
    local list_out
    list_out=$(curl -sf "$_STORAGE_URL/uploads" \
        -H "Authorization: Bearer $_UPLOAD_KEY")
    assert_contains "$list_out" "$test_key" "file appears in listing" || return 1

    # delete
    code=$(curl -s -o /dev/null -w "%{http_code}" -X DELETE \
        "$_STORAGE_URL/uploads/$test_key" \
        -H "Authorization: Bearer $_UPLOAD_KEY")
    # hybrids3 returns 204 No Content on successful delete
    if [ "$code" != "200" ] && [ "$code" != "204" ]; then
        echo "  FAIL: delete file: expected 200 or 204, got $code"
        return 1
    fi
    echo "  OK: delete file ($code)"

    # verify gone
    code=$(curl -s -o /dev/null -w "%{http_code}" "$_STORAGE_URL/uploads/$test_key")
    assert_eq "$code" "404" "file gone after delete" || return 1

    echo "OK: hybrids3_crud (5 operations)"
}

# ── public read without auth ───────────────────────────────────────────────

test_hybrids3_public_read() {
    local test_key="public-test-$(date +%s).txt"

    # upload with auth
    curl -s -o /dev/null -X PUT \
        "$_STORAGE_URL/uploads/$test_key" \
        -H "Authorization: Bearer $_UPLOAD_KEY" \
        -H "Content-Type: text/plain" \
        -d "public data"

    # read without auth
    local out
    out=$(curl -sf "$_STORAGE_URL/uploads/$test_key")
    assert_eq "$out" "public data" "public read no auth" || return 1

    # cleanup
    curl -s -o /dev/null -X DELETE "$_STORAGE_URL/uploads/$test_key" \
        -H "Authorization: Bearer $_UPLOAD_KEY"

    echo "OK: hybrids3_public_read"
}

# ── reject write without auth ─────────────────────────────────────────────

test_hybrids3_auth_write() {
    # hybrids3 returns 404 for unauthorized writes (bucket not visible)
    local code
    code=$(curl -s -o /dev/null -w "%{http_code}" -X PUT \
        "$_STORAGE_URL/uploads/no-auth-test.txt" \
        -H "Content-Type: text/plain" \
        -d "should fail")
    if [ "$code" = "200" ]; then
        echo "  FAIL: write without auth should not succeed"
        return 1
    fi
    echo "  OK: write without auth rejected ($code)"

    code=$(curl -s -o /dev/null -w "%{http_code}" -X PUT \
        "$_STORAGE_URL/uploads/bad-auth-test.txt" \
        -H "Authorization: Bearer wrong-key" \
        -H "Content-Type: text/plain" \
        -d "should fail")
    if [ "$code" = "200" ]; then
        echo "  FAIL: write with bad auth should not succeed"
        return 1
    fi
    echo "  OK: write with bad auth rejected ($code)"

    echo "OK: hybrids3_auth_write"
}

ALL_TESTS+=(
    test_hybrids3_crud
    test_hybrids3_public_read
    test_hybrids3_auth_write
)
