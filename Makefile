-include .env
-include .env.limits
export

.PHONY: run run-bg down restart test logs limits build-config help

# ── Profile detection ─────────────────────────────────────────────────────────

comma := ,
empty :=
space := $(empty) $(empty)

_PROFILES :=

# claudebox: opt-in with CLAUDEBOX=1
ifeq ($(strip $(CLAUDEBOX)),1)
  _PROFILES += claudebox
endif

# pibox-zai: opt-in with PIBOX_ZAI=1
ifeq ($(strip $(PIBOX_ZAI)),1)
  _PROFILES += pibox-zai
endif

# cloudflared: opt-in with CLOUDFLARED=1
ifeq ($(strip $(CLOUDFLARED)),1)
  _PROFILES += cloudflared
endif

# hybrids3: opt-in with HYBRIDS3=1
ifeq ($(strip $(HYBRIDS3)),1)
  _PROFILES += hybrids3
endif

# browser: opt-in with BROWSER=1
ifeq ($(strip $(BROWSER)),1)
  _PROFILES += browser
endif

# ollama: opt-in with OLLAMA=1
ifeq ($(strip $(OLLAMA)),1)
  _PROFILES += ollama
endif

# ollama CUDA: opt-in with OLLAMA_CUDA=1
ifeq ($(strip $(OLLAMA_CUDA)),1)
  _PROFILES += ollama-cuda
endif

# sdcpp: opt-in with SDCPP=1
ifeq ($(strip $(SDCPP)),1)
  _PROFILES += sdcpp
endif

# sdcpp CUDA: opt-in with SDCPP_CUDA=1
ifeq ($(strip $(SDCPP_CUDA)),1)
  _PROFILES += sdcpp-cuda
endif

# talkies: opt-in with TALKIES=1 (CPU — whisper + canary-180m ASR + Kokoro TTS)
ifeq ($(strip $(TALKIES)),1)
  _PROFILES += talkies
endif

# talkies CUDA: opt-in with TALKIES_CUDA=1 (GPU — whisper + parakeet +
# all canary ASR + Kokoro TTS)
ifeq ($(strip $(TALKIES_CUDA)),1)
  _PROFILES += talkies-cuda
endif

# librechat: opt-in with LIBRECHAT=1
ifeq ($(strip $(LIBRECHAT)),1)
  _PROFILES += librechat
endif

# searxng: opt-in with SEARXNG=1
ifeq ($(strip $(SEARXNG)),1)
  _PROFILES += searxng
endif

# telethon: opt-in with TELETHON=1
ifeq ($(strip $(TELETHON)),1)
  _PROFILES += telethon
endif

# tailscale: opt-in with TAILSCALE=1
ifeq ($(strip $(TAILSCALE)),1)
  _PROFILES += tailscale
  # Load the tailnet-egress overlay so claudebox/pibox can reach the tailnet.
  export COMPOSE_FILE := docker-compose.yml:docker-compose.tailscale.yml
endif

# predictalot: opt-in with PREDICTALOT=1 (CPU)
ifeq ($(strip $(PREDICTALOT)),1)
  _PROFILES += predictalot
endif

# predictalot CUDA: opt-in with PREDICTALOT_CUDA=1
ifeq ($(strip $(PREDICTALOT_CUDA)),1)
  _PROFILES += predictalot-cuda
endif

# audiolla: opt-in with AUDIOLLA=1
ifeq ($(strip $(AUDIOLLA)),1)
  _PROFILES += audiolla
endif

# audiolla CUDA: opt-in with AUDIOLLA_CUDA=1
ifeq ($(strip $(AUDIOLLA_CUDA)),1)
  _PROFILES += audiolla-cuda
endif

# flickies: opt-in with FLICKIES=1
ifeq ($(strip $(FLICKIES)),1)
  _PROFILES += flickies
endif

# flickies CUDA: opt-in with FLICKIES_CUDA=1
ifeq ($(strip $(FLICKIES_CUDA)),1)
  _PROFILES += flickies-cuda
endif

# vllm (CPU): opt-in with VLLM=1
ifeq ($(strip $(VLLM)),1)
  _PROFILES += vllm
endif

# vllm CUDA: opt-in with VLLM_CUDA=1
ifeq ($(strip $(VLLM_CUDA)),1)
  _PROFILES += vllm-cuda
endif

# llama.cpp (CPU): opt-in with LLAMACPP=1
ifeq ($(strip $(LLAMACPP)),1)
  _PROFILES += llamacpp
endif

# llama.cpp CUDA: opt-in with LLAMACPP_CUDA=1
ifeq ($(strip $(LLAMACPP_CUDA)),1)
  _PROFILES += llamacpp-cuda
endif

# piston: opt-in with PISTON=1 (sandboxed multi-language code execution)
ifeq ($(strip $(PISTON)),1)
  _PROFILES += piston
endif

# mailbox: opt-in with MAILBOX=1
ifeq ($(strip $(MAILBOX)),1)
  _PROFILES += mailbox
endif


# mcp: auto-enabled when any image, TTS, or search provider is active
_HAS_MCP :=
ifeq ($(strip $(HUGGINGFACE)),1)
  _HAS_MCP := 1
endif
ifeq ($(strip $(OPENAI)),1)
  _HAS_MCP := 1
endif
ifeq ($(strip $(TALKIES)),1)
  _HAS_MCP := 1
