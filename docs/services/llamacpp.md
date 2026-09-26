# llamacpp / llamacpp-cuda — GGUF + vision VLMs

> Profile flags: `LLAMACPP=1` (CPU) / `LLAMACPP_CUDA=1` (NVIDIA GPU).
> Sister service to vllm-wrap; serves GGUF and supports vision models via `mmproj`.

Supervised `llama-server` wrapper mirroring the vllm-wrap lifecycle surface (`/api/ps`, `DELETE /api/ps/{model_id}`, `POST /unload`, idle-TTL unload, one-resident-model-at-a-time supervisor) but the underlying engine is `llama-server` from llama.cpp, the weights are GGUF, and **vision models are supported via `mmproj`**. Picks up the slack from vllm-wrap's weak vision-VLM support on CPU and serves any Qwen3-VL-class document model cleanly on either hardware.

Base images pinned by digest: `ghcr.io/ggml-org/llama.cpp:server@sha256:7d02b045...` (CPU) and `:server-cuda@sha256:841b199a...` (CUDA), both upstream build `b9603` (rev `ba1df050f3dc78...`). Wrapper code lives in `llamacpp/src/llamacpp_wrap/` and mirrors `vllm/src/vllm_wrap/` 1-for-1.

## Default model — Surya OCR 2

`datalab-to/surya-ocr-2-gguf` (revision `6a3a4c30e5e74...`, ~650M params, Apache-2.0 code / modified AI Pubs Open Rail-M weights, free for research / personal / startups <$5M ARR). One VLM that handles **OCR**, **layout detection**, and **table recognition** — behaviour switches on the **prompt string**, not on the model.

> **Surya prompts are training-time contracts.** Paraphrasing them produces unpredictable output mode (the model emits a layout-JSON instead of OCR-HTML when given a generic "transcribe this" prompt). Pass the literal strings below verbatim.

### Available slugs

- `LLAMACPP=1` → `local-llamacpp-surya-ocr-2` (CPU)
- `LLAMACPP_CUDA=1` → `local-llamacpp-cuda-surya-ocr-2` (CUDA — strongly preferred for interactive workloads)

### The 4 prompt modes

| Task | Prompt (verbatim) | Output shape |
|---|---|---|
| **Block OCR** | `OCR this block image to HTML.` | HTML for one tight crop. Use after layout-segmenting a page; equivalent to `RecognitionPredictor`'s block mode. |
| **Full-page OCR** | `OCR this image to HTML. Each block is a div with data-label and data-bbox (x0 y0 x1 y1, normalized 0-1000).` | Whole page OCR'd in one call, blocks tagged with `data-label` + `data-bbox`. Equivalent to `RecognitionPredictor`'s default full-page mode. |
| **Layout detection** | `Output the layout of this image as JSON. Each entry is a dict with "label", "bbox", and "count" fields. Bbox is x0 y0 x1 y1, normalized 0-1000.` | JSON array of `{label, bbox, count}` describing reading-order-sorted blocks. Labels are the canonical Surya set: `Text`, `SectionHeader`, `Caption`, `Footnote`, `Equation`, `ListGroup`, `Picture`, `Table`, `Form`, `PageHeader`, `PageFooter`, `TableOfContents`, `Figure`, `Code`, `Bibliography`, `BlankPage`, `ChemicalBlock`, `Diagram`. |
| **Table recognition** | `Output the table rows then columns as JSON. Each entry is a dict with "label" ("Row" or "Col") and "bbox" (x0 y0 x1 y1, normalized 0-1000).` | JSON array of `{label, bbox}` where label is `Row` or `Col`. Geometric intersections give the cells. |

## Which mode for which job

