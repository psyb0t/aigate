# Build stage: pull official litellm image
# v1.83.14-stable.patch.2 — patched for CVE-2026-42208 (pre-auth SQLi, fixed in v1.83.7+)
# and post-supply-chain-incident (clean v1.83.x line, new CI/CD v2 pipeline). Cosign-signed.
FROM ghcr.io/berriai/litellm:v1.83.14-stable.patch.2@sha256:73cbb215d3d43ae5b42816217b200386eb08d567767fcb36cba163152c5f3c79 AS base

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
