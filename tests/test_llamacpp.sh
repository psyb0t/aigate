#!/bin/bash

# ── llamacpp wrapper: gated on LLAMACPP=1 / LLAMACPP_CUDA=1 ─────────────────
#
# Two variants run side-by-side on distinct service hostnames inside the
# compose network:
#   llamacpp        → CPU (LLAMACPP=1)
#   llamacpp-cuda   → GPU (LLAMACPP_CUDA=1)
# Both registered with LiteLLM as `local-llamacpp-<slug>` and
# `local-llamacpp-cuda-<slug>` chat models. The tests below exercise the
# full path through LiteLLM (model routing → wrapper supervisor → spawn
# llama-server → vision chat completion → response) so any breakage in the
# pipeline gets caught.
#
# What we test, per variant:
#   1. `/v1/models` lists the configured surya-ocr-2 slug
#   2. The captcha fixture (tests/.fixtures/captcha.png) returns a JSON
#      response containing the expected literal text "AIGATE2026" — this
#      proves: (a) the wrapper spawned llama-server with the right gguf +
#      mmproj, (b) the model loaded a real image and decoded it, (c) the
#      OpenAI vision chat completions wire format works through the whole
#      LiteLLM → wrapper → llama-server proxy chain.
#   3. The doc.pdf fixture's first page is rasterized with `pdftoppm` and
#      sent the same way; we assert the response contains "quick brown fox"
#      so we catch regressions where Surya stops working on PDF-derived
#      raster input but still works on captcha-style PNGs.

_llamacpp_cpu_enabled()  { [ "${LLAMACPP:-0}" = "1" ]; }
_llamacpp_cuda_enabled() { [ "${LLAMACPP_CUDA:-0}" = "1" ]; }

# ── helpers ────────────────────────────────────────────────────────────────

# data:image/<fmt>;base64,<payload> URL — vision chat completions over
# OpenAI take this in the `image_url.url` field. We base64-encode the
# fixture inline so the request stays a single curl.
_llamacpp_data_url() {
    local fmt="$1" path="$2"
    printf 'data:image/%s;base64,' "$fmt"
    base64 -w 0 < "$path"
}

# Raster page 1 of a PDF to a PNG at 96 DPI — Surya's training-time
# default (see surya/README "DPI can also impact throughput significantly
# — you can adjust the DPI settings ... Try going from 192 to 96 for
# improved throughput.") CPU-side vision encoding is the bottleneck and
# is roughly quadratic in image area, so 200 DPI → ~4× slower than 96 DPI
# for no quality gain on synthetic fixtures.
_llamacpp_pdf_page1_png() {
    local pdf="$1" out_dir="$2"
    pdftoppm -png -r 96 -f 1 -l 1 "$pdf" "$out_dir/page" >/dev/null 2>&1
    # pdftoppm writes <prefix>-<page-number>.png. Single-page → page-1.png.
    echo "$out_dir/page-1.png"
}

# POST one /v1/chat/completions request with a single vision message
# containing the image + a Surya training-time task prompt, and echo the
# raw assistant text content. Anything non-200 returns the body so the
# caller can grep for what went wrong.
#
# Surya prompts are TRAINED INTO THE MODEL — paraphrasing them produces
# unpredictable output mode (layout-JSON vs OCR-HTML). The exact strings
# come from datalab-to/surya:surya/inference/prompts.py:
#   BLOCK_PROMPT — "OCR this block image to HTML."
#       For a tight crop of one text region (captcha, single text block).
#   HIGH_ACCURACY_BBOX_PROMPT — "OCR this image to HTML. Each block is a
#       div with data-label and data-bbox (x0 y0 x1 y1, normalized 0-1000)."
#       For a full page with multiple regions (PDF page, scanned doc).
#
#   $1 model_id   — e.g. local-llamacpp-surya-ocr-2
#   $2 image_url  — full data:image/...;base64,... string
#   $3 timeout_s  — curl --max-time
#   $4 task       — "block" or "page" (chooses the prompt)

# CPU Surya generates around 1 token/s on a loaded host and the wrapper ends a
# request after LLAMACPP_WRAP_REQUEST_TIMEOUT (300 s by default), so CPU runs
# get a budget that covers the text the tests assert on and still finishes.
readonly LLAMACPP_CPU_OCR_MAX_TOKENS=160

# $1 model_id, $2 token budget for GPU models. Echoes the budget to request.
_llamacpp_max_tokens() {
    local model="$1" gpu_budget="$2"
    if [[ "$model" == *-cuda-* ]]; then
        echo "$gpu_budget"
        return 0
    fi
    echo "$LLAMACPP_CPU_OCR_MAX_TOKENS"
}

