.PHONY: up down restart test logs help

# Start the full stack
up:
	docker compose up -d

# Stop everything
down:
	docker compose down

# Full restart
restart: down up

# Run all tests (stack must be running)
test:
	bash test.sh

# Follow logs
logs:
	docker compose logs -f

help:
	@echo "Available targets:"
	@echo "  up       - Start the full stack"
	@echo "  down     - Stop everything"
	@echo "  restart  - Full restart"
	@echo "  test     - Run all tests (stack must be running)"
	@echo "  logs     - Follow logs"
	@echo "  help     - Show this help message"
