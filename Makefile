# Development and deploy targets. Everything runs in Docker — no host toolchain
# needed. .ONESHELL: each recipe runs as one shell script (needed for the
# multi-line `build` deploy recipe; `cd` persists between lines).

SHELL := /bin/bash
.ONESHELL:

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

## build: build the production site into public-build/ and deploy it to the
## gh-pages branch. Requires HUGO_BASEURL (or a real baseURL in
## config/_default/config.yaml).
build:
	@set -e
	TODAY=$$(date -u)
	HOST_UID=$$(id -u)
	HOST_GID=$$(id -g)
	PROJECT="$(notdir $(CURDIR))-build"
	if [ "$$(git status -s)" ]; then
		echo "The working directory is dirty. Please commit any pending changes."
		exit 1
	fi
	# The base URL is required. Prefer the HUGO_BASEURL env var; otherwise fall
	# back to `baseURL` in config/_default/config.yaml (ignoring the "/" placeholder).
	BASE_URL="$${HUGO_BASEURL:-}"
	if [ -z "$$BASE_URL" ]; then
		BASE_URL=$$(grep -E '^baseURL:' config/_default/config.yaml | head -1 | sed -E 's/^baseURL:[[:space:]]*"?([^"]*)"?[[:space:]]*$$/\1/')
		if [ "$$BASE_URL" = "/" ]; then BASE_URL=""; fi
	fi
	if [ -z "$$BASE_URL" ]; then
		echo "No base URL set." >&2
		echo "Set it one of two ways:" >&2
		echo "  1. Per build:  HUGO_BASEURL=https://<user>.github.io/<repo>/ make build" >&2
		echo "  2. Permanently: replace the \"/\" placeholder for 'baseURL' in config/_default/config.yaml" >&2
		exit 1
	fi
	# Build the Docker image (separate project name to avoid conflicting with dev).
	# Only the `tailwind` service has a build directive; `hugo` reuses the image.
	COMPOSE_PROJECT_NAME="$$PROJECT" docker compose build tailwind
	docker image prune -f >/dev/null
	echo "Pulling last changes from origin"
	git fetch origin gh-pages 2>/dev/null || true
	echo "Deleting old publication"
	rm -rf public-build
	mkdir public-build
	git worktree prune
	rm -rf .git/worktrees/public-build/
	echo "Checking out gh-pages branch into public-build"
	if git show-ref --verify --quiet refs/remotes/origin/gh-pages; then
		git worktree add -B gh-pages public-build origin/gh-pages
	else
		echo "gh-pages branch does not exist yet — creating orphan branch"
		git worktree add --detach public-build
		cd public-build && git checkout --orphan gh-pages && git reset --hard && cd ..
	fi
	echo "Removing existing files"
	find public-build -mindepth 1 ! -name '.git' -exec rm -rf {} + 2>/dev/null || true
	echo "Generating site (base URL: $$BASE_URL)"
	COMPOSE_PROJECT_NAME="$$PROJECT" docker compose run --rm \
	  -e HUGO_ENV=production \
	  -e HUGO_BASEURL="$$BASE_URL" \
	  --no-deps \
	  hugo sh -c "cd /src/assets/css && npx @tailwindcss/cli -i ./style.css -o ./output.css && cd /src && hugo --minify --baseURL '$$BASE_URL' --destination public-build && chown -R $$HOST_UID:$$HOST_GID /src/public-build"
	echo "Updating gh-pages branch"
	cd public-build
	git config user.name "$${GIT_DEPLOY_NAME:-github-actions[bot]}"
	git config user.email "$${GIT_DEPLOY_EMAIL:-41898282+github-actions[bot]@users.noreply.github.com}"
	git add --all
	if git diff --cached --quiet; then
		echo "No changes to deploy — gh-pages already up to date."
	else
		git commit -m "Deploy to gh-pages: $$TODAY"
		echo "Deploying to Github Pages"
		git push origin gh-pages:gh-pages
	fi

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
