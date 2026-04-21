# Build stage: pull official litellm image (post-1.83.0 CVE patches)
# Using nightly until v1.83.x-stable is tagged; pin digest for reproducibility
FROM ghcr.io/berriai/litellm:v1.83.5-nightly AS base

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
