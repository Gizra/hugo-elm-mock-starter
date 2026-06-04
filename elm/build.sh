#!/bin/sh
#
# Compile the embedded Elm app into Hugo's assets dir, where Tailwind scans it
# for class names and baseof.html bundles it ahead of boot.js. Pass `watch` to
# recompile on change (needs fswatch).
#
# This is an offline mock: there is no network call. assets/javascript/boot.js
# starts this app and feeds it a scripted stream of events.

set -eu
cd "$(dirname "$0")"

OUTPUT="../assets/javascript/vendor/elm-main.js"

compile() {
  elm make src/Main.elm --output "$OUTPUT"
}

compile

if [ "${1:-}" = "watch" ]; then
  fswatch -o ./src | while read -r _; do compile; done
fi
