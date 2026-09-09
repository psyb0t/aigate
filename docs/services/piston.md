# piston — sandboxed multi-language code execution

> Profile flag: `PISTON=1`.
> Upstream: [`engineer-man/piston`](https://github.com/engineer-man/piston) (`ghcr.io/engineer-man/piston@sha256:2f66b745...`).
> Exposes `/piston/api/v2/*` behind nginx bearer auth + an MCP-friendly REST API any function-calling LLM can call.

50+ language sandboxed code execution. nsjail-based isolation per execution (own user namespace, chroot, seccomp, cgroups). Network disabled inside sandboxes by default. Hard wall-clock + memory + output-size caps per call.

## Quick start

```bash
# list installed runtimes
curl -H "Authorization: Bearer $AIGATE_TOKEN" \
  http://localhost:4000/piston/api/v2/runtimes

# execute python
curl -H "Authorization: Bearer $AIGATE_TOKEN" \
     -H "Content-Type: application/json" \
     -X POST http://localhost:4000/piston/api/v2/execute \
     -d '{
       "language": "python",
       "version": "3.12.0",
       "files": [{"content": "print(sum(range(1,11)))"}]
     }'
# → {"run":{"stdout":"55\n","code":0,"cpu_time":15,"wall_time":27, ...}, ...}
```

## Default language set + how to extend

Languages are **pre-baked into the image at build time** (not installed at runtime). The shipped default is the minimal useful set:

| Language | Version | Status |
|---|---|---|
| `python` | 3.12.0 | Released Oct 2023. One major behind current (3.13.x). Reasonable for production. |
| `node` | 20.11.1 | Released Feb 2024. Node 20 is supported LTS through Apr 2026. |

That's it. Two languages cover most "LLM writes a snippet, runs it" use cases — hashing, regex, JSON wrangling, math, parsing, basic algorithms.

### How to add a language

1. Edit `PISTON_LANGUAGES` in `.env` — comma-separated `language=version` specs.
2. Rebuild: `docker compose --profile piston build piston`
3. Swap in the new image: `make run-bg` (or `docker compose --profile piston up -d --no-deps piston`).

```bash
# .env
PISTON=1
PISTON_LANGUAGES=python=3.12.0,node=20.11.1,bash=5.2.0
```

### What's available + a heads-up on staleness

Piston's `pkgs` index lives at [github.com/engineer-man/piston/releases/tag/pkgs](https://github.com/engineer-man/piston/releases/tag/pkgs). 77 languages, 115+ language/version pairs. **But that index has not been kept current.** Most languages there pin to 2021-2023 versions:

| If you reach for | Piston has | Current stable | Verdict |
|---|---|---|---|
| go | 1.16.2 (Mar 2021) | 1.23.x | **Ancient** — missing generics, structured logging, range-over-func |
| rust | 1.68.2 (Mar 2023) | 1.83.x | ~2 years behind — usable, but missing several stabilized features |
| java | 15.0.2 (Jan 2021) | 23 (LTS 21) | **Ancient** — no records, no pattern matching, no virtual threads |
| ruby | 3.0.1 (Jan 2021) | 3.3.x | **Ancient** — pre-YJIT |
| swift | 5.3.3 (Jan 2021) | 6.0.x | **Ancient** |
| typescript | 5.0.3 (Mar 2023) | 5.7.x | ~2 years behind |
| deno | 1.32.3 (Mar 2023) | 2.x | **Major version skipped** |
| kotlin | 1.8.20 (Apr 2023) | 2.0.x | One major behind |
| python | 3.12.0 (Oct 2023) | 3.13.x | One major behind. Fine. |
| node | 20.11.1 (Feb 2024) | 22.x | LTS 20.x still supported. Fine. |

The point: **python + node are the languages piston actually keeps current-ish.** Everything else carries a real "missing N years of language evolution" cost. If you need a recent Rust or current Go for actual production work, swap to a different code-execution backend (judge0, e2b, or roll your own) — don't extend piston for those.

### Why pre-bake instead of runtime install

The runtime container lives on `aigate-internal` ONLY — no outbound network. This shrinks the attack surface: if a neighbour container in `aigate-public` (e.g. searxng, browser cluster, talkies, audiolla) is compromised, the attacker can't reach `http://piston:2000` directly to spawn arbitrary code execution. They'd have to first break into a service ON `aigate-internal` (nginx, mcp, litellm), which is a much harder target.

The cost: adding a language requires a `docker compose build`. For a service that processes untrusted-LLM-written code, that's a fair price.

The build-time install works because the docker build context has internet access — piston spawns its own API in the Dockerfile RUN step, POSTs the install calls to itself, downloads tarballs from GitHub releases, and persists the result to `/piston/packages/`. At runtime the upstream entrypoint scans that dir and registers every language.

## Isolation model

Per-execution isolation lives inside nsjail (Google's process-isolation tool):

```
host
└── piston container (privileged: true) ← needs caps to set up nsjail
    └── nsjail subprocess per execution ← THIS is where the sandbox is
        ├── new user namespace (code runs as uid 65534)
        ├── chroot to minimal language runtime only
        ├── new pid + mount + uts + ipc + net namespaces
        ├── seccomp filters blocking dangerous syscalls
        ├── cgroups: cpu, memory, pids, wall-clock all hard-capped
        └── no /proc, no /sys, no host paths visible
```

`privileged: true` on the container is **what piston needs to set up nsjail** — not what isolates the code itself. The actual sandboxing happens in the nsjail subprocess. nsjail is stronger than Docker's default isolation (the same primitive Google uses to sandbox user submissions in their programming competitions).

| Threat | Mitigated by |
|---|---|
| Code escapes to other executions | nsjail process + pid + mount namespace isolation |
| Code reads host filesystem | chroot + no host bind-mounts |
| Code does outbound network calls | `PISTON_DISABLE_NETWORKING=true` (default) — nsjail creates a network namespace with no veth pair |
| Code burns CPU / RAM indefinitely | cgroup CPU + memory limits + `PISTON_RUN_TIMEOUT` wall clock |
| Code calls dangerous syscalls (`ptrace`, `keyctl`, `bpf`, etc.) | nsjail seccomp filter |
| **Code escapes nsjail itself** | This is the real residual risk. A kernel CVE in namespace / seccomp would let code land in the privileged container = effectively root on host. |
| Unauthenticated API access | nginx bearer auth at `/piston/` (the upstream API has no auth) |

If you want stronger isolation than this — run piston in a dedicated VM (not just a Docker container), or use Firecracker-microVM-based execution (e2b). For aigate's threat model (trusted operator + bearer-auth-gated public endpoint + sandboxed code from LLM agents) the nsjail-inside-privileged setup is acceptable.

## Configuration

### Profile flag

`PISTON=1` in `.env` activates the service. Detected by `make`'s profile autodetect.

### Language set

| Variable | Default | Description |
|---|---|---|
| `PISTON_LANGUAGES` | `python=3.12.0,node=20.11.1,bash=5.2.0,deno=1.32.3,go=1.16.2,rust=1.68.2,typescript=5.0.3` | Comma-separated `language=version` specs. Re-running `make run-bg` after adding new entries installs only the new ones. |

### Sandbox limits (per execution)

| Variable | Default | Description |
|---|---|---|
| `PISTON_RUN_TIMEOUT` | `30000` (ms) | Hard wall-clock cap per execution. |
| `PISTON_COMPILE_TIMEOUT` | `30000` (ms) | Hard cap on compile-step (for compiled languages). |
| `PISTON_OUTPUT_MAX_SIZE` | `1024` (KB) | Cap on stdout + stderr bytes captured. |
| `PISTON_MAX_PROCESS_COUNT` | `64` | Max processes nsjail allows the sandbox to spawn. |
| `PISTON_MAX_OPEN_FILES` | `2048` | Max open file descriptors. |
| `PISTON_MAX_FILE_SIZE` | `10000000` (bytes) | Max single-file write. |
| `PISTON_DISABLE_NETWORKING` | `true` | When `true`, sandboxes have no network. Flip to `false` if you specifically want LLM-written code to be able to make HTTP calls — but be aware of the threat model implications. |

### Service-level limits

| Variable | Default | Description |
|---|---|---|
| `PISTON_MEM_LIMIT` | `4g` | Container memory cap. |
| `PISTON_MEMSWAP_LIMIT` | `8g` | Container swap cap. |
| `PISTON_CPUS` | `2.0` | Container CPU limit. |
| `DATA_DIR_PISTON` | `${DATA_DIR}/piston` | Bind-mount root for the wrapper's `/piston` dir. Holds installed language packages (so subsequent `up` calls don't re-download every language). |

### Nginx route

| Variable | Default | Description |
|---|---|---|
| `RATELIMIT_PISTON` | `30r/m` | Per-IP request-rate to the `/piston/` route. |
| `RATELIMIT_PISTON_BURST` | `10` | Per-IP burst allowance. |
| `TIMEOUT_PISTON` | `2m` | nginx proxy read / send timeout. |

## API endpoints (proxied at `/piston/api/v2/*`)

| Endpoint | Method | Description |
|---|---|---|
| `/api/v2/runtimes` | GET | List installed languages + versions + aliases. |
| `/api/v2/execute` | POST | Execute code. Body: `{language, version, files: [{content}], stdin?, args?, run_timeout?, compile_timeout?, run_memory_limit?}`. Returns `{run: {stdout, stderr, code, signal, cpu_time, wall_time, memory}, compile?: {...}}`. |
| `/api/v2/packages` | GET | List packages available for install (queries the upstream piston releases). |
| `/api/v2/packages` | POST | Install a language package: `{language, version}`. Used by `piston-pull` sidecar. |
| `/api/v2/packages` | DELETE | Uninstall a language package: `{language, version}`. |

All endpoints require `Authorization: Bearer $AIGATE_TOKEN`. Unauthenticated requests return HTTP 401.

## MCP tool

A function-calling LLM can invoke code execution through the `execute_code` MCP tool exposed by the aggregator at `/mcp/`. The tool wraps `POST /piston/api/v2/execute` with the same auth. Tool signature:

```
execute_code(language: str, source: str, stdin?: str, args?: list[str]) → {
    stdout: str,
    stderr: str,
    exit_code: int,
    cpu_time_ms: int,
    wall_time_ms: int,
    memory_bytes: int,
}
```

See [`docs/services/mcp.md`](mcp.md) for the full tool catalog.

## Bump piston upstream

Upstream publishes only `:latest` (no semver tags). To bump:

```bash
docker pull ghcr.io/engineer-man/piston:latest
docker image inspect ghcr.io/engineer-man/piston:latest --format '{{.RepoDigests}}'
# → ghcr.io/engineer-man/piston@sha256:<NEW_DIGEST>
```

To pin the new digest locally, put it in `docker-compose.override.yml` rather than editing `docker-compose.yml`, which an update overwrites:

```yaml
services:
  piston:
    image: ghcr.io/engineer-man/piston@sha256:<NEW_DIGEST>
```

Test against the existing language set before bumping. To change the digest the project ships for everyone, edit `docker-compose.yml` and send that change upstream.