| You have… | You want… | Use this mode | Why |
|---|---|---|---|
| One tight crop of text (captcha, single-line clip, one paragraph) | The transcription | **Block OCR** | Smallest prompt → cheapest call. Cropping has done the layout work for you. |
| A full document page with mixed content | Everything in one call | **Full-page OCR** | Single call returns HTML with per-block bboxes. Works well on clean / single-column pages. |
| A full document page with **dense / complex** layout | Higher-accuracy text in reading order | **Layout → crop → Block OCR per block** | Slower but more accurate on multi-column / heavy-illustration / scan-quality pages. Also lets you skip `Picture` / `Figure` / `BlankPage` blocks. |
| A full page; just want to know WHERE blocks are | Block positions, no text yet | **Layout only** | Use to budget downstream OCR cost (the `count` field per block) or to route specific blocks differently (e.g. Tables → table-rec, Text → OCR, Picture → image-captioning). |
| A page with a table on it | The table's grid structure | **Layout → crop the `Table` block → Table recognition** | `table_rec` on the raw full page produces unreliable output. You **must** crop to a tight table region first. |
| Multi-page PDF | All pages OCR'd | **Send the PDF directly** in `image_url.url` (data URL or http URL) — the wrapper rasterizes each page, runs the per-page chat completion, and stitches the responses. Per-mode stitching: full-page → `<div data-page="N">` wrappers, layout / table → `"page": N` field per JSON entry, block → 400 (single-image only, crop first). See the "PDF input — server-side handling" section below. | Or pre-rasterize client-side and loop one PNG per call if you need fine-grained control over which pages to send. |

## Workflow recipes

### Recipe A — one-call full-page OCR (simplest)

```
rasterize page (96 DPI) → POST /v1/chat/completions w/ full-page OCR prompt → HTML
```

Single call. Good first try. If accuracy is poor on complex layouts, switch to Recipe B.

### Recipe B — layout-then-OCR per block (higher accuracy)

```
rasterize page (96 DPI)
├─ POST /v1/chat/completions w/ layout prompt → JSON [{label, bbox, count}, ...]
├─ for each block where label in {Text, SectionHeader, Caption, Footnote,
│                                   ListGroup, PageHeader, PageFooter,
│                                   Code, Bibliography}:
│     crop image to bbox → POST /v1/chat/completions w/ block OCR prompt → HTML
├─ for each block where label == "Table":
│     crop image to bbox → POST /v1/chat/completions w/ table-rec prompt
│         → JSON [{label: "Row"|"Col", bbox}, ...]
├─ skip blocks where label in {Picture, Figure, Diagram, BlankPage, ChemicalBlock}
│     (they're not text — caption them separately via a different VLM if needed)
└─ assemble HTML in reading-order (layout returns blocks pre-sorted)
```

This is what the upstream `surya-ocr` Python lib does when you call `RecognitionPredictor` with `full_page=False`. If you don't want to implement it yourself, point the Python lib at our endpoint (see "Upstream Python lib drop-in" below).

### Recipe C — multi-page PDF, mixed pipeline

```
for page in pages of PDF:
    rasterize page (96 DPI)
    use Recipe A on simple pages, Recipe B on dense/complex pages
    (heuristic: if layout-prompt returns >5 blocks OR any block has label
    in {Table, MultiColumn}, switch to Recipe B for that page)
    accumulate HTML
```

Don't try to send a whole multi-page PDF in one call — Surya is single-image. Rasterize per-page client-side.

## curl recipes — one per prompt mode

