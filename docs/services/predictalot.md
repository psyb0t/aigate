# predictalot (optional, `PREDICTALOT=1` / `PREDICTALOT_CUDA=1`)

Two model families served from one container:

- **Foundation time-series** at `/v1/timeseries/<type>/…` — five zero-shot forecasters (`chronos-2`, `timesfm-2.5`, `moirai-2`, `toto-1`, `sundial-base-128m`) across six types (univariate, multivariate, covariates/past, covariates/future, covariates, samples) with per-type weighted ensembles. Type-routed REST + 27-tool MCP surface aggregated into `/mcp/` (26 forecast and listing tools plus `unload_models`).
- **Tabular ML** at `/v1/tabular/…` — nine supervised backends (`lightgbm`, `xgboost`, `hist-gbt`, `random-forest`, `logistic`, `mlp`, `svm-rbf`, `knn`, `naive-bayes`) and three meta-learners (`calibrated`, `stacking`, `diversified`) operating over caller-engineered features. **REST-only** — upstream has not (yet) registered tabular endpoints as MCP tools, so the aggregated `/mcp/` exposes the foundation-model tools and `unload_models` only; tabular work goes through the REST surface.

Direct nginx route, not via LiteLLM.

> **Breaking from upstream v0.2.x.** aigate v3.12.0 ships upstream **v1.0.1** (v1.0.1 is a docs-only patch over v1.0.0 — same image bytes; v1.0.0 is where the breaking change landed). FM endpoints moved from `/v1/<type>/…` to `/v1/timeseries/<type>/…`. No redirect compatibility layer ships — old paths now return 404. The MCP tool names are unchanged (`predictalot-forecast_<type>_<model>` / `predictalot-list_<type>_models`), so MCP callers are unaffected; only direct REST callers need to rewrite URLs.

**Model lifecycle (upstream v1.2.0).** `POST /v1/models/unload` and the `unload_models` MCP tool release every resident foundation model, Python garbage, Torch compiler state, and CUDA caches. Both return `409` while a forecast is running. aigate's resource manager calls this endpoint before any LiteLLM-routed local model runs on the same hardware, and `POST /v1/unload/{cuda,cpu}` includes predictalot in its fan-out (see [resource management](../resource-management.md)). `"unload": true` on a forecast now waits for concurrent forecasts on the same model before releasing it. Multivariate Moirai-2 forecasts past the model's 64-step limit return `400` instead of `503`.

CPU and CUDA variants run **side-by-side** on distinct routes and aliases — `/predictalot/` → CPU container, `/predictalot-cuda/` → GPU container. Enable independently via `PREDICTALOT=1` and/or `PREDICTALOT_CUDA=1`. CUDA needs `nvidia-container-toolkit`. Both share `${DATA_DIR_PREDICTALOT}/models` so the second variant to boot reuses the first's HF snapshots with zero re-fetch.

| Endpoint        | CPU (`PREDICTALOT=1`)                   | CUDA (`PREDICTALOT_CUDA=1`)                   |
| --------------- | --------------------------------------- | --------------------------------------------- |
| REST            | `http://localhost:4000/predictalot/*`   | `http://localhost:4000/predictalot-cuda/*`    |
| MCP (direct)    | `http://localhost:4000/predictalot/mcp` | `http://localhost:4000/predictalot-cuda/mcp` |
| MCP (aggregated)| `http://localhost:4000/mcp/` (`predictalot-*` prefix) | `http://localhost:4000/mcp/` (`predictalot_cuda-*` prefix) |
| Health          | `http://localhost:4000/predictalot/healthz` | `http://localhost:4000/predictalot-cuda/healthz` |
| Unload models   | `POST http://localhost:4000/predictalot/v1/models/unload` | `POST http://localhost:4000/predictalot-cuda/v1/models/unload` |

Auth: `Authorization: Bearer $PREDICTALOT_AUTH_TOKEN` (defaults to `AIGATE_TOKEN`).

