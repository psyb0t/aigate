-include .env
export

.PHONY: run run-bg down restart test logs help

# ── Profile detection ─────────────────────────────────────────────────────────

comma := ,
empty :=
space := $(empty) $(empty)

_PROFILES :=

# claudebox: OAuth token or Anthropic API key
ifneq ($(strip $(CLAUDE_CODE_OAUTH_TOKEN))$(strip $(CLAUDEBOX_ANTHROPIC_API_KEY)),)
  _PROFILES += claudebox
endif

# claudebox-zai: z.ai auth token
ifneq ($(strip $(ZAI_AUTH_TOKEN)),)
  _PROFILES += claudebox-zai
endif

# cloudflared: opt-in with CLOUDFLARED=1
ifeq ($(strip $(CLOUDFLARED)),1)
  _PROFILES += cloudflared
endif

override COMPOSE_PROFILES := $(subst $(space),$(comma),$(strip $(_PROFILES)))
export COMPOSE_PROFILES

# ── Targets ───────────────────────────────────────────────────────────────────

run:
	@echo "Active profiles: $(if $(COMPOSE_PROFILES),$(COMPOSE_PROFILES),(none))"
	docker compose up

run-bg:
	@echo "Active profiles: $(if $(COMPOSE_PROFILES),$(COMPOSE_PROFILES),(none))"
	docker compose up -d

down:
	docker compose down

restart: down run

test:
	bash test.sh

logs:
	docker compose logs -f

help:
	@echo ""
	@echo "Usage: make <target>"
	@echo ""
	@echo "Targets:"
	@echo "  run      Start the stack (profiles auto-detected from .env)"
	@echo "  down     Stop everything"
	@echo "  restart  Full restart"
	@echo "  test     Run test suite (stack must be running)"
	@echo "  logs     Follow logs"
	@echo "  help     Show this help"
	@echo ""
	@echo "Profiles (auto-enabled when credentials are set in .env):"
	@echo "  claudebox     set CLAUDE_CODE_OAUTH_TOKEN or CLAUDEBOX_ANTHROPIC_API_KEY"
	@echo "  claudebox-zai set ZAI_AUTH_TOKEN"
	@echo "  cloudflared   set CLOUDFLARED=1"
	@echo ""
	@echo "Active profiles: $(if $(COMPOSE_PROFILES),$(COMPOSE_PROFILES),(none))"
	@echo ""