_llamacpp_ocr_call() {
    local model="$1" image_url="$2" timeout="$3" task="$4"
    local prompt
    case "$task" in
        block)     prompt="OCR this block image to HTML." ;;
        page)      prompt="OCR this image to HTML. Each block is a div with data-label and data-bbox (x0 y0 x1 y1, normalized 0-1000)." ;;
        layout)    prompt="Output the layout of this image as JSON. Each entry is a dict with \"label\", \"bbox\", and \"count\" fields. Bbox is x0 y0 x1 y1, normalized 0-1000." ;;
        table_rec) prompt="Output the table rows then columns as JSON. Each entry is a dict with \"label\" (\"Row\" or \"Col\") and \"bbox\" (x0 y0 x1 y1, normalized 0-1000)." ;;
        *)         echo "  FAIL: unknown task '$task'"; return 1 ;;
    esac
    local body
    body=$(python3 -c "
import json, sys
print(json.dumps({
    'model': sys.argv[1],
    'max_tokens': int(sys.argv[4]),
    'temperature': 0.0,
    'messages': [
        {
            'role': 'user',
            'content': [
                {'type': 'image_url', 'image_url': {'url': sys.argv[2]}},
                {'type': 'text', 'text': sys.argv[3]},
            ],
        },
    ],
}))
" "$model" "$image_url" "$prompt" "$(_llamacpp_max_tokens "$model" 1024)")
    curl -s -m "$timeout" -X POST "$BASE_URL/v1/chat/completions" \
        -H "$AUTH_HEADER" \
        -H "Content-Type: application/json" \
        -d "$body" \
        -w "\nHTTP_CODE:%{http_code}"
}

# Parse the assistant content out of an OpenAI chat completion response.
# Returns empty string on parse failure (caller asserts).
_llamacpp_extract_content() {
    local raw="$1"
    echo "$raw" | sed '/^HTTP_CODE:/d' \
        | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    print(d['choices'][0]['message']['content'])
except Exception:
    pass
"
}

# ── parameterised assertions ───────────────────────────────────────────────

_llamacpp_test_models_list() {
    local model="$1" tag="$2"
    local out
    out=$(curl -sf "$BASE_URL/v1/models" -H "$AUTH_HEADER" 2>/dev/null) || {
        echo "  FAIL: ${tag} GET /v1/models"; return 1
    }
    assert_contains "$out" "\"$model\"" "${tag} /v1/models lists ${model}" || return 1
    echo "OK: ${tag} models_list"
}

_llamacpp_test_captcha_ocr() {
    local model="$1" tag="$2"
    local fixture="$WORKDIR/tests/.fixtures/captcha.png"
    [ -f "$fixture" ] || { echo "  SKIP: missing $fixture"; return 0; }
    local url; url=$(_llamacpp_data_url "png" "$fixture")
    local raw code content
    raw=$(_llamacpp_ocr_call "$model" "$url" 600 "block")
    code=$(echo "$raw" | sed -n 's/^HTTP_CODE://p' | tail -1)
    if [ "$code" != "200" ]; then
        echo "  FAIL: ${tag} captcha OCR HTTP $code"
        echo "  body: $(echo "$raw" | sed '/^HTTP_CODE:/d' | head -c 400)"
        return 1
    fi
    content=$(_llamacpp_extract_content "$raw")
    assert_contains "$content" "AIGATE2026" "${tag} captcha contains 'AIGATE2026'" || {
        echo "  hint: model returned: $(echo "$content" | head -c 200)"
        return 1
    }
    echo "OK: ${tag} captcha_ocr"
}

_llamacpp_test_pdf_ocr() {
    local model="$1" tag="$2"
    local fixture="$WORKDIR/tests/.fixtures/doc.pdf"
    [ -f "$fixture" ] || { echo "  SKIP: missing $fixture"; return 0; }
    if ! command -v pdftoppm >/dev/null 2>&1; then
        echo "  SKIP: ${tag} pdftoppm not in PATH (need poppler-utils in the runner)"
        return 0
    fi
    local tmp; tmp=$(mktemp -d)
    local png; png=$(_llamacpp_pdf_page1_png "$fixture" "$tmp")
    [ -f "$png" ] || { echo "  FAIL: ${tag} pdftoppm produced no PNG"; rm -rf "$tmp"; return 1; }
    local url; url=$(_llamacpp_data_url "png" "$png")
    local raw code content
    raw=$(_llamacpp_ocr_call "$model" "$url" 600 "page")
    code=$(echo "$raw" | sed -n 's/^HTTP_CODE://p' | tail -1)
    rm -rf "$tmp"
    if [ "$code" != "200" ]; then
        echo "  FAIL: ${tag} pdf OCR HTTP $code"
        echo "  body: $(echo "$raw" | sed '/^HTTP_CODE:/d' | head -c 400)"
        return 1
    fi
    content=$(_llamacpp_extract_content "$raw")
    # The fixture line: "The quick brown fox jumps over the lazy dog."
    # Case-fold the comparison; Surya emits HTML with mixed-case prose.
    local lower_content
    lower_content=$(echo "$content" | tr '[:upper:]' '[:lower:]')
    assert_contains "$lower_content" "quick brown fox" "${tag} pdf contains 'quick brown fox'" || {
        echo "  hint: model returned: $(echo "$content" | head -c 200)"
        return 1
    }
    echo "OK: ${tag} pdf_ocr"
}