Full API reference (upstream — v1.0.1 splits the deep API content out of the README into a focused docs tree):
- **Foundation time-series:** [`docs/timeseries.md`](https://github.com/psyb0t/docker-predictalot/blob/main/docs/timeseries.md) — 5 models × 6 types, request/response shapes, per-model quirks, ensemble recipes, "Recommended for" guidance per model and per type.
- **Tabular ML:** [`docs/tabular.md`](https://github.com/psyb0t/docker-predictalot/blob/main/docs/tabular.md) — 9 backends + 3 meta-learners, tier-1/2/3 config layers, storage layout, per-backend `extra` key tables.
- **MCP:** [`docs/mcp.md`](https://github.com/psyb0t/docker-predictalot/blob/main/docs/mcp.md) — the forecast, listing, and `unload_models` tools, arg shapes, namespacing.
- Configuration, architecture, accuracy benchmarks, error taxonomy: [`docs/configuration.md`](https://github.com/psyb0t/docker-predictalot/blob/main/docs/configuration.md), [`docs/architecture.md`](https://github.com/psyb0t/docker-predictalot/blob/main/docs/architecture.md), [`docs/accuracy.md`](https://github.com/psyb0t/docker-predictalot/blob/main/docs/accuracy.md), [`docs/errors.md`](https://github.com/psyb0t/docker-predictalot/blob/main/docs/errors.md).

Env vars: `PREDICTALOT_AUTH_TOKEN`, `PREDICTALOT_DEVICE` (CPU), `PREDICTALOT_CUDA_DEVICE` (CUDA), `PREDICTALOT_PREFETCH`, `PREDICTALOT_PRELOAD`, `PREDICTALOT_MODEL_IDLE_TIMEOUT`, `PREDICTALOT_MAX_BODY_SIZE`, `PREDICTALOT_LOG_LEVEL`, `DATA_DIR_PREDICTALOT`, per-route `RATELIMIT_PREDICTALOT[_BURST]` and `RATELIMIT_PREDICTALOT_CUDA[_BURST]`, shared `TIMEOUT_PREDICTALOT`. Full reference in [`.env.example`](../../.env.example).

---


## Usage

### Foundation time-series forecast (univariate, chronos-2)

```bash
curl http://localhost:4000/predictalot/v1/timeseries/univariate/forecast \
  -H "Authorization: Bearer $PREDICTALOT_AUTH_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"model":"chronos-2","context":[[10,11,12,13,14,15,16,17,18,19,20]],"config":{"horizon":5}}'
```

Returns `{model, quantileLevels, quantiles, loadedSecsAgo, lastUsedSecsAgo}` — quantile rows per requested level, one column per horizon step.

### Foundation time-series ensemble (univariate)

```bash
curl http://localhost:4000/predictalot/v1/timeseries/univariate/forecast/ensemble \
  -H "Authorization: Bearer $PREDICTALOT_AUTH_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
        "context": [[10,11,12,13,14,15,16,17,18,19,20]],
        "config": {"horizon": 5},
        "weights": {"chronos-2": 1.0, "moirai-2": 1.0, "toto-1": 0.5}
      }'
```

`weights` keys are model slugs; omitted slugs default to 1.0; `0` disables a member. `memberOverrides: {slug → partial-config}` (added in upstream v1.0.0) lets you shadow specific config keys per member in the same call.

### List FM model status per type

```bash
curl http://localhost:4000/predictalot/v1/timeseries/univariate/models \
  -H "Authorization: Bearer $PREDICTALOT_AUTH_TOKEN"
```

Swap the type — `univariate`, `multivariate`, `covariates/past`, `covariates/future`, `covariates`, `samples` — to see which members each type supports and whether they're currently in memory. (`covariates_future` is chronos-2 only; `samples` is toto-1 + sundial-base-128m; etc.)

### Tabular ML — train a direction classifier and forecast

```bash
# 1. Train a direction classifier from a labeled history (REST-only — no MCP wrapper in v1.0.0).
curl -X POST http://localhost:4000/predictalot/v1/tabular/train \
  -H "Authorization: Bearer $PREDICTALOT_AUTH_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
        "modelId": "btc-1h-direction",
        "backend": "lightgbm",
        "mode": "direction",
        "features": [["rsi","macd","obv","vol_z"], "..."],
        "labels": [1,0,1,1,0,"..."]
      }'

# 2. Predict direction on the latest feature snapshot.
curl -X POST http://localhost:4000/predictalot/v1/tabular/forecast \
  -H "Authorization: Bearer $PREDICTALOT_AUTH_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"modelId": "btc-1h-direction", "features": [[64.2, 0.18, 1.2e7, 1.4]]}'

# 3. List trained models.
curl http://localhost:4000/predictalot/v1/tabular/models \
  -H "Authorization: Bearer $PREDICTALOT_AUTH_TOKEN"

# 4. List available backends + supported modes.
curl http://localhost:4000/predictalot/v1/tabular/backends \
  -H "Authorization: Bearer $PREDICTALOT_AUTH_TOKEN"
```

The `value` and `quantile` modes work the same way — same train + forecast shape, just numeric labels instead of `0`/`1`. Meta-learners (`/v1/tabular/train/{calibrated,stacking,diversified}` with matching `/forecast/{…}` endpoints) take the same wire shape plus their own knobs (calibration `method`, stacking `K`, diversified `maxPairwiseCorr` etc. — see the upstream README).

Full API — exact request/response shapes per type / model / ensemble / tabular backend / meta-learner, accuracy benchmarks, error taxonomy: upstream [`docs/timeseries.md`](https://github.com/psyb0t/docker-predictalot/blob/main/docs/timeseries.md), [`docs/tabular.md`](https://github.com/psyb0t/docker-predictalot/blob/main/docs/tabular.md), [`docs/accuracy.md`](https://github.com/psyb0t/docker-predictalot/blob/main/docs/accuracy.md), [`docs/errors.md`](https://github.com/psyb0t/docker-predictalot/blob/main/docs/errors.md).

---

