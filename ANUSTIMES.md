# ANUSTIMES — README & Docs Quality Review

## Phase 1 — Issue Catalog (23 issues found)

Source of truth: docker-compose.yml, Makefile, build-config.py, provider YAMLs (15 files, 94 models), test_mcp.sh, recommend-limits.sh.

### README.md — ALL FIXED

| # | Issue | Status |
|---|-------|--------|
| 1 | "82 models across 12 providers" → 94 models, 13 providers | FIXED |
| 2 | "Two more run locally" → 3 local providers (Ollama, Speaches, Qwen3 CUDA TTS) | FIXED |
| 3 | "34 tools" → 18 MCP tools (SAB v1.0.0: 1 tool) | FIXED |
| 4 | Architecture diagram: duplicate Groq-Cohere block | FIXED |
| 5 | Architecture diagram: missing optional labels, added flags to every entry | FIXED |
| 6 | MCP section: "34 tools across 4 servers" → "up to 18 tools across 4 optional servers" | FIXED |
| 7 | claudebox/hybrids3/browser: missing optional labels | FIXED |
| 8 | Ollama: missing optional label | FIXED |
| 9 | Speaches: missing optional label | FIXED |
| 10 | Security paragraph: optional services listed as always-on | FIXED |
| 11 | Providers intro: wrong counts | FIXED |
| 12 | Routing table: "Local CPU" → "Local (CPU/CUDA)" with Qwen3 CUDA TTS | FIXED |
| 13 | Test count: 94 → 91 | FIXED |
| 14 | Added "Everything is opt-in" paragraph to intro | FIXED |

### docs/ — ALL FIXED

| # | File | Issue | Status |
|---|------|-------|--------|
| 15 | mcp-tools.md | SAB: 17 individual tools → 1 run_script tool with actions table | FIXED |
| 16 | mcp-tools.md | Missing optional flag labels on all MCP server sections | FIXED |
| 17 | providers.md | "Add API keys to activate" → flag activates, not key | FIXED |
| 18 | services-reference.md | Admin rate limit: "5 req/min" → 30r/m | FIXED |
| 19 | services-reference.md | cloudflared: COMPOSE_PROFILES → CLOUDFLARED=1 | FIXED |
| 20 | testing.md | "all 57 models" → dynamic count based on flags | FIXED |
| 21 | testing.md | "34 tools" → 18 tools | FIXED |

## Phase 3 — Brutal Review Findings

| # | File | Severity | Issue | Status |
|---|------|----------|-------|--------|
| B1 | testing.md | WRONG | "/ui path blocked (404)" → "root path blocked (404)" | FIXED |
| B2 | services-reference.md | WRONG | "Leave empty to disable auth" → defaults to lulz-4-security | FIXED |
| B3 | usage.md | BROKEN | All browser REST examples missing Authorization header | FIXED |
| B4 | usage.md | INCOMPLETE | Vision model list missing 7+ multimodal models | FIXED |
| B5 | .env.example | STALE | RATELIMIT_API=120r/m → 500r/m | FIXED |
| B6 | services-reference.md | MINOR | run_script listed flat alongside atomic actions → separated | FIXED |

## Phase 3 — Counter-Review

- Issue 5 (16 vs 17 actions): DISMISSED. 16 actions in mcp-tools.md is correct. run_script is the MCP tool, not a step.
- Issue 6 (qwen3 alias naming): DISMISSED. Not a docs bug — matches the actual config.
- Issue 9 (API rate limit not documented in prose): DISMISSED. It's in .env.example (now correct) and docker-compose.yml.

## Phase 4 — Final Verification (2 agents, parallel)

### README.md verification (12 checks): ALL PASS
1. PASS — "94 models across 13 providers" on lines 5 and 110, no stale values
2. PASS — "18 tools" used consistently, no stale "34"
3. PASS — No duplicate providers in architecture diagram
4. PASS — Every service/provider has .env flag shown
5. PASS — "Up to 18 tools across 4 optional servers"
6. PASS — All non-core services have optional labels
7. PASS — Core services have no optional labels
8. PASS — Security paragraph correctly frames optional services
9. PASS — "Local (CPU/CUDA)" in routing table
10. PASS — "91 tests"
11. PASS — "Three more run on your own hardware"
12. PASS — "Everything is opt-in" paragraph present

### docs/ verification (6 checks): ALL PASS
1. PASS — mcp-tools.md: SAB = 1 tool, actions as steps, all flags shown
2. PASS — providers.md: flags activate providers
3. PASS — services-reference.md: 30r/m, CLOUDFLARED=1, lulz-4-security default
4. PASS — testing.md: no stale counts, "root path blocked"
5. PASS — usage.md: all browser examples have auth, vision list complete
6. PASS — .env.example: RATELIMIT_API=500r/m

## Summary

- 27 issues found and fixed across 7 files
- 0 remaining issues after verification
- Files changed: README.md, docs/mcp-tools.md, docs/providers.md, docs/services-reference.md, docs/testing.md, docs/usage.md, .env.example