# ── CPU variant ────────────────────────────────────────────────────────────

test_llamacpp_cpu_models_list() {
    _llamacpp_cpu_enabled || { echo "  SKIP: LLAMACPP not enabled"; return 0; }
    _llamacpp_test_models_list "local-llamacpp-surya-ocr-2" "llamacpp-cpu"
}

test_llamacpp_cpu_captcha_ocr() {
    _llamacpp_cpu_enabled || { echo "  SKIP: LLAMACPP not enabled"; return 0; }
    _llamacpp_test_captcha_ocr "local-llamacpp-surya-ocr-2" "llamacpp-cpu"
}

test_llamacpp_cpu_pdf_ocr() {
    _llamacpp_cpu_enabled || { echo "  SKIP: LLAMACPP not enabled"; return 0; }
    _llamacpp_test_pdf_ocr "local-llamacpp-surya-ocr-2" "llamacpp-cpu"
}

# ── CUDA variant ───────────────────────────────────────────────────────────

test_llamacpp_cuda_models_list() {
    _llamacpp_cuda_enabled || { echo "  SKIP: LLAMACPP_CUDA not enabled"; return 0; }
    _llamacpp_test_models_list "local-llamacpp-cuda-surya-ocr-2" "llamacpp-cuda"
}

test_llamacpp_cuda_captcha_ocr() {
    _llamacpp_cuda_enabled || { echo "  SKIP: LLAMACPP_CUDA not enabled"; return 0; }
    _llamacpp_test_captcha_ocr "local-llamacpp-cuda-surya-ocr-2" "llamacpp-cuda"
}

test_llamacpp_cuda_pdf_ocr() {
    _llamacpp_cuda_enabled || { echo "  SKIP: LLAMACPP_CUDA not enabled"; return 0; }
    _llamacpp_test_pdf_ocr "local-llamacpp-cuda-surya-ocr-2" "llamacpp-cuda"
}

# ── image_url fetch ────────────────────────────────────────────────────────
#
# llama-server's mtmd vision pipeline only accepts data: URLs natively. The
# wrapper fetches http(s):// URLs and rewrites them to data: URLs before
# forwarding. Its SSRF guard refuses any URL whose host resolves to a
# private, loopback, link-local, or reserved address. In aigate the llamacpp
# containers sit on the internal network with no internet egress, so public
# URLs cannot be fetched either and callers send data: URLs (covered by the
# PDF and captcha data-URL tests). This test checks that an in-network URL is
# refused with 400 instead of being fetched.

# Resolves to a private address on the aigate-internal network.
readonly LLAMACPP_PRIVATE_IMAGE_URL="http://nginx:4000/health/liveliness"
readonly LLAMACPP_SSRF_REFUSAL="refusing to fetch URL"

_llamacpp_test_url_captcha() {
    local model="$1" tag="$2"
    local raw code

    raw=$(_llamacpp_ocr_call "$model" "$LLAMACPP_PRIVATE_IMAGE_URL" 120 "block")
    code=$(echo "$raw" | sed -n 's/^HTTP_CODE://p' | tail -1)
    assert_eq "$code" "400" "${tag} internal image URL refused" || return 1
    assert_contains "$raw" "$LLAMACPP_SSRF_REFUSAL" "${tag} refusal names the SSRF guard" || return 1
    echo "OK: ${tag} url_ssrf_guard"
}

test_llamacpp_cpu_url_captcha() {
    _llamacpp_cpu_enabled || { echo "  SKIP: LLAMACPP not enabled"; return 0; }
    _llamacpp_test_url_captcha "local-llamacpp-surya-ocr-2" "llamacpp-cpu"
}

test_llamacpp_cuda_url_captcha() {
    _llamacpp_cuda_enabled || { echo "  SKIP: LLAMACPP_CUDA not enabled"; return 0; }
    _llamacpp_test_url_captcha "local-llamacpp-cuda-surya-ocr-2" "llamacpp-cuda"
}