Image input accepts both `data:image/...;base64,...` inline payloads AND `http(s)://...` URLs (the wrapper transparently fetches URLs and rewrites them before forwarding — `llama-server`'s `mtmd` only accepts data URLs natively).

### Block OCR — one tight crop

```bash
curl http://localhost:4000/v1/chat/completions \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d "{
    \"model\": \"local-llamacpp-cuda-surya-ocr-2\",
    \"max_tokens\": 1024,
    \"temperature\": 0.0,
    \"messages\": [{
      \"role\": \"user\",
      \"content\": [
        {\"type\": \"image_url\", \"image_url\": {\"url\": \"data:image/png;base64,$(base64 -w0 crop.png)\"}},
        {\"type\": \"text\", \"text\": \"OCR this block image to HTML.\"}
      ]
    }]
  }"
# → assistant content: HTML for that crop. Math wrapped in <math>...</math>,
#   tables in <table>...</table>, prose in <p> / <h1>-<h5> / <div> etc.
```

### Full-page OCR — whole document image

```bash
curl http://localhost:4000/v1/chat/completions \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d "{
    \"model\": \"local-llamacpp-cuda-surya-ocr-2\",
    \"max_tokens\": 4096,
    \"temperature\": 0.0,
    \"messages\": [{
      \"role\": \"user\",
      \"content\": [
        {\"type\": \"image_url\", \"image_url\": {\"url\": \"https://example.com/scan.png\"}},
        {\"type\": \"text\", \"text\": \"OCR this image to HTML. Each block is a div with data-label and data-bbox (x0 y0 x1 y1, normalized 0-1000).\"}
      ]
    }]
  }"
# → assistant content:
#   <div data-label="SectionHeader" data-bbox="100 50 900 90">Heading</div>
#   <div data-label="Text" data-bbox="100 100 900 400"><p>Paragraph...</p></div>
#   <div data-label="Picture" data-bbox="100 410 900 700"></div>
#   ...
```

### Layout detection — no OCR, just block positions

```bash
curl http://localhost:4000/v1/chat/completions \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d "{
    \"model\": \"local-llamacpp-cuda-surya-ocr-2\",
    \"max_tokens\": 1024,
    \"temperature\": 0.0,
    \"messages\": [{
      \"role\": \"user\",
      \"content\": [
        {\"type\": \"image_url\", \"image_url\": {\"url\": \"https://example.com/scan.png\"}},
        {\"type\": \"text\", \"text\": \"Output the layout of this image as JSON. Each entry is a dict with \\\"label\\\", \\\"bbox\\\", and \\\"count\\\" fields. Bbox is x0 y0 x1 y1, normalized 0-1000.\"}
      ]
    }]
  }"
# → assistant content (JSON array, reading-order-sorted):
#   [
#     {"label": "SectionHeader", "bbox": "100 50 900 90", "count": 5},
#     {"label": "Text",          "bbox": "100 100 900 400", "count": 50},
#     {"label": "Picture",       "bbox": "100 410 900 700", "count": 0},
#     {"label": "Table",         "bbox": "100 720 900 1000", "count": 30}
#   ]
# `count` is the model's per-block OCR-token estimate (rounded to 50) —
# pass it (plus a safety margin) as max_tokens when you feed each crop
# back through Block OCR.
```

### Table recognition — rows + columns of a table image

```bash
curl http://localhost:4000/v1/chat/completions \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d "{
    \"model\": \"local-llamacpp-cuda-surya-ocr-2\",
    \"max_tokens\": 1024,
    \"temperature\": 0.0,
    \"messages\": [{
      \"role\": \"user\",
      \"content\": [
        {\"type\": \"image_url\", \"image_url\": {\"url\": \"data:image/png;base64,$(base64 -w0 table-crop.png)\"}},
        {\"type\": \"text\", \"text\": \"Output the table rows then columns as JSON. Each entry is a dict with \\\"label\\\" (\\\"Row\\\" or \\\"Col\\\") and \\\"bbox\\\" (x0 y0 x1 y1, normalized 0-1000).\"}
      ]
    }]
  }"
# → assistant content (JSON array):
#   [
#     {"label": "Row", "bbox": "0 0 1000 100"},
#     {"label": "Row", "bbox": "0 100 1000 200"},
#     ...
#     {"label": "Col", "bbox": "0 0 333 1000"},
#     {"label": "Col", "bbox": "333 0 666 1000"},
#     ...
#   ]
# Cell geometry is the intersection of every Row × every Col bbox. For
# full HTML (handles spanning cells + header rows) use the upstream
# Surya Python lib's TableRecPredictor.predict_full() — see the bottom
# of this doc for the env wiring.
```

## Practical tips

### Sampling settings — set these every call

| Field | Value | Why |
|---|---|---|
| `temperature` | `0.0` | Surya is deterministic OCR / layout, not creative. Non-zero temp introduces hallucinated characters. |
| `top_p` | `1.0` (or unset) | Same reason. Greedy decode is correct here. |
| `max_tokens` | Task-dependent — see below | Truncation = silent OCR loss. Budget generously. |

### Sizing `max_tokens` per task

| Task | Suggested `max_tokens` | Notes |
|---|---|---|
| Block OCR — captcha / single line | 64-128 | Truncation looks like `"AIGATE20"...`. |
| Block OCR — one paragraph | 256-512 | Roughly 4 chars/token in English HTML. |
| Block OCR — one column | 1024-2048 | Long blocks. |
| Full-page OCR | 4096-8192 | A4 page of body prose ≈ 3000 tokens of HTML. |
| Layout detection | 512-1024 | JSON is compact; one entry per block. |
| Table recognition | 512-1024 | One entry per Row + one per Col. |

When in doubt, oversize — unused budget is free, truncation is silent corruption. For Recipe B (layout-then-OCR), the layout response includes a `count` field per block — pass `max_tokens = count + 50` on the per-block OCR follow-up.

### Image preprocessing (you do this — Surya doesn't)

- **Deskew** old / phone-photo scans (a few degrees of tilt drops accuracy noticeably). `opencv-python` `cv2.minAreaRect` + `cv2.warpAffine`, or the `deskew` pip package.
- **Denoise** speckle on faxes / dot-matrix prints. `cv2.fastNlMeansDenoising` works for most cases.
- **Binarize** very-low-contrast scans. `cv2.adaptiveThreshold` (Otsu) helps when text is faint against a noisy background.
- Do NOT upscale to "help" Surya. The model resamples internally and higher input DPI inflates prompt tokens quadratically without quality gain. Keep PDF rasterization at 96 DPI.
- Photos / natural scenes are off-spec — Surya is trained for documents.

### Parsing the responses (defensive)

- Layout / table-rec JSON occasionally has trailing whitespace, a stray BOM, or a tiny prefix before the array. Regex-extract: `re.search(r'\[.*\]', content, re.DOTALL)` then `json.loads(match.group(0))` is the robust pattern. The test harness in `tests/test_llamacpp.sh` uses this.
- OCR HTML uses a **restricted tag set**: `<math>`, `<br>`, `<i>`, `<b>`, `<u>`, `<del>`, `<sup>`, `<sub>`, `<table>`, `<tr>`, `<td>`, `<th>`, `<thead>`, `<tbody>`, `<p>`, `<pre>`, `<h1>`-`<h5>`, `<ul>`, `<ol>`, `<li>`, `<input>`, `<a>`, `<span>`, `<img>`, `<hr>`, `<div>`, `<small>`, `<caption>`, `<strong>`, `<big>`, `<code>`, `<chem>`. Math is wrapped in `<math>...</math>` with **KaTeX-compatible LaTeX** inside.
- `bbox` is a space-separated string `"x0 y0 x1 y1"` normalized to **0-1000** (not pixels). Convert to image coords: `px = (bbox_value / 1000) * image_dimension_in_pixels`.

### Common gotchas

- **Paraphrased prompts → wrong output mode.** A generic "transcribe this" prompt usually returns a layout JSON. Copy the prompt strings verbatim from the table at the top.
- **`table_rec` on a full page is unreliable.** The prompt expects a tight crop of just the table. Run layout first, find the `Table` block, crop, THEN table-rec.
- **Image must be valid base64 + correct MIME.** `data:image/png;base64,...` for PNG, `data:image/jpeg;base64,...` for JPEG. The wrapper auto-detects MIME for `http(s)://` URLs (via Content-Type or file extension); for `data:` URLs you set it.
- **`http(s)://` URLs must be reachable from inside the docker network**, not just from your laptop. From outside the network, `localhost:4000` works (LiteLLM router); from inside, use `nginx:4000` or the target service's container hostname. The wrapper has the same network view as other in-network services.
- **URL fetch is hard-capped:** 32 MB body limit, 30 s timeout, follow_redirects on. Anything else returns HTTP 400 / 413 from the wrapper.
- **Surya only does documents.** Photos / natural scenes / arbitrary screenshots — accuracy degrades. For those, use a general vision model (Anthropic / OpenAI / openrouter routes).
- **No streaming for OCR.** llama-server supports it on the wire but Surya's JSON / HTML outputs are post-processed end-to-end client-side, so you gain nothing from `stream: true`. Leave it off.

## Image input — data URLs OR http(s)

The wrapper accepts both, and rewrites the request before forwarding to `llama-server` (which only natively accepts `data:` URLs):

```jsonc
"content": [
  // EITHER inline base64:
  { "type": "image_url", "image_url": { "url": "data:image/png;base64,iVBORw0K..." } },
  // OR any http(s) URL the wrapper can reach from inside the docker network:
  { "type": "image_url", "image_url": { "url": "https://example.com/page.png" } },
  { "type": "image_url", "image_url": { "url": "http://hybrids3:8080/uploads/scan-1.png" } },
  { "type": "image_url", "image_url": { "url": "http://nginx:4000/storage/uploads/scan-1.png" } },
  { "type": "text", "text": "<one of the prompts from the table above>" }
]
```

URL fetching is hard-capped at **32 MB / 30 s** per image, follows redirects, and trusts an explicit `image/*` Content-Type when present (falls back to the URL extension). Anything else (non-`http(s)`, non-`data:`, missing) is passed through untouched so the underlying backend's own error handling kicks in.

## PDF input — server-side handling

The wrapper accepts PDFs directly via the same `image_url.url` field. When the `surya-ocr-2` model declares `"handler": "surya"` in its `models.{cpu,cuda}.json` entry, the wrapper's Surya handler:

1. Detects PDF input — either a `data:application/pdf;base64,...` URL or an `http(s)://...` URL whose fetched body returns `Content-Type: application/pdf` (or `.pdf` extension fallback).
2. Probes each page's native DPI via `pdfimages -list` (max DPI of any embedded raster image on that page; vector-only pages fall back to 96 DPI).
3. Rasterizes each page via `pdftoppm -r <chosen_dpi>`.
4. Detects the Surya prompt mode from the text content (block / page / layout / table-rec).
5. Loops the chat completion per page with the same prompt, replacing the PDF reference with the rasterized PNG.
6. Stitches the per-page responses per mode:
   - **Block OCR** — rejected with HTTP 400 (single-image only; crop client-side first).
   - **Full-page OCR** — per-page HTML concatenated, each wrapped in `<div data-page="N">...</div>`.
   - **Layout detection** — per-page JSON arrays merged, every entry gains a `"page": N` field.
   - **Table recognition** — same as layout.
   - **Unknown mode** — plaintext concat with `<!-- page N -->` separators.
7. Returns one final OpenAI-shape chat completion. Extra response fields: `x_surya_pages` (page count), `x_surya_mode` (detected mode), `page_errors` (only present when one or more pages failed — does NOT abort the whole request).

### `dpi_rescale_to` (per-request OpenAI extension)

Caller controls the rasterization DPI via the top-level body field `dpi_rescale_to` (set via `extra_body` on official OpenAI SDK clients):

| Value | Meaning |
|---|---|
| `96` (default) | Cap at 96 DPI. Renders at `min(96, native_dpi)` per page — only downscales, never upscales. |
| `N > 0` | Cap at N DPI. Renders at `min(N, native_dpi)` per page. |
| `-1` | Skip rescaling. Render at the page's native DPI (vector-only pages still fall back to 96). |

Hard cap: 600 DPI (safety bound — beyond this the vision encoder produces an impractically large input). Anything else returns HTTP 400.

### curl recipes — PDF input

```bash
# Single-page PDF as data URL, full-page OCR
PDF_B64=$(base64 -w0 doc.pdf)
curl http://localhost:4000/v1/chat/completions \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d "{
    \"model\": \"local-llamacpp-cuda-surya-ocr-2\",
    \"max_tokens\": 4096,
    \"temperature\": 0.0,
    \"messages\": [{
      \"role\": \"user\",
      \"content\": [
        {\"type\": \"image_url\", \"image_url\": {\"url\": \"data:application/pdf;base64,$PDF_B64\"}},
        {\"type\": \"text\", \"text\": \"OCR this image to HTML. Each block is a div with data-label and data-bbox (x0 y0 x1 y1, normalized 0-1000).\"}
      ]
    }]
  }"
# → assistant content:
#   <div data-page="1">
#     <div data-label="Text" data-bbox="..."><p>...</p></div>
#   </div>
# Response top-level: x_surya_pages=1, x_surya_mode="page"

# Multi-page PDF via http URL, layout mode, default DPI (96 cap)
curl http://localhost:4000/v1/chat/completions \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "local-llamacpp-cuda-surya-ocr-2",
    "max_tokens": 4096,
    "temperature": 0.0,
    "messages": [{
      "role": "user",
      "content": [
        {"type": "image_url", "image_url": {"url": "https://example.com/doc.pdf"}},
        {"type": "text", "text": "Output the layout of this image as JSON. Each entry is a dict with \"label\", \"bbox\", and \"count\" fields. Bbox is x0 y0 x1 y1, normalized 0-1000."}
      ]
    }]
  }'
# → assistant content (JSON array, every entry has a `page` field):
#   [{"label":"SectionHeader","bbox":"...","count":5,"page":1},
#    {"label":"Text",         "bbox":"...","count":50,"page":1},
#    {"label":"Text",         "bbox":"...","count":40,"page":2},
#    ...]

# High-detail scan — render at native DPI (skip the 96 cap)
curl http://localhost:4000/v1/chat/completions \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d "{
    \"model\": \"local-llamacpp-cuda-surya-ocr-2\",
    \"max_tokens\": 8192,
    \"temperature\": 0.0,
    \"dpi_rescale_to\": -1,
    \"messages\": [...]
  }"

# Force a specific cap (e.g. for dense footnotes / math)
curl ... -d '{..., "dpi_rescale_to": 150, ...}'
```

### Pre-rasterizing client-side (still supported)

If you'd rather pre-rasterize and send individual PNGs (skipping the wrapper's PDF handler entirely), the recipe is unchanged: render at 96 DPI and POST per page:

