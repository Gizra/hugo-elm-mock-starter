#!/usr/bin/env bash
#
# Codespace post-create setup. Non-fatal throughout: a failed optional step must not
# block Codespace creation. See .devcontainer/devcontainer.json.
set -u

# Elm watcher that the dev stack runs on the host (this Codespace container). If elm is
# missing, the dev stack falls back to the committed elm-main.js — installing it enables
# live Elm recompiles on .elm change.
npm install -g elm || echo "post-create: elm install failed; committed elm-main.js still serves."

echo "post-create complete. Run 'make dev' to start Hugo."