# ── Surya layout + table-recognition modes ─────────────────────────────────
#
# Surya is one VLM that switches behaviour based on which training-time
# prompt it's given. The two OCR modes (block + page) are tested above.
# Two more modes:
#   layout      — emit JSON [{label, bbox, count}, ...] describing the
#                 reading-order-sorted blocks (Text / Picture / Table /
#                 Caption / etc.). Used by Surya's own LayoutPredictor
#                 to pre-segment a page before per-block OCR.
#   table_rec   — emit JSON [{label: "Row"|"Col", bbox}, ...] describing
#                 the rows then columns of a table image. Used by
#                 TableRecPredictor (simple mode); the full HTML output
#                 ships only via predict_full() at the Python layer.
#
# These tests use the doc.pdf + table.pdf fixtures rasterized via
# pdftoppm, and assert structural properties of the JSON (must contain
# either a known label string or the expected JSON shape) — not exact
# pixel-perfect bbox values, since those are noise-sensitive.

_llamacpp_test_layout() {
    local model="$1" tag="$2"
    local fixture="$WORKDIR/tests/.fixtures/doc.pdf"
    [ -f "$fixture" ] || { echo "  SKIP: missing $fixture"; return 0; }
    if ! command -v pdftoppm >/dev/null 2>&1; then
        echo "  SKIP: ${tag} pdftoppm not in PATH (need poppler-utils in the runner)"
        return 0
    fi
    local tmp; tmp=$(mktemp -d)
    local png; png=$(_llamacpp_pdf_page1_png "$fixture" "$tmp")
    [ -f "$png" ] || { echo "  FAIL: ${tag} pdftoppm produced no PNG"; rm -rf "$tmp"; return 1; }
    local url; url=$(_llamacpp_data_url "png" "$png")
    local raw code content
    raw=$(_llamacpp_ocr_call "$model" "$url" 600 "layout")
    code=$(echo "$raw" | sed -n 's/^HTTP_CODE://p' | tail -1)
    rm -rf "$tmp"
    if [ "$code" != "200" ]; then
        echo "  FAIL: ${tag} layout HTTP $code"
        echo "  body: $(echo "$raw" | sed '/^HTTP_CODE:/d' | head -c 400)"
        return 1
    fi
    content=$(_llamacpp_extract_content "$raw")
    # Layout output is a JSON array of {label, bbox, count} objects. The
    # exact labels depend on what Surya finds in the page (Text / Picture /
    # SectionHeader / ...); we just assert the response is a non-empty JSON
    # array with at least one `"label"` field — that's enough to prove the
    # model entered layout mode and emitted the trained schema.
    local first_label
    first_label=$(echo "$content" | python3 -c "
import json, sys, re
raw = sys.stdin.read().strip()
try:
    data = json.loads(raw)
except Exception:
    # Surya occasionally wraps the JSON in stray whitespace or a leading
    # newline. Salvage the first JSON array we can find.
    m = re.search(r'\[.*\]', raw, re.DOTALL)
    data = json.loads(m.group(0)) if m else None
if not isinstance(data, list) or not data:
    sys.exit(0)
first = data[0]
if isinstance(first, dict) and isinstance(first.get('label'), str):
    print(first['label'])
" 2>/dev/null)
    if [ -z "$first_label" ]; then
        echo "  FAIL: ${tag} layout — response is not a non-empty JSON array of {label, ...} objects"
        echo "  body: $(echo "$content" | head -c 400)"
        return 1
    fi
    echo "OK: ${tag} layout (first label=${first_label})"
}

_llamacpp_test_table_rec() {
    local model="$1" tag="$2"
    local fixture="$WORKDIR/tests/.fixtures/table.pdf"
    [ -f "$fixture" ] || { echo "  SKIP: missing $fixture"; return 0; }
    if ! command -v pdftoppm >/dev/null 2>&1; then
        echo "  SKIP: ${tag} pdftoppm not in PATH (need poppler-utils in the runner)"
        return 0
    fi
    local tmp; tmp=$(mktemp -d)
    local png; png=$(_llamacpp_pdf_page1_png "$fixture" "$tmp")
    [ -f "$png" ] || { echo "  FAIL: ${tag} pdftoppm produced no PNG"; rm -rf "$tmp"; return 1; }
    local url; url=$(_llamacpp_data_url "png" "$png")
    local raw code content
    raw=$(_llamacpp_ocr_call "$model" "$url" 600 "table_rec")
    code=$(echo "$raw" | sed -n 's/^HTTP_CODE://p' | tail -1)
    rm -rf "$tmp"
    if [ "$code" != "200" ]; then
        echo "  FAIL: ${tag} table_rec HTTP $code"
        echo "  body: $(echo "$raw" | sed '/^HTTP_CODE:/d' | head -c 400)"
        return 1
    fi
    content=$(_llamacpp_extract_content "$raw")
    # Table-rec output is a JSON array of {label: "Row"|"Col", bbox}. The
    # fixture has 4 rows (1 header + 3 data) and 3 columns, so we expect at
    # least one "Row" AND at least one "Col" entry. Anything else is a
    # regression in either the wrapper or the model.
    local counts
    counts=$(echo "$content" | python3 -c "
import json, sys, re
raw = sys.stdin.read().strip()
try:
    data = json.loads(raw)
except Exception:
    m = re.search(r'\[.*\]', raw, re.DOTALL)
    data = json.loads(m.group(0)) if m else None
if not isinstance(data, list):
    sys.exit(0)
rows = sum(1 for e in data if isinstance(e, dict) and e.get('label') == 'Row')
cols = sum(1 for e in data if isinstance(e, dict) and e.get('label') == 'Col')
print(f'{rows} {cols}')
" 2>/dev/null)
    local rows cols
    rows=$(echo "$counts" | awk '{print $1}')
    cols=$(echo "$counts" | awk '{print $2}')
    rows=${rows:-0}
    cols=${cols:-0}
    if [ "$rows" -lt 1 ] || [ "$cols" -lt 1 ]; then
        echo "  FAIL: ${tag} table_rec — expected >=1 Row + >=1 Col, got rows=$rows cols=$cols"
        echo "  body: $(echo "$content" | head -c 400)"
        return 1
    fi
    echo "OK: ${tag} table_rec (rows=$rows cols=$cols)"
}

test_llamacpp_cpu_layout() {
    _llamacpp_cpu_enabled || { echo "  SKIP: LLAMACPP not enabled"; return 0; }
    _llamacpp_test_layout "local-llamacpp-surya-ocr-2" "llamacpp-cpu"
}

test_llamacpp_cpu_table_rec() {
    _llamacpp_cpu_enabled || { echo "  SKIP: LLAMACPP not enabled"; return 0; }
    _llamacpp_test_table_rec "local-llamacpp-surya-ocr-2" "llamacpp-cpu"
}

test_llamacpp_cuda_layout() {
    _llamacpp_cuda_enabled || { echo "  SKIP: LLAMACPP_CUDA not enabled"; return 0; }
    _llamacpp_test_layout "local-llamacpp-cuda-surya-ocr-2" "llamacpp-cuda"
}

test_llamacpp_cuda_table_rec() {
    _llamacpp_cuda_enabled || { echo "  SKIP: LLAMACPP_CUDA not enabled"; return 0; }
    _llamacpp_test_table_rec "local-llamacpp-cuda-surya-ocr-2" "llamacpp-cuda"
}

# ── direct PDF input (Surya handler — server-side rasterize + stitch) ──────
#
# The wrapper grew a per-model handler hook; the Surya handler detects PDF
# input in `image_url.url` (data:application/pdf;base64,... or http URL
# with application/pdf Content-Type), rasterizes each page server-side via
# poppler-utils, loops the chat completion per page, and stitches the
# results back per detected Surya prompt mode. These tests verify:
#
#   - PDF as a data: URL works (single-page + multi-page)
#   - Per-page stitching tags each page with `<div data-page="N">`
#   - Layout mode adds a `page` field to each JSON entry
#   - Block-OCR mode rejected with HTTP 400 (single-image only)
#   - `dpi_rescale_to` extension is parsed (`-1` and explicit values)

# Build a PDF data: URL inline.
_llamacpp_pdf_data_url() {
    local path="$1"
    printf 'data:application/pdf;base64,'
    base64 -w 0 < "$path"
}

# Same POST shape as _llamacpp_ocr_call but feeds an arbitrary
# image_url + lets the caller add a top-level `dpi_rescale_to` field
# (passed unquoted as JSON — caller passes "-1" or "96" or "" to skip).
_llamacpp_ocr_call_with_dpi() {
    local model="$1" image_url="$2" timeout="$3" task="$4" dpi="$5"
    local prompt
    case "$task" in
        block)     prompt="OCR this block image to HTML." ;;
        page)      prompt="OCR this image to HTML. Each block is a div with data-label and data-bbox (x0 y0 x1 y1, normalized 0-1000)." ;;
        layout)    prompt="Output the layout of this image as JSON. Each entry is a dict with \"label\", \"bbox\", and \"count\" fields. Bbox is x0 y0 x1 y1, normalized 0-1000." ;;
        table_rec) prompt="Output the table rows then columns as JSON. Each entry is a dict with \"label\" (\"Row\" or \"Col\") and \"bbox\" (x0 y0 x1 y1, normalized 0-1000)." ;;
        *)         echo "  FAIL: unknown task '$task'"; return 1 ;;
    esac
    local body
    body=$(python3 -c "
import json, sys
payload = {
    'model': sys.argv[1],
    'max_tokens': int(sys.argv[5]),
    'temperature': 0.0,
    'messages': [{
        'role': 'user',
        'content': [
            {'type': 'image_url', 'image_url': {'url': sys.argv[2]}},
            {'type': 'text', 'text': sys.argv[3]},
        ],
    }],
}
dpi = sys.argv[4]
if dpi:
    payload['dpi_rescale_to'] = int(dpi)
print(json.dumps(payload))
" "$model" "$image_url" "$prompt" "$dpi" "$(_llamacpp_max_tokens "$model" 2048)")
    curl -s -m "$timeout" -X POST "$BASE_URL/v1/chat/completions" \
        -H "$AUTH_HEADER" \
        -H "Content-Type: application/json" \
        -d "$body" \
        -w "\nHTTP_CODE:%{http_code}"
}

