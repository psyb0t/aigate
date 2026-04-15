-include .env
-include .env.limits
export

.PHONY: run run-bg down restart test logs limits help

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

run:
	$(check_file_vars)
	@echo "Active profiles: $(if $(COMPOSE_PROFILES),$(COMPOSE_PROFILES),(none))"
	docker compose up --build

run-bg:
	$(check_file_vars)
	@echo "Active profiles: $(if $(COMPOSE_PROFILES),$(COMPOSE_PROFILES),(none))"
	docker compose up -d --build

down:
	docker compose down --remove-orphans

restart: down run

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
