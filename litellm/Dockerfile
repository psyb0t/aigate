# Build stage: pull official litellm image
# v1.104.8: bumped from v1.104.0.
#  * Security: carries the GHSA-w4c7-34wj-hqm8 fix (1.104.8). Signed with the
#    cosign key from upstream commit e82a3c6, which replaced the key likely
#    exposed in the v1.107.0 release compromise.
#  * Newest v1.104.x release, and it clears the seven-day age gate (2026-11-05).
#
# v1.104.0 — bumped from v1.83.14-stable.patch.2.
#  * MCP OAuth: the v1.83 line only allowed a loopback redirect_uri, so LiteLLM's
#    own /ui/mcp/oauth/callback was rejected (400 invalid_request) and any MCP
#    server with auth_type oauth2 could not be authorised from the UI. Same-origin
#    callbacks landed in v1.85.0.
#  * Security: v1.104.0 carries fixes for advisories that affect v1.83.14 —
#    CVE-2026-84377 (fixed 1.94.0) and GHSA-g5ff-637f-6q2m (fixed 1.95.0) — plus
#    the 1.93/1.95/1.96/1.101 hardening. It is not in the affected range of
#    GHSA-7hp6-4w63-5g45 (v1.101.0-1.103.0).
#  * Newest release that clears the seven-day age gate (2026-10-03).
# CVE-2026-42208 (pre-auth SQLi, fixed in v1.83.7+) stays fixed.
FROM ghcr.io/berriai/litellm:v1.104.8@sha256:6cc08e60be3e4ebf0cfb41ef23aed97e9ba4f61702d1e95e533f47ee6d67865f AS base

# ── Extra Python packages ────────────────────────────────────────────────────
# The upstream image has no pip or uv. uv is copied in for this one install
# and removed afterwards. Both pins are older than the seven-day age gate.
COPY --from=ghcr.io/astral-sh/uv:0.12.17@sha256:10787c682e4184e4f290de1171fd4703dc63de99221f10fe1c99002ce7fa9acc /uv /tmp/uv
COPY requirements-extra.txt /tmp/requirements-extra.txt
RUN /tmp/uv pip install --python /app/.venv/bin/python --no-cache --require-hashes \
        -r /tmp/requirements-extra.txt \
    && rm /tmp/uv /tmp/requirements-extra.txt

# ── Custom callbacks ─────────────────────────────────────────────────────────
COPY callbacks/ /app/callbacks/
ENV PYTHONPATH=/app/callbacks

# ── Runtime hardening ────────────────────────────────────────────────────────
# Expose the proxy port
EXPOSE 4000

# Healthcheck — hits the /health/liveliness endpoint
HEALTHCHECK --interval=30s --timeout=10s --start-period=15s --retries=3 \
  CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:4000/health/liveliness')" || exit 1

# Config is bind-mounted at runtime (see docker-compose.yml)
# num_workers is overridden via docker-compose command: to support WORKERS env var
CMD ["--config", "/app/config.yaml", "--port", "4000", "--num_workers", "4"]
