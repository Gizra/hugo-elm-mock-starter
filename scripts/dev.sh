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

# Elm, Tailwind, and Hugo all run inside the container (Elm is baked into the
# image — see Dockerfile). The `elm` service compiles the app and watches
# src/*.elm; `tailwind` rebuilds CSS; Hugo live-reloads. No host toolchain needed.
echo "Starting Hugo dev server on http://localhost:${PORT}"
docker compose up --build