```bash
pdftoppm -png -r 96 -f 1 -l 1 doc.pdf out
# or in Python:
pip install pdf2image
python -c 'from pdf2image import convert_from_path; convert_from_path("doc.pdf", dpi=96)[0].save("page-1.png")'
```

Pick the server-side path when you don't want pagination logic in your client. Pick client-side when you want fine-grained control over which pages to send, or when you need to process pages in parallel across multiple llamacpp replicas.

### PDF handling is per-model

Server-side PDF orchestration is opt-in via the `"handler": "surya"` field in the model registry — it applies only to `surya-ocr-2`. Other GGUF models (future text-only LLMs, audio-input VLMs, etc.) added to `models.{cpu,cuda}.json` will NOT auto-rasterize PDFs; PDF input on those models is forwarded to llama-server and will fail there. To add a handler for a different document model, drop a new `llamacpp/src/llamacpp_wrap/handlers/<name>.py` implementing the `Handler` protocol from `handlers/base.py` and register it under that name in `handlers/__init__.py`.

## Throughput — what to expect

Measured end-to-end through LiteLLM → wrapper → `llama-server` on the actual test fixtures.

### CUDA (RTX-class single-GPU)

| Task | Image | Wall clock per call |
|---|---|---|
| Captcha OCR (block) | 400×120 PNG | ~3 s |
| Full-page OCR | A4 page @ 96 DPI (~794×1123) | ~6-12 s |
| Layout detection | A4 page @ 96 DPI | ~5-10 s |
| Table recognition | Table-only crop | ~3-6 s |

