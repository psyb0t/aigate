#!/usr/bin/env python3
"""
Build litellm/config.yaml dynamically from fragment files based on .env settings.

Uses only Python stdlib — no external dependencies required.

Usage: python3 litellm/build-config.py
       (run from the workspace root, or via Docker — see Makefile)
"""

import json
import os
import sys

# ── Paths ─────────────────────────────────────────────────────────────────────

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
WORKSPACE_ROOT = os.path.dirname(SCRIPT_DIR)
CONFIG_DIR = os.path.join(SCRIPT_DIR, "config")
PROVIDERS_DIR = os.path.join(CONFIG_DIR, "providers")
MCP_DIR = os.path.join(CONFIG_DIR, "mcp")
OUTPUT_PATH = os.path.join(SCRIPT_DIR, "config.yaml")
ENV_PATH = os.path.join(WORKSPACE_ROOT, ".env")
BASE_PATH = os.path.join(CONFIG_DIR, "base.yaml")
FALLBACKS_PATH = os.path.join(CONFIG_DIR, "fallbacks.json")

PREFIX = "[build-config]"


def log(msg):
    print(f"{PREFIX} {msg}")


def warn(msg):
    print(f"{PREFIX} WARNING: {msg}", file=sys.stderr)


def die(msg):
    print(f"{PREFIX} ERROR: {msg}", file=sys.stderr)
    sys.exit(1)


# ── .env loading ──────────────────────────────────────────────────────────────

def load_env(path):
    env = {}
    if not os.path.exists(path):
        warn(f".env not found at {path} — using empty env")
        return env
    with open(path, "r", encoding="utf-8") as fh:
        for raw_line in fh:
            line = raw_line.strip()
            if not line or line.startswith("#"):
                continue
            if "=" not in line:
                continue
            key, _, rest = line.partition("=")
            key = key.strip()
            value = rest.strip()
            if len(value) >= 2 and value[0] == value[-1] and value[0] in ('"', "'"):
                value = value[1:-1]
            else:
                comment_pos = value.find("#")
                if comment_pos > 0:
                    value = value[:comment_pos].rstrip()
            env[key] = value
    return env


# ── Activation logic ──────────────────────────────────────────────────────────

def is_set(env, key):
    return bool(env.get(key, "").strip())


def is_flag(env, key):
    return env.get(key, "").strip() == "1"


def active_providers(env):
    checks = [
        ("openai",        lambda e: is_flag(e, "OPENAI")),
        ("anthropic",     lambda e: is_flag(e, "ANTHROPIC")),
        ("claudebox",     lambda e: is_flag(e, "CLAUDEBOX")),
        ("claudebox-zai", lambda e: is_flag(e, "CLAUDEBOX_ZAI")),
        ("cerebras",      lambda e: is_flag(e, "CEREBRAS")),
        ("openrouter",    lambda e: is_flag(e, "OPENROUTER")),
        ("huggingface",   lambda e: is_flag(e, "HUGGINGFACE")),
        ("mistral",       lambda e: is_flag(e, "MISTRAL")),
        ("cohere",        lambda e: is_flag(e, "COHERE")),
        ("groq",          lambda e: is_flag(e, "GROQ")),
        ("ollama",        lambda e: is_flag(e, "OLLAMA")),
        ("ollama-cuda",     lambda e: is_flag(e, "CUDA")),
        ("qwen3-cuda-tts", lambda e: is_flag(e, "CUDA")),
        ("speaches",       lambda e: is_flag(e, "SPEACHES")),
        ("speaches-cuda",  lambda e: is_flag(e, "CUDA")),
        ("sdcpp",          lambda e: is_flag(e, "SDCPP")),
        ("sdcpp-cuda",     lambda e: is_flag(e, "SDCPP") and is_flag(e, "CUDA")),
    ]
    return [name for name, check in checks if check(env)]


def active_mcp_servers(env):
    checks = [
        ("hybrids3",      lambda e: is_flag(e, "HYBRIDS3")),
        ("browser",       lambda e: is_flag(e, "BROWSER")),
        ("claudebox",     lambda e: is_flag(e, "CLAUDEBOX")),
        ("claudebox-zai", lambda e: is_flag(e, "CLAUDEBOX_ZAI")),
        ("mcp",           lambda e: any(
            is_flag(e, f) for f in ("HUGGINGFACE", "OPENAI", "SPEACHES", "CUDA", "SDCPP")
        )),
    ]
    return [name for name, check in checks if check(env)]


