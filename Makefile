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

# cuda: opt-in with CUDA=1
ifeq ($(strip $(CUDA)),1)
  _PROFILES += cuda
endif

# sdcpp: opt-in with SDCPP=1 (always CPU; add CUDA variant when CUDA=1)
ifeq ($(strip $(SDCPP)),1)
  _PROFILES += sdcpp
  ifeq ($(strip $(CUDA)),1)
    _PROFILES += sdcpp-cuda
  endif
endif

# speaches: opt-in with SPEACHES=1
ifeq ($(strip $(SPEACHES)),1)
  _PROFILES += speaches
endif

# librechat: opt-in with LIBRECHAT=1
ifeq ($(strip $(LIBRECHAT)),1)
  _PROFILES += librechat
endif

# mcp: auto-enabled when any image or TTS provider is active
_HAS_IMAGE_OR_TTS :=
ifeq ($(strip $(HUGGINGFACE)),1)
  _HAS_IMAGE_OR_TTS := 1
endif
ifeq ($(strip $(OPENAI)),1)
  _HAS_IMAGE_OR_TTS := 1
endif
ifeq ($(strip $(SPEACHES)),1)
  _HAS_IMAGE_OR_TTS := 1
endif
ifeq ($(strip $(CUDA)),1)
  _HAS_IMAGE_OR_TTS := 1
endif
ifeq ($(strip $(SDCPP)),1)
  _HAS_IMAGE_OR_TTS := 1
endif
ifeq ($(_HAS_IMAGE_OR_TTS),1)
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
	docker compose up --build

run-bg:
	$(check_file_vars)
	$(MAKE) build-config
	@echo "Active profiles: $(if $(COMPOSE_PROFILES),$(COMPOSE_PROFILES),(none))"
	docker compose up -d --build

down:
	COMPOSE_PROFILES=claudebox,claudebox-zai,cloudflared,hybrids3,browser,ollama,cuda,sdcpp,sdcpp-cuda,speaches,mcp,librechat \
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
	@echo "  run           Start the stack (profiles auto-detected from .env)"
	@echo "  down          Stop everything"
	@echo "  restart       Full restart"
	@echo "  build-config  Regenerate litellm/config.yaml from fragments"
	@echo "  test          Run test suite (stack must be running)"
	@echo "  logs          Follow logs"
	@echo "  help          Show this help"
	@echo ""
	@echo "Profiles (auto-enabled when credentials are set in .env):"
	@echo "  claudebox     set CLAUDEBOX=1"
	@echo "  claudebox-zai set CLAUDEBOX_ZAI=1"
	@echo "  cloudflared   set CLOUDFLARED=1"
	@echo "  hybrids3      set HYBRIDS3=1"
	@echo "  browser       set BROWSER=1"
	@echo "  ollama        set OLLAMA=1"
	@echo "  cuda          set CUDA=1 (requires NVIDIA GPU + docker nvidia runtime)"
	@echo "  sdcpp         set SDCPP=1 (CPU build, or CUDA build when CUDA=1)"
	@echo "  speaches      set SPEACHES=1"
	@echo "  librechat     set LIBRECHAT=1"
	@echo "  mcp           (auto: any image/TTS provider enabled)"
	@echo ""
	@echo "Active profiles: $(if $(COMPOSE_PROFILES),$(COMPOSE_PROFILES),(none))"
	@echo ""
