# Development targets. Everything runs in Docker — no host toolchain needed.

.PHONY: dev stop build lint pa11y clean

# Find a free port starting from 1313 (each candidate must be free).
define FIND_PORT
port=1313; \
while ss -tuln 2>/dev/null | grep -q ":$${port} " || lsof -i ":$${port}" >/dev/null 2>&1; do \
  echo "Port $${port} is in use, trying next..." >&2; \
  port=$$((port + 1)); \
done; \
echo $$port
endef

## dev: start the dev stack (Tailwind + Elm watchers + Hugo server) on a free port.
dev:
	@PORT=$$($(FIND_PORT)); \
	export PORT; \
	echo "Starting Hugo dev server on http://localhost:$${PORT}"; \
	( url="http://localhost:$${PORT}"; \
	  for _ in $$(seq 1 60); do \
	    if curl -sf -o /dev/null "$$url" 2>/dev/null; then \
	      echo "Hugo is ready — opening $$url"; \
	      { command -v xdg-open >/dev/null 2>&1 && xdg-open "$$url" >/dev/null 2>&1; } || \
	      { command -v open >/dev/null 2>&1 && open "$$url" >/dev/null 2>&1; } || true; \
	      exit 0; \
	    fi; \
	    sleep 1; \
	  done ) & \
	docker compose build && \
	docker image prune -f >/dev/null && \
	docker compose up

## stop: stop and remove the dev containers.
stop:
	docker compose down --remove-orphans

## build: build the production site into public-build/ and deploy to gh-pages.
build:
	bash scripts/build.sh

## lint: run ESLint inside the running hugo container.
lint:
	docker compose exec hugo npm run lint

## pa11y: run the WCAG 2.1 AAA accessibility checks against the dev server.
pa11y:
	docker compose exec hugo npm run pa11y

## clean: stop containers and remove dangling images and build output.
clean:
	docker compose down --remove-orphans --rmi local || true
	docker image prune -f
	rm -rf public public-build resources .hugo_build.lock
