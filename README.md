# Hugo + Elm Mock Starter

[![Build and Deploy](https://github.com/Gizra/hugo-elm-mock-starter/actions/workflows/build.yml/badge.svg)](https://github.com/Gizra/hugo-elm-mock-starter/actions/workflows/build.yml)
[![Lint](https://github.com/Gizra/hugo-elm-mock-starter/actions/workflows/lint.yml/badge.svg)](https://github.com/Gizra/hugo-elm-mock-starter/actions/workflows/lint.yml)
[![Pa11y](https://github.com/Gizra/hugo-elm-mock-starter/actions/workflows/pa11y.yml/badge.svg)](https://github.com/Gizra/hugo-elm-mock-starter/actions/workflows/pa11y.yml)

A starter kit for building **redesign mockups** and **prototype ideas** as a
static site: Hugo + Tailwind v4 with an embedded **Elm app** wired as an offline
**mock** (no backend). Use it to stand up a believable, interactive prototype
fast — then swap in your own UI.

## What's inside

- **Hugo** static site (single homepage) that embeds the Elm app.
- **Tailwind v4** — utility-first, stock classes plus a single `--color-accent`
  token. WCAG 2.1 AAA target.
- **Elm 0.19.2** app: a sessions sidebar + a chat column. It talks to its
  `sendToOpenAi` / `openAiEvent` ports; `assets/javascript/boot.js` answers with
  a scripted, streamed mock so the interaction runs entirely offline.
- **Docker Compose** dev stack (Hugo + Tailwind + Elm watchers) — no host
  toolchain needed.
- **CI**: ESLint, pa11y (WCAG 2.1 AAA), and a GitHub Pages build/deploy.

## Development

```bash
make dev   # docker compose up; finds a free port from 1313, prunes dangling images
```

This runs the Tailwind CLI watcher (`style.css` → `output.css`), the Hugo dev
server, and the Elm watcher (recompiles the embedded app on `.elm` change) — all
in Docker.

## The embedded app (mock)

The homepage mounts an Elm chat app. It is a **mock**: no network call is made.
`assets/javascript/boot.js` feeds the app a scripted stream of events so the
interaction can be demonstrated offline.

- Source: `elm/src/` (Elm 0.19.2). Compiles to
  `assets/javascript/vendor/elm-main.js` (committed, so Docker/CI builds need no
  Elm toolchain).
- Rebuild manually (in the container): `docker compose exec hugo sh elm/build.sh`.

To prototype your own idea, replace the scenario in `boot.js` and the view in
`elm/src/` — the port contract (`delta` / `questions` / `done` / `error`) is the
only thing that needs to stay stable.

## Accessibility

Target is WCAG 2.1 AAA. Run pa11y once the dev server is up:

```bash
docker compose exec hugo npm run pa11y
```

## Lint

```bash
docker compose exec hugo npm run lint   # or: npm run lint:fix
```

## Short comments

A comment is at most 30 words, and a paragraph in a `.md` file the same. Only
what a branch writes is measured; nothing already in the tree needs rewriting.

```bash
make comments   # the check CI runs, against origin/main (or BASE=<ref>)
```

## Build / deploy (GitHub Pages)

The base URL is required and not hard-coded. Set it via `HUGO_BASEURL`, or
replace the `baseURL: "/"` placeholder in `config/_default/config.yaml`.

```bash
HUGO_BASEURL=https://<user>.github.io/<repo>/ make build
```

CI (`.github/workflows/build.yml`) derives the base URL from the repo context
automatically.
