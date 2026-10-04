# Seed .env from the tracked example. This runs while make parses the file,
# before the -include below, so a freshly created .env is read by this same
# invocation.
$(shell [ -f .env ] || cp .env.example .env)

-include .env
-include .env.limits
export

.PHONY: run run-bg down restart restart-audiolla test test-unit test-config build-decidealot test-decidealot-coordination test-llamacpp-pull test-llamacpp-server logs limits build-config bootstrap help

# ── Profile detection ─────────────────────────────────────────────────────────

comma := ,
empty :=
space := $(empty) $(empty)

_PROFILES :=

# Compose files, in merge order. The base is always first. Overlays gated by a
# flag append themselves below, and docker-compose.override.yml goes last so a
# local change wins over everything the repository ships.
_COMPOSE_FILES := docker-compose.yml

# claudebox: opt-in with CLAUDEBOX=1
ifeq ($(strip $(CLAUDEBOX)),1)
  _PROFILES += claudebox
endif

# pibox-zai: opt-in with PIBOX_ZAI=1
ifeq ($(strip $(PIBOX_ZAI)),1)
  _PROFILES += pibox-zai
endif

# pibox: opt-in with PIBOX=1 (pi driven by this stack's own models)
ifeq ($(strip $(PIBOX)),1)
  _PROFILES += pibox
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
  # Pull in the tailnet-egress overlay so claudebox/pibox can reach the tailnet.
  _COMPOSE_FILES += docker-compose.tailscale.yml
endif

# predictalot: opt-in with PREDICTALOT=1 (CPU)
ifeq ($(strip $(PREDICTALOT)),1)
  _PROFILES += predictalot
endif

# predictalot CUDA: opt-in with PREDICTALOT_CUDA=1
ifeq ($(strip $(PREDICTALOT_CUDA)),1)
  _PROFILES += predictalot-cuda
endif

# decidealot: opt-in with DECIDEALOT=1 (CPU)
ifeq ($(strip $(DECIDEALOT)),1)
  _PROFILES += decidealot
endif

# decidealot CUDA: opt-in with DECIDEALOT_CUDA=1
ifeq ($(strip $(DECIDEALOT_CUDA)),1)
  _PROFILES += decidealot-cuda
endif

# CLM uses the local Qwen3-8B embeddings route, which lives in the llama.cpp
# CUDA profile. Starting a Decidealot CLM deployment always starts that route.
ifneq ($(filter 1,$(strip $(DECIDEALOT) $(DECIDEALOT_CUDA))),)
ifneq ($(strip $(DECIDEALOT_CLM_ENABLED)),false)
  override LLAMACPP_CUDA := 1
endif
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

# Compose only auto-loads docker-compose.override.yml when COMPOSE_FILE is
# unset, and setting COMPOSE_FILE here turns that off, so append it explicitly.
ifneq ($(wildcard docker-compose.override.yml),)
  _COMPOSE_FILES += docker-compose.override.yml
endif

override COMPOSE_FILE := $(subst $(space),:,$(strip $(_COMPOSE_FILES)))
export COMPOSE_FILE

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

# The copies themselves happen at parse time (top of this file), so every target
# already has them. This target reports the state and is the documented way to
# create the files without starting anything.
bootstrap:
	@echo ".env: present (created from .env.example, gitignored, yours to edit)"
	@echo ""
	@echo "Compose files in merge order:"
	@for f in $(_COMPOSE_FILES); do echo "  $$f"; done
	@echo ""
	@echo "docker-compose.yml is tracked and moves with the repository; it carries the"
	@echo "service definitions, nginx routes, and rate-limit zones that the rest of the"
	@echo "repo expects, so an edit there is overwritten on update. Put your own changes"
	@echo "in docker-compose.override.yml, which is gitignored and merges last:"
	@echo ""
	@echo "  services:"
	@echo "    claudebox:"
	@echo "      mem_limit: 8g"

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
	COMPOSE_PROFILES=claudebox,pibox-zai,pibox,cloudflared,hybrids3,browser,ollama,ollama-cuda,sdcpp,sdcpp-cuda,talkies,talkies-cuda,vllm,vllm-cuda,llamacpp,llamacpp-cuda,mcp,librechat,searxng,telethon,tailscale,predictalot,predictalot-cuda,decidealot,decidealot-cuda,audiolla,audiolla-cuda,flickies,flickies-cuda,piston,mailbox \
		docker compose down --remove-orphans

restart: down run-bg

