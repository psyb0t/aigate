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

# claudebox-zai: opt-in with CLAUDEBOX_ZAI=1
ifeq ($(strip $(CLAUDEBOX_ZAI)),1)
  _PROFILES += claudebox-zai
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

# speaches: opt-in with SPEACHES=1
ifeq ($(strip $(SPEACHES)),1)
  _PROFILES += speaches
endif

# speaches CUDA: opt-in with SPEACHES_CUDA=1
ifeq ($(strip $(SPEACHES_CUDA)),1)
  _PROFILES += speaches-cuda
endif

# qwen3 CUDA TTS: opt-in with QWEN_TTS_CUDA=1
ifeq ($(strip $(QWEN_TTS_CUDA)),1)
  _PROFILES += qwen3-cuda-tts
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


# mcp: auto-enabled when any image, TTS, or search provider is active
_HAS_MCP :=
ifeq ($(strip $(HUGGINGFACE)),1)
  _HAS_MCP := 1
endif
ifeq ($(strip $(OPENAI)),1)
  _HAS_MCP := 1
endif
ifeq ($(strip $(SPEACHES)),1)
  _HAS_MCP := 1
endif
ifeq ($(strip $(SPEACHES_CUDA)),1)
  _HAS_MCP := 1
endif
ifeq ($(strip $(QWEN_TTS_CUDA)),1)
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
_FILE_VARS := CLOUDFLARED_CONFIG CLOUDFLARED_CREDS

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
	COMPOSE_PROFILES=claudebox,claudebox-zai,cloudflared,hybrids3,browser,ollama,ollama-cuda,sdcpp,sdcpp-cuda,speaches,speaches-cuda,qwen3-cuda-tts,mcp,librechat,searxng,telethon \
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
	@echo "  claudebox-zai set CLAUDEBOX_ZAI=1"
	@echo "  cloudflared   set CLOUDFLARED=1"
	@echo "  hybrids3      set HYBRIDS3=1"
	@echo "  browser       set BROWSER=1"
	@echo "  ollama        set OLLAMA=1 (CPU inference)"
	@echo "  ollama-cuda   set OLLAMA_CUDA=1 (NVIDIA GPU inference)"
	@echo "  sdcpp         set SDCPP=1 (CPU image generation)"
	@echo "  sdcpp-cuda    set SDCPP_CUDA=1 (NVIDIA GPU image generation)"
	@echo "  speaches      set SPEACHES=1 (CPU TTS + STT)"
	@echo "  speaches-cuda set SPEACHES_CUDA=1 (NVIDIA GPU STT)"
	@echo "  qwen-tts-cuda set QWEN_TTS_CUDA=1 (NVIDIA GPU TTS)"
	@echo "  librechat     set LIBRECHAT=1"
	@echo "  searxng       set SEARXNG=1 (meta search engine + MCP tool)"

	@echo "  mcp           (auto: any image/TTS/search provider enabled)"
	@echo ""
	@echo "Active profiles: $(if $(COMPOSE_PROFILES),$(COMPOSE_PROFILES),(none))"
	@echo ""
