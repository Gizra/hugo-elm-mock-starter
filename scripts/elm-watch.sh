#!/bin/sh
# Compile the embedded Elm app, then poll src/*.elm mtimes and recompile on
# change. Runs inside the Hugo container (Elm is baked into the image), so no
# host Elm toolchain is needed. Writes assets/javascript/vendor/elm-main.js,
# which Tailwind (@source) and Hugo live-reload. Uses `stat -c` because busybox
# `find` has no GNU -printf. Runs from elm/ so it finds elm.json (like build.sh).
set -u
cd /src/elm

compile() {
  elm make src/Main.elm --output ../assets/javascript/vendor/elm-main.js
}

echo "Compiling Elm app…"
compile || echo "Warning: initial Elm build failed — using existing elm-main.js."

last=""
while true; do
  now=$(find src -name '*.elm' -exec stat -c '%Y %n' {} \; 2>/dev/null | sort | md5sum)
  if [ "$now" != "$last" ]; then
    if [ -n "$last" ]; then
      echo "Elm change detected — recompiling…"
      compile || true
    fi
    last="$now"
  fi
  sleep 1
done