_llamacpp_test_pdf_data_url() {
    local model="$1" tag="$2"
    local fixture="$WORKDIR/tests/.fixtures/doc.pdf"
    [ -f "$fixture" ] || { echo "  SKIP: missing $fixture"; return 0; }
    local url; url=$(_llamacpp_pdf_data_url "$fixture")
    local raw code content
    raw=$(_llamacpp_ocr_call_with_dpi "$model" "$url" 600 "page" "")
    code=$(echo "$raw" | sed -n 's/^HTTP_CODE://p' | tail -1)
    if [ "$code" != "200" ]; then
        echo "  FAIL: ${tag} PDF data URL HTTP $code"
        echo "  body: $(echo "$raw" | sed '/^HTTP_CODE:/d' | head -c 400)"
        return 1
    fi
    content=$(_llamacpp_extract_content "$raw")
    local lower; lower=$(echo "$content" | tr '[:upper:]' '[:lower:]')
    assert_contains "$lower" "quick brown fox" "${tag} PDF data URL contains 'quick brown fox'" || return 1
    assert_contains "$content" 'data-page="1"' "${tag} PDF data URL stitched as 'data-page=\"1\"'" || return 1
    echo "OK: ${tag} pdf_data_url"
}

_llamacpp_test_pdf_multipage() {
    local model="$1" tag="$2"
    local fixture="$WORKDIR/tests/.fixtures/doc-multipage.pdf"
    [ -f "$fixture" ] || { echo "  SKIP: missing $fixture"; return 0; }
    local url; url=$(_llamacpp_pdf_data_url "$fixture")
    local raw code content
    raw=$(_llamacpp_ocr_call_with_dpi "$model" "$url" 900 "page" "")
    code=$(echo "$raw" | sed -n 's/^HTTP_CODE://p' | tail -1)
    if [ "$code" != "200" ]; then
        echo "  FAIL: ${tag} multi-page PDF HTTP $code"
        echo "  body: $(echo "$raw" | sed '/^HTTP_CODE:/d' | head -c 400)"
        return 1
    fi
    content=$(_llamacpp_extract_content "$raw")
    # 3 unique substrings, one per page — proves the stitcher walked
    # every page and concatenated their contents in order.
    assert_contains "$content" 'data-page="1"' "${tag} multipage page 1 wrapper" || return 1
    assert_contains "$content" 'data-page="2"' "${tag} multipage page 2 wrapper" || return 1
    assert_contains "$content" 'data-page="3"' "${tag} multipage page 3 wrapper" || return 1
    assert_contains "$content" 'Alpha' "${tag} multipage contains page 1 text 'Alpha'" || return 1
    assert_contains "$content" 'Beta'  "${tag} multipage contains page 2 text 'Beta'"  || return 1
    assert_contains "$content" 'Gamma' "${tag} multipage contains page 3 text 'Gamma'" || return 1
    # x_surya_pages should be 3
    local pages
    pages=$(echo "$raw" | sed '/^HTTP_CODE:/d' | python3 -c "import sys,json; print(json.load(sys.stdin).get('x_surya_pages',''))" 2>/dev/null)
    assert_eq "$pages" "3" "${tag} multipage x_surya_pages=3" || return 1
    echo "OK: ${tag} pdf_multipage"
}