Suitable for interactive workloads. Idle TTL unload returns VRAM to other CUDA services (ollama / sdcpp / talkies / vllm) — first request after eviction pays the model-load cost (~5-10 s).

### CPU (4-core container, `--n-gpu-layers 0`)

| Task | Image | Wall clock per call |
|---|---|---|
| Captcha OCR (block) | 400×120 PNG | ~24 s |
| URL-fetch captcha (block) | same, fetched from hybrids3 first | ~24 s |
| Full-page OCR | A4 page @ 96 DPI (~794×1123, ~1100 prompt tokens) | ~2-3 min |
| Layout detection | A4 page @ 96 DPI | ~2 min |
| Table recognition | Table PDF @ 96 DPI | ~2 min |
| Full-page OCR | A4 page @ **200 DPI** (~1654×2339, ~3940 prompt tokens) | ~7+ min (avoid) |

Suitable for **batch / overnight document processing**, sub-second small-image OCR (captchas, single-line crops). Not suitable for interactive A4-page work.

### Slug picker by workload

| Workload | Slug | Why |
|---|---|---|
| Interactive UI ("OCR this page now") | `local-llamacpp-cuda-surya-ocr-2` | A4 page OCR is ~6-12 s on CUDA |
| Batch / overnight document processing | either, CPU is fine | A4 page OCR is ~2-3 min on a 4-core CPU container |
| Small images (captchas, signature crops, single-line clips) | either | <30 s on CPU, ~3 s on CUDA — CPU is fine for short queues |
| Real-time A4-page work | CUDA only | CPU is too slow (~minutes per page) |