restart-audiolla:
	@test -n "$(filter audiolla audiolla-cuda,$(_PROFILES))" || { echo "Enable AUDIOLLA=1 or AUDIOLLA_CUDA=1 first" >&2; exit 1; }
	docker compose up -d --no-deps --no-build --pull never --force-recreate $(filter audiolla audiolla-cuda,$(_PROFILES))

test:
	bash test.sh

test-unit:
	bash tests/unit/run.sh

build-decidealot:
	docker compose build decidealot decidealot-cuda

test-decidealot-coordination:
	docker build -f decidealot/Dockerfile -t aigate-decidealot:latest .
	RUNNER_IMAGE=aigate-decidealot:latest TEST_PYTHON=/opt/app-venv/bin/python TEST_DIRECTORY="$(CURDIR)/tests/decidealot" bash tests/unit/run.sh

test-config:
	docker run --rm \
		-v "$(CURDIR):/workspace:ro" \
		-w /workspace \
		-e PYTHONDONTWRITEBYTECODE=1 \
		python:3.12-alpine \
		python3 -m unittest discover -s tests/config -v

test-llamacpp-pull:
	docker run --rm \
		-v "$(CURDIR):/workspace:ro" \
		-w /workspace \
		python:3.12-slim-bookworm \
		python3 llamacpp/tests/test_pull_models.py -v

test-llamacpp-server:
	docker run --rm \
		-v "$(CURDIR):/workspace:ro" \
		-w /workspace \
		-e PYTHONPATH=/workspace/llamacpp/src \
		-e LLAMACPP_WRAP_MODELS_FILE=/workspace/llamacpp/models.cuda.json \
		--entrypoint python3 \
		aigate-llamacpp-cuda:latest \
		-m unittest llamacpp/tests/test_server.py -v

logs:
	docker compose logs -f

limits:
	@bash recommend-limits.sh

help:
	@echo ""
	@echo "Usage: make <target>"
	@echo ""
	@echo "Targets:"
	@echo "  bootstrap     Create .env from .env.example and show the active compose file chain"
	@echo "  run           Start the stack in foreground (auto-detects profiles from .env)"
	@echo "  run-bg        Start the stack in background"
	@echo "  down          Stop everything"
	@echo "  restart       Full restart (down + build-config + run-bg)"
	@echo "  restart-audiolla Recreate enabled Audiolla variants from locally available pinned images only"
	@echo "  build-config  Regenerate litellm/config.yaml from fragments"
	@echo "  limits        Check enabled services fit this machine, write CPU caps to .env.limits"
	@echo "  test          Run test suite (stack must be running)"
	@echo "  test-unit     Run LiteLLM callback unit tests against a throwaway Redis (no running stack)"
	@echo "  build-decidealot Build Aigate's CPU/CUDA Decidealot admission wrappers"
	@echo "  test-decidealot-coordination Test per-provider admission with a throwaway Redis"
	@echo "  test-config   Test provider activation and default CLM encoder selection"
	@echo "  test-llamacpp-pull Test llama.cpp model artifact selection and checksum verification"
	@echo "  test-llamacpp-server Test llama.cpp's public HTTP wrapper contract"
	@echo "  logs          Follow logs"
	@echo "  help          Show this help"
	@echo ""
	@echo "Profiles (set flag to 1 in .env to enable):"
	@echo "  claudebox     set CLAUDEBOX=1"
	@echo "  pibox-zai     set PIBOX_ZAI=1 (pi-coding-agent via z.ai/GLM)"
	@echo "  pibox  set PIBOX=1 (pi-coding-agent on this stack's own models; needs PIBOX_MODELS)"
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
	@echo "  decidealot    set DECIDEALOT=1 (CPU typed decisions, Laya + Von + CLM, MCP)"
	@echo "  decidealot-cuda set DECIDEALOT_CUDA=1 (NVIDIA GPU typed decisions, Laya + Von + CLM, MCP)"
	@echo "  decidealot CLM enabled by default (also starts llamacpp-cuda Qwen3-8B embeddings); disable with DECIDEALOT_CLM_ENABLED=false"
	@echo "  mailbox       set MAILBOX=1 (IMAP+SMTP gateway REST API + MCP — needs MAILBOX_CONFIG)"

	@echo "  mcp           (auto: any image/TTS/search provider enabled)"
	@echo ""
	@echo "Active profiles: $(if $(COMPOSE_PROFILES),$(COMPOSE_PROFILES),(none))"
	@echo ""
