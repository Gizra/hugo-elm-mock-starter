#!/bin/bash
set -e

cd "$(dirname "$0")/.."

# Find a free port starting from 1313.
find_free_port() {
  local port=1313
  while ss -tuln 2>/dev/null | grep -q ":${port} " || \
        lsof -i ":${port}" >/dev/null 2>&1; do
    echo "Port ${port} is in use, trying next..." >&2
    port=$((port + 1))
  done
  echo "$port"
}

PORT=$(find_free_port)
export PORT

# Open the dev server in the browser once Hugo is responding. Runs in the
# background so `docker compose up` can stay in the foreground; exits quietly if
# the server never comes up or no opener is available.
open_when_ready() {
  local url="http://localhost:${PORT}"
  for _ in $(seq 1 60); do
    if curl -sf -o /dev/null "$url" 2>/dev/null; then
      echo "Hugo is ready — opening ${url}"
      if command -v xdg-open >/dev/null 2>&1; then
        xdg-open "$url" >/dev/null 2>&1
      elif command -v open >/dev/null 2>&1; then
        open "$url" >/dev/null 2>&1
      fi
      return
    fi
    sleep 1
  done
}
open_when_ready &

# Elm, Tailwind, and Hugo all run inside the container (Elm is baked into the
# image — see Dockerfile). The `elm` service compiles the app and watches
# src/*.elm; `tailwind` rebuilds CSS; Hugo live-reloads. No host toolchain needed.
echo "Starting Hugo dev server on http://localhost:${PORT}"
docker compose up --build