## Endpoints (internal API)

| Endpoint                                  | URL (via LiteLLM)                       | Auth                              |
|---|---|---|
| Chat (OpenAI-compat, vision-capable)      | `POST /v1/chat/completions`             | `Bearer $LITELLM_MASTER_KEY`      |
| Completions (legacy OpenAI)               | `POST /v1/completions`                  | `Bearer $LITELLM_MASTER_KEY`      |
| Embeddings                                | `POST /v1/embeddings`                   | `Bearer $LITELLM_MASTER_KEY`      |
| Health (in-network)                       | `GET llamacpp{,-cuda}:8000/healthz`     | none                              |
| Loaded model (in-network)                 | `GET llamacpp{,-cuda}:8000/api/ps`      | none                              |
| Unload one (in-network — resource_manager)| `DELETE llamacpp{,-cuda}:8000/api/ps/{id}` | none                            |
| Unload all (in-network)                   | `POST llamacpp{,-cuda}:8000/unload`     | none                              |

## Configuration

Every tunable has a CPU (`LLAMACPP_*`) and CUDA (`LLAMACPP_CUDA_*`) counterpart with the same meaning and default:

| Tunable | Default | Notes |
|---|---|---|
| `LLAMACPP_MODEL_TTL` / `LLAMACPP_CUDA_MODEL_TTL` | `600` | Seconds idle before `llama-server` is killed (`-1` disables) |
| `LLAMACPP_SWEEPER_INTERVAL` / `LLAMACPP_CUDA_SWEEPER_INTERVAL` | `60` | How often the idle sweeper checks (seconds) |
| `LLAMACPP_LOAD_TIMEOUT` / `LLAMACPP_CUDA_LOAD_TIMEOUT` | `600` | Max time to wait for `/health` after spawning `llama-server` |
| `LLAMACPP_REQUEST_TIMEOUT` / `LLAMACPP_CUDA_REQUEST_TIMEOUT` | `300` | Per-request proxy timeout |
| `LLAMACPP_LOG_LEVEL` / `LLAMACPP_CUDA_LOG_LEVEL` | `INFO` | Wrapper log level |
| `LLAMACPP_PRELOAD` / `LLAMACPP_CUDA_PRELOAD` | _empty_ | Pre-spawn this model_id at boot |
| `LLAMACPP_MEM_LIMIT` / `LLAMACPP_CUDA_MEM_LIMIT` | `12g` | Container memory limit |
| `LLAMACPP_CPUS` / `LLAMACPP_CUDA_CPUS` | `4.0` | Container CPU limit |
| `DATA_DIR_LLAMACPP` | `${DATA_DIR}/llamacpp` | Bind-mount root for the wrapper's `/data` dir. Holds the flat HF-repo layout under `models/<org>/<repo>/<files>` (no blobs/snapshots dedup) — the `llamacpp-pull` sidecar populates this via `huggingface-cli download <repo> --local-dir <path>` reading from BOTH `llamacpp/models.cpu.json` and `models.cuda.json` (union of `repo` fields). Both CPU and CUDA wrappers share the same files. |