# ── Fragment readers ──────────────────────────────────────────────────────────

def read_file(path):
    if not os.path.exists(path):
        die(f"Fragment missing: {path}")
    with open(path, "r", encoding="utf-8") as fh:
        return fh.read()


def indent_block(text, spaces=2):
    """Indent every non-empty line of a text block."""
    pad = " " * spaces
    lines = []
    for line in text.splitlines():
        lines.append(pad + line if line.strip() else line)
    return "\n".join(lines)


# ── Fallback filtering ────────────────────────────────────────────────────────

def load_fallbacks():
    if not os.path.exists(FALLBACKS_PATH):
        die(f"fallbacks.json missing: {FALLBACKS_PATH}")
    with open(FALLBACKS_PATH, "r", encoding="utf-8") as fh:
        return json.load(fh)


def filter_fallbacks(fallbacks_raw, active_models):
    result = []
    for entry in fallbacks_raw:
        primary = next(iter(entry))
        fb_list = entry[primary]
        if primary not in active_models:
            continue
        filtered = [m for m in fb_list if m in active_models]
        if not filtered:
            continue
        result.append({primary: filtered})
    return result


def serialize_fallbacks_yaml(fallbacks):
    """
    Serialize filtered fallbacks to YAML text at 2-space indent,
    suitable for appending directly after the router_settings block in base.yaml.
    """
    if not fallbacks:
        return ""
    lines = ["  fallbacks:"]
    for entry in fallbacks:
        primary = next(iter(entry))
        lines.append(f"  - {primary}:")
        for fb in entry[primary]:
            lines.append(f"    - {fb}")
    return "\n".join(lines) + "\n"


# ── Model name extraction ─────────────────────────────────────────────────────

def extract_model_names(provider_text):
    """Extract model_name values from a provider YAML fragment (text only, no parser)."""
    names = set()
    for line in provider_text.splitlines():
        stripped = line.strip()
        # Matches both "model_name: foo" and "- model_name: foo"
        if "model_name:" not in stripped:
            continue
        _, _, rest = stripped.partition("model_name:")
        name = rest.strip()
        if name:
            names.add(name)
    return names


# ── Main ──────────────────────────────────────────────────────────────────────

def main():
    env = load_env(ENV_PATH)

    providers = active_providers(env)
    mcp_names = active_mcp_servers(env)

    log(f"Active providers: {', '.join(providers) if providers else '(none)'}")
    log(f"Active MCP servers: {', '.join(mcp_names) if mcp_names else '(none)'}")

    # ── model_list ────────────────────────────────────────────────────────────
    model_list_parts = []
    active_model_names = set()
    model_count = 0

    for provider in providers:
        path = os.path.join(PROVIDERS_DIR, f"{provider}.yaml")
        text = read_file(path)
        model_list_parts.append(text.rstrip("\n"))
        names = extract_model_names(text)
        active_model_names.update(names)
        model_count += len(names)

    model_list_block = "model_list:\n"
    if model_list_parts:
        model_list_block += "\n".join(model_list_parts) + "\n"

    # ── mcp_servers ───────────────────────────────────────────────────────────
    mcp_block = ""
    if mcp_names:
        mcp_parts = []
        for server_name in mcp_names:
            path = os.path.join(MCP_DIR, f"{server_name}.yaml")
            text = read_file(path)
            mcp_parts.append(indent_block(text.rstrip("\n")))
        mcp_block = "\nmcp_servers:\n" + "\n".join(mcp_parts) + "\n"

    # ── base settings (general_settings, litellm_settings, router_settings) ──
    base_block = "\n" + read_file(BASE_PATH).rstrip("\n") + "\n"

    # ── fallbacks ─────────────────────────────────────────────────────────────
    fallbacks_raw = load_fallbacks()
    filtered_fallbacks = filter_fallbacks(fallbacks_raw, active_model_names)
    fallbacks_block = serialize_fallbacks_yaml(filtered_fallbacks)

    # ── write output ──────────────────────────────────────────────────────────
    output = model_list_block + mcp_block + base_block
    if fallbacks_block:
        output = output.rstrip("\n") + "\n" + fallbacks_block

    with open(OUTPUT_PATH, "w", encoding="utf-8") as fh:
        fh.write(output)

    log(f"Wrote {os.path.relpath(OUTPUT_PATH, WORKSPACE_ROOT)} ({model_count} models)")


if __name__ == "__main__":
    main()
