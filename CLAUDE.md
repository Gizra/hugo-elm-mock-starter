# Project Conventions

A Hugo + Tailwind v4 starter for building redesign mockups and prototype ideas.
A single homepage embeds an Elm app (sessions sidebar + chat) wired as an offline
**mock** — no backend, no network. Use it as the base for a new prototype: swap
the Elm view and the scripted mock in `boot.js` for your idea.

## Development

Start the dev server (finds a free port from 1313 and runs the Elm + Tailwind
watchers + Hugo, all in Docker):

```bash
bash scripts/dev.sh
```

The Tailwind CLI compiles `assets/css/style.css` → `assets/css/output.css`
(gitignored); Hugo serves the compiled file.

## Hugo build

Check the site builds without errors:

```bash
# If the dev server is already running (use the actual PORT):
docker compose exec hugo hugo --gc --minify

# Or build the gh-pages output from scratch (requires HUGO_BASEURL):
HUGO_BASEURL=https://<user>.github.io/<repo>/ bash scripts/build.sh
```

The base URL is intentionally not hard-coded — set `HUGO_BASEURL` or replace the
`baseURL: "/"` placeholder in `config/_default/config.yaml`.

## Accessibility

All HTML targets WCAG 2.1 AAA. After modifying any HTML/layout/CSS, run pa11y (0
errors expected).

```bash
# Single page (use the actual PORT):
docker compose exec hugo npx pa11y --standard WCAG2AAA --config .pa11y.json http://localhost:1313/

# All screens:
docker compose exec hugo npm run pa11y
```

Add new screens to the `paths` array in `.pa11yci.js` as they are built.

## CSS

Tailwind-first. `assets/css/style.css` holds **only** config: `@import
"tailwindcss"`, the `@source` globs, the `@theme` design tokens (one accent color
+ fonts), and a minimal `@layer base`. Express everything else with Tailwind
utilities in the markup — prefer a named utility over an arbitrary value when one
exists (`text-xs`, not `text-[11px]`); reach for arbitrary values
(`h-[calc(…)]`, `[writing-mode:vertical-rl]`) only when there is no close stock
class. **Do not** add component classes.

Recolor the project by changing `--color-accent` (and `-dark` / `-soft`) in
`style.css`; everything else is stock Tailwind. The accent values are chosen to
pass WCAG AAA (white text on accent; accent-dark text on accent-soft).

Reuse repeated markup via **Hugo partials**, not CSS classes. Note: inline
`var()` in a `style=""` attribute is stripped by Hugo's template CSS sanitizer —
set custom properties via arbitrary-property utilities instead.

## Embedded Elm app (mock)

The homepage embeds the Elm chat app (`elm/src/*.elm`). It is wired as a
**mock**: there is no network call. The Elm app talks to its
`sendToOpenAi` / `openAiEvent` ports, and `assets/javascript/boot.js` answers
with a scripted stream so the interaction can be shown offline.

- Source: `elm/src/` (Elm 0.19.2). Compiles to
  `assets/javascript/vendor/elm-main.js` (committed, so Docker/CI builds need no
  Elm toolchain).
- Rebuild manually (in the container): `docker compose exec hugo sh elm/build.sh`.
- The `elm` service in `docker-compose.yml` recompiles `elm-main.js` on `.elm`
  change (Tailwind `@source` + Hugo then live-reload). No host Elm toolchain is
  needed.
- The Elm app emits Tailwind class names as string literals; `style.css` has an
  `@source` for `elm-main.js` so those utilities are generated. After editing the
  Elm UI, that file is re-scanned automatically.
- Port event contract (see `boot.js` / `elm/src/OpenAi.elm`): `{type:'delta',
  text}`, `{type:'questions', questions}`, `{type:'done'}`, `{type:'error',
  message}`.

## JavaScript

JavaScript lives in `assets/javascript/*.js`, never inline in `<script>` tags in
templates (`vendor/` is generated/third-party and is ESLint-ignored). After
modifying any file there, run ESLint and expect 0 errors:

```bash
docker compose exec hugo npm run lint   # or: npm run lint:fix
```

## Code hygiene

If you come across stale code while working — a selector/class/reference that no
longer matches the markup, a dead handler, a pointer to a removed file — **fix
it, don't work around it.** Repair it to match current reality or remove it if
the feature is genuinely gone.

## Git

Commit and push freely on a feature branch — no need to ask first. Never
force-push. Don't push directly to `main` or merge a PR without explicit
approval.