## Auto-sizing `--ctx-size` to available memory

Models can opt into supervisor-side auto-sizing of `--ctx-size` against probed free VRAM (CUDA) or RAM (CPU) by passing the literal string `"auto"` instead of an integer:

```jsonc
"llama_server_args": [
  "--ctx-size", "auto",
  "--parallel", "4",
  "--n-gpu-layers", "999"
]
```

At spawn time (every model load — fresh boot, swap from sibling eviction, or post-idle-TTL reload) the supervisor:

1. Probes free memory via `nvidia-smi --query-gpu=memory.free` on CUDA, or `MemAvailable` from `/proc/meminfo` on CPU.
2. Subtracts the model's declared weights footprint and a safety margin (CUDA-graph alloc, batch buffers, Mamba-SSM state, mmproj scratch — covers what the per-token formula can't model).
3. Divides the remaining headroom by the per-token KV cache cost.
4. Caps at the model's trained max context (`max_ctx_size` — going past this wastes memory without quality gain).
5. Floors at `LLAMACPP_WRAP_CTX_FLOOR` (default 16384) so a tight memory situation doesn't silently shrink ctx to uselessness.
6. Rounds down to the nearest multiple of 1024.

The resolved value is logged at INFO level for every spawn so you can verify what was picked:

```
ctx-size auto math: free=10.19 GiB, weights=2.00 GiB, safety=1.00 GiB,
                    kv_per_tok=12288 B → headroom for 628053 tokens;
                    model_max=262144, floor=16384, chosen=262144
ctx-size auto → 262144 (model_id=datalab-to/surya-ocr-2-gguf)
spawning: /app/llama-server -m ... --ctx-size 262144 --parallel 4 ...
```

### Per-model fields used by the resolver

All optional. Missing fields fall back to conservative defaults:

| Field | Default | Description |
|---|---|---|
| `max_ctx_size` | 16384 | Model's trained context ceiling. For Surya OCR 2 (`qwen3_5_text` architecture) the model card declares `max_position_embeddings=262144`. |
| `kv_bytes_per_token` | 16384 (16 KiB) | Per-token KV cache cost. For pure-attention transformers: `2 (K+V) × n_layers × n_kv_heads × head_dim × sizeof(cache_dtype)`. For **hybrid Mamba+attention** models (Surya / Qwen3.5 generation) count only full-attention layers — linear/Mamba blocks have constant state. **Surya math**: 6 full-attn layers (24 / `full_attention_interval=4`) × 2 KV heads × 256 head_dim × 2 (K+V) × 2 B (fp16) = **12288 B/token**. |
| `weights_estimate_bytes` | sum of GGUF + mmproj file sizes on disk | Total memory consumed by weights when fully loaded. Used to budget what's left for the KV cache. Padding above on-disk size accounts for CUDA-side alignment + scratch. |