endif
ifeq ($(strip $(TALKIES_CUDA)),1)
  _HAS_MCP := 1
endif
ifeq ($(strip $(SDCPP)),1)
  _HAS_MCP := 1
endif
ifeq ($(strip $(SDCPP_CUDA)),1)
  _HAS_MCP := 1
endif
ifeq ($(strip $(SEARXNG)),1)
  _HAS_MCP := 1
endif
ifeq ($(_HAS_MCP),1)
  _PROFILES += mcp
endif

override COMPOSE_PROFILES := $(subst $(space),$(comma),$(strip $(_PROFILES)))
export COMPOSE_PROFILES

# ── File path env vars that get volume-mounted ───────────────────────────────
# Add any env var here whose value is a host file path used in a volume mount.
_FILE_VARS := CLOUDFLARED_CONFIG CLOUDFLARED_CREDS MAILBOX_CONFIG

define check_file_vars
	@for var in $(_FILE_VARS); do \
		val=$$(eval echo "\$$$$var"); \
		if [ -z "$$val" ] || [ "$$val" = "/dev/null" ]; then continue; fi; \
		case "$$val" in /*) ;; *) val="$(CURDIR)/$$val" ;; esac; \
		if [ ! -f "$$val" ]; then \
			echo "ERROR: $$var — file does not exist: $$val" >&2; \
			exit 1; \
		fi; \
	done
endef

# ── Targets ───────────────────────────────────────────────────────────────────

build-config:
	@docker run --rm \
		-v "$(CURDIR):/workspace" \
		-w /workspace \
		python:3.12-alpine \
		python3 litellm/build-config.py

run:
	$(check_file_vars)
	$(MAKE) build-config
	@echo "Active profiles: $(if $(COMPOSE_PROFILES),$(COMPOSE_PROFILES),(none))"
	docker compose up --build --force-recreate

run-bg:
	$(check_file_vars)
	$(MAKE) build-config
	@echo "Active profiles: $(if $(COMPOSE_PROFILES),$(COMPOSE_PROFILES),(none))"
	docker compose up -d --build --force-recreate

down:
	COMPOSE_PROFILES=claudebox,pibox-zai,cloudflared,hybrids3,browser,ollama,ollama-cuda,sdcpp,sdcpp-cuda,talkies,talkies-cuda,vllm,vllm-cuda,mcp,librechat,searxng,telethon,tailscale,predictalot,predictalot-cuda,audiolla,audiolla-cuda,flickies,flickies-cuda,mailbox \
		docker compose down --remove-orphans

restart: down run-bg

test:
	bash test.sh

logs:
	docker compose logs -f

limits:
	@bash recommend-limits.sh

help:
	@echo ""
	@echo "Usage: make <target>"
	@echo ""
	@echo "Targets:"
	@echo "  run           Start the stack in foreground (auto-detects profiles from .env)"
	@echo "  run-bg        Start the stack in background"
	@echo "  down          Stop everything"
	@echo "  restart       Full restart (down + build-config + run-bg)"
	@echo "  build-config  Regenerate litellm/config.yaml from fragments"
	@echo "  limits        Generate .env.limits with recommended resource limits"
	@echo "  test          Run test suite (stack must be running)"
	@echo "  logs          Follow logs"
	@echo "  help          Show this help"
	@echo ""
	@echo "Profiles (set flag to 1 in .env to enable):"
	@echo "  claudebox     set CLAUDEBOX=1"
	@echo "  pibox-zai     set PIBOX_ZAI=1 (pi-coding-agent via z.ai/GLM)"
	@echo "  cloudflared   set CLOUDFLARED=1"
	@echo "  hybrids3      set HYBRIDS3=1"
	@echo "  browser       set BROWSER=1"
	@echo "  ollama        set OLLAMA=1 (CPU inference)"
	@echo "  ollama-cuda   set OLLAMA_CUDA=1 (NVIDIA GPU inference)"
	@echo "  sdcpp         set SDCPP=1 (CPU image generation)"
	@echo "  sdcpp-cuda    set SDCPP_CUDA=1 (NVIDIA GPU image generation)"
	@echo "  talkies       set TALKIES=1 (CPU unified ASR + Kokoro TTS, VAD-chunked)"
	@echo "  talkies-cuda  set TALKIES_CUDA=1 (GPU ASR + Kokoro + Qwen3-TTS voice cloning)"
	@echo "  librechat     set LIBRECHAT=1"
	@echo "  searxng       set SEARXNG=1 (meta search engine + MCP tool)"
	@echo "  telethon      set TELETHON=1 (Telegram client REST API + MCP)"
	@echo "  tailscale     set TAILSCALE=1 (tailnet-only HTTP proxy to nginx; claudebox/pibox get outbound tailnet reach)"
	@echo "  predictalot   set PREDICTALOT=1 (CPU time-series forecasting + MCP)"
	@echo "  predictalot-cuda set PREDICTALOT_CUDA=1 (NVIDIA GPU time-series forecasting + MCP)"
	@echo "  mailbox       set MAILBOX=1 (IMAP+SMTP gateway REST API + MCP — needs MAILBOX_CONFIG)"

	@echo "  mcp           (auto: any image/TTS/search provider enabled)"
	@echo ""
	@echo "Active profiles: $(if $(COMPOSE_PROFILES),$(COMPOSE_PROFILES),(none))"
	@echo ""