_llamacpp_test_pdf_layout() {
    local model="$1" tag="$2"
    local fixture="$WORKDIR/tests/.fixtures/doc.pdf"
    [ -f "$fixture" ] || { echo "  SKIP: missing $fixture"; return 0; }
    local url; url=$(_llamacpp_pdf_data_url "$fixture")
    local raw code content
    raw=$(_llamacpp_ocr_call_with_dpi "$model" "$url" 600 "layout" "")
    code=$(echo "$raw" | sed -n 's/^HTTP_CODE://p' | tail -1)
    if [ "$code" != "200" ]; then
        echo "  FAIL: ${tag} PDF layout HTTP $code"
        echo "  body: $(echo "$raw" | sed '/^HTTP_CODE:/d' | head -c 400)"
        return 1
    fi
    content=$(_llamacpp_extract_content "$raw")
    # Layout stitcher should produce a JSON array where every entry has
    # a "page" field added in.
    local check
    check=$(echo "$content" | python3 -c "
import json, sys, re
raw = sys.stdin.read().strip()
m = re.search(r'\[.*\]', raw, re.DOTALL)
if not m:
    print('NO_ARRAY'); sys.exit(0)
try:
    data = json.loads(m.group(0))
except Exception:
    print('PARSE_FAIL'); sys.exit(0)
if not isinstance(data, list) or not data:
    print('NOT_LIST'); sys.exit(0)
if all(isinstance(e, dict) and 'page' in e for e in data):
    print('OK')
else:
    print('MISSING_PAGE')
" 2>/dev/null)
    assert_eq "$check" "OK" "${tag} PDF layout: every entry has 'page' field" || return 1
    echo "OK: ${tag} pdf_layout"
}

_llamacpp_test_pdf_block_rejected() {
    local model="$1" tag="$2"
    local fixture="$WORKDIR/tests/.fixtures/doc.pdf"
    [ -f "$fixture" ] || { echo "  SKIP: missing $fixture"; return 0; }
    local url; url=$(_llamacpp_pdf_data_url "$fixture")
    local raw code body
    raw=$(_llamacpp_ocr_call_with_dpi "$model" "$url" 60 "block" "")
    code=$(echo "$raw" | sed -n 's/^HTTP_CODE://p' | tail -1)
    if [ "$code" != "400" ]; then
        echo "  FAIL: ${tag} PDF+block expected HTTP 400, got $code"
        echo "  body: $(echo "$raw" | sed '/^HTTP_CODE:/d' | head -c 400)"
        return 1
    fi
    body=$(echo "$raw" | sed '/^HTTP_CODE:/d')
    assert_contains "$body" "single-image" "${tag} 400 mentions 'single-image' rejection" || return 1
    echo "OK: ${tag} pdf_block_rejected"
}

_llamacpp_test_pdf_dpi_negative_one() {
    local model="$1" tag="$2"
    local fixture="$WORKDIR/tests/.fixtures/doc.pdf"
    [ -f "$fixture" ] || { echo "  SKIP: missing $fixture"; return 0; }
    local url; url=$(_llamacpp_pdf_data_url "$fixture")
    local raw code content
    raw=$(_llamacpp_ocr_call_with_dpi "$model" "$url" 600 "page" "-1")
    code=$(echo "$raw" | sed -n 's/^HTTP_CODE://p' | tail -1)
    if [ "$code" != "200" ]; then
        echo "  FAIL: ${tag} dpi_rescale_to=-1 HTTP $code"
        echo "  body: $(echo "$raw" | sed '/^HTTP_CODE:/d' | head -c 400)"
        return 1
    fi
    content=$(_llamacpp_extract_content "$raw")
    local lower; lower=$(echo "$content" | tr '[:upper:]' '[:lower:]')
    assert_contains "$lower" "quick brown fox" "${tag} dpi=-1 contains 'quick brown fox'" || return 1
    echo "OK: ${tag} pdf_dpi_rescale_negative_one"
}

test_llamacpp_cpu_pdf_data_url() {
    _llamacpp_cpu_enabled || { echo "  SKIP: LLAMACPP not enabled"; return 0; }
    _llamacpp_test_pdf_data_url "local-llamacpp-surya-ocr-2" "llamacpp-cpu"
}
test_llamacpp_cpu_pdf_multipage() {
    _llamacpp_cpu_enabled || { echo "  SKIP: LLAMACPP not enabled"; return 0; }
    _llamacpp_test_pdf_multipage "local-llamacpp-surya-ocr-2" "llamacpp-cpu"
}
test_llamacpp_cpu_pdf_layout() {
    _llamacpp_cpu_enabled || { echo "  SKIP: LLAMACPP not enabled"; return 0; }
    _llamacpp_test_pdf_layout "local-llamacpp-surya-ocr-2" "llamacpp-cpu"
}
test_llamacpp_cpu_pdf_block_rejected() {
    _llamacpp_cpu_enabled || { echo "  SKIP: LLAMACPP not enabled"; return 0; }
    _llamacpp_test_pdf_block_rejected "local-llamacpp-surya-ocr-2" "llamacpp-cpu"
}
test_llamacpp_cpu_pdf_dpi_negative_one() {
    _llamacpp_cpu_enabled || { echo "  SKIP: LLAMACPP not enabled"; return 0; }
    _llamacpp_test_pdf_dpi_negative_one "local-llamacpp-surya-ocr-2" "llamacpp-cpu"
}

test_llamacpp_cuda_pdf_data_url() {
    _llamacpp_cuda_enabled || { echo "  SKIP: LLAMACPP_CUDA not enabled"; return 0; }
    _llamacpp_test_pdf_data_url "local-llamacpp-cuda-surya-ocr-2" "llamacpp-cuda"
}
test_llamacpp_cuda_pdf_multipage() {
    _llamacpp_cuda_enabled || { echo "  SKIP: LLAMACPP_CUDA not enabled"; return 0; }
    _llamacpp_test_pdf_multipage "local-llamacpp-cuda-surya-ocr-2" "llamacpp-cuda"
}
test_llamacpp_cuda_pdf_layout() {
    _llamacpp_cuda_enabled || { echo "  SKIP: LLAMACPP_CUDA not enabled"; return 0; }
    _llamacpp_test_pdf_layout "local-llamacpp-cuda-surya-ocr-2" "llamacpp-cuda"
}
test_llamacpp_cuda_pdf_block_rejected() {
    _llamacpp_cuda_enabled || { echo "  SKIP: LLAMACPP_CUDA not enabled"; return 0; }
    _llamacpp_test_pdf_block_rejected "local-llamacpp-cuda-surya-ocr-2" "llamacpp-cuda"
}
test_llamacpp_cuda_pdf_dpi_negative_one() {
    _llamacpp_cuda_enabled || { echo "  SKIP: LLAMACPP_CUDA not enabled"; return 0; }
    _llamacpp_test_pdf_dpi_negative_one "local-llamacpp-cuda-surya-ocr-2" "llamacpp-cuda"
}

# ── auto ctx-size resolver ────────────────────────────────────────────────
#
# Verifies the supervisor resolved `--ctx-size auto` to a concrete value at
# spawn time. We assert: (a) the resolver log line landed, (b) the chosen
# value is at or above the floor (16384), (c) the value is a multiple of
# 1024. Doesn't pin a specific exact value — that depends on real-time
# free VRAM/RAM at the moment of spawn (other CUDA tenants, container
# mem-limit, current talkies/sdcpp load state).
#
# Uses `docker logs` against the wrapper container, so this test is only
# meaningful when the runner has docker socket access to the live stack.
_llamacpp_test_ctx_auto_resolved() {
    local container="$1" tag="$2"
    if ! docker inspect "$container" >/dev/null 2>&1; then
        echo "  SKIP: ${tag} container ${container} not running"
        return 0
    fi
    local line chosen rem
    # The resolver logs two lines on every spawn — pick the most recent.
    line=$(docker logs "$container" 2>&1 \
        | grep -E 'ctx-size auto math:' \
        | tail -1)
    if [ -z "$line" ]; then
        echo "  FAIL: ${tag} no 'ctx-size auto math:' log line — resolver did not run"
        return 1
    fi
    chosen=$(echo "$line" | sed -nE 's/.*chosen=([0-9]+).*/\1/p')
    if [ -z "$chosen" ]; then
        echo "  FAIL: ${tag} could not parse chosen=N from resolver log"
        echo "  line: $line"
        return 1
    fi
    if [ "$chosen" -lt 16384 ]; then
        echo "  FAIL: ${tag} resolver picked chosen=$chosen, below floor 16384"
        return 1
    fi
    rem=$(( chosen % 1024 ))
    if [ "$rem" -ne 0 ]; then
        echo "  FAIL: ${tag} resolver picked chosen=$chosen, not a multiple of 1024"
        return 1
    fi
    echo "OK: ${tag} ctx-size auto resolved to $chosen (≥ floor, %1024 == 0)"
}

test_llamacpp_cpu_ctx_auto_resolved() {
    _llamacpp_cpu_enabled || { echo "  SKIP: LLAMACPP not enabled"; return 0; }
    _llamacpp_test_ctx_auto_resolved "aigate-llamacpp-1" "llamacpp-cpu"
}

test_llamacpp_cuda_ctx_auto_resolved() {
    _llamacpp_cuda_enabled || { echo "  SKIP: LLAMACPP_CUDA not enabled"; return 0; }
    _llamacpp_test_ctx_auto_resolved "aigate-llamacpp-cuda-1" "llamacpp-cuda"
}

ALL_TESTS+=(
    test_llamacpp_cpu_models_list
    test_llamacpp_cpu_captcha_ocr
    test_llamacpp_cpu_pdf_ocr
    test_llamacpp_cpu_url_captcha
    test_llamacpp_cpu_layout
    test_llamacpp_cpu_table_rec
    test_llamacpp_cpu_pdf_data_url
    test_llamacpp_cpu_pdf_multipage
    test_llamacpp_cpu_pdf_layout
    test_llamacpp_cpu_pdf_block_rejected
    test_llamacpp_cpu_pdf_dpi_negative_one
    test_llamacpp_cpu_ctx_auto_resolved
    test_llamacpp_cuda_models_list
    test_llamacpp_cuda_captcha_ocr
    test_llamacpp_cuda_pdf_ocr
    test_llamacpp_cuda_url_captcha
    test_llamacpp_cuda_layout
    test_llamacpp_cuda_table_rec
    test_llamacpp_cuda_pdf_data_url
    test_llamacpp_cuda_pdf_multipage
    test_llamacpp_cuda_pdf_layout
    test_llamacpp_cuda_pdf_block_rejected
    test_llamacpp_cuda_pdf_dpi_negative_one
    test_llamacpp_cuda_ctx_auto_resolved
)