### Per-deployment overrides (env vars in `.env`, per-variant)

Each setting has separate `LLAMACPP_*` (CPU) and `LLAMACPP_CUDA_*` (CUDA) overrides — the operator-facing names without the `_WRAP_` infix that docker-compose translates to the in-container `LLAMACPP_WRAP_*` form:

| Operator var (in `.env`) | In-container var | Default | Description |
|---|---|---|---|
| `LLAMACPP_CTX_FLOOR` / `LLAMACPP_CUDA_CTX_FLOOR` | `LLAMACPP_WRAP_CTX_FLOOR` | `16384` | Never pick a smaller ctx than this. Even if the probe says we don't have room, the supervisor falls back to this and lets the spawn either succeed (under-budget OK) or fail loudly at load. |
| `LLAMACPP_CTX_SAFETY_MARGIN_BYTES` / `LLAMACPP_CUDA_CTX_SAFETY_MARGIN_BYTES` | `LLAMACPP_WRAP_CTX_SAFETY_MARGIN_BYTES` | `1073741824` (1 GiB) | Subtracted from probed free memory before dividing by KV cost. Bigger margin = smaller chosen ctx but less risk of OOM-at-first-request. Bump this when other CUDA tenants share the same GPU; trim it on a dedicated card. |

### Fallback behavior

If the probe fails entirely (no `nvidia-smi`, no `/proc/meminfo`, command timeout, unparseable output) the supervisor falls back to `min(max_ctx_size, max(floor*2, floor))` and logs a warning. Picks something usable rather than crashing the spawn.

If the probe succeeds but probed memory is already under the weights + safety budget (i.e. another CUDA tenant is eating most of the card), it falls back to `floor` and logs the deficit. Better to attempt the spawn at a small ctx (which often still works since the safety margin is conservative) than refuse.

## Auto-sizing `--threads` to the CPU limit

CPU models pass `"--threads", "auto"`. At spawn time the supervisor replaces it with the number of CPUs the container may use: the cgroup quota from `/sys/fs/cgroup/cpu.max` (set by `LLAMACPP_CPUS`), capped by the scheduler affinity. llama.cpp's own `--threads -1` counts every host core and ignores the quota. Running more threads than the quota allows makes the kernel throttle the workers at each sync point, and decoding slows by an order of magnitude. The resolved value is logged as `threads auto → N`.

## Adding a new model

Per-model GGUF + mmproj filenames + `llama-server` extra args are declared in `llamacpp/models.{cpu,cuda}.json`.

1. Append a new entry to both JSONs (or one if it's only relevant for one hardware). Required fields: `repo`, `gguf_file`, `endpoints`. Optional: `revision`, `mmproj_file` (vision models), `llama_server_args` (e.g. `--ctx-size`, `--n-gpu-layers`, `--parallel`).
2. Bring the stack down and back up — the `llamacpp-pull` sidecar will fetch the new repo on next boot.
3. Add a corresponding LiteLLM provider entry to `litellm/config/providers/llamacpp{,-cuda}.yaml` and regenerate `config.yaml` via `make build-config`.
4. If the new model is heavy enough to need its own resource_manager group, add a `_LLAMACPP_MODELS` entry in `litellm/callbacks/resource_manager.py` so the `DELETE /api/ps/{model_id}` eviction fires on it.

## Upstream Python lib drop-in

Surya's `surya-ocr` pip package does the full orchestration (image pre-proc, prompt construction per task, multi-call routing — layout → crop → per-block OCR — and output parsing into typed dataclasses). It also runs Surya's small torch text-line-detector locally (not VLM). Point it at our endpoint:

```bash
pip install surya-ocr
export SURYA_INFERENCE_BACKEND=vllm   # OpenAI-compatible client; works for ours too
export SURYA_INFERENCE_URL=http://localhost:4000/v1
# (No SURYA_INFERENCE_MODEL env in the lib — the upstream client hardcodes
# the model id. Easiest workaround: register `local-llamacpp-cuda-surya-ocr-2`
# as a LiteLLM alias of the slug Surya defaults to, or run a tiny rewrite
# proxy. For most use cases the raw curl examples above are simpler.)
surya_ocr docs/page.pdf
```
