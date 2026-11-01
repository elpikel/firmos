---
name: onboard
description: >-
  Welcome someone who just cloned Firmos and get it running locally: check
  Elixir/Erlang and PostgreSQL, run `mix setup`, prove the test suite is green
  with `mix test`, start `mix phx.server`, and point them at the docs and the
  phase commands. Interviews them one question at a time and fixes the cause
  of any failure rather than papering over it. Use when the user types
  /onboard, or asks to set up, install, configure, or "get this running".
---

# 🚀 /onboard

You are welcoming someone to **Firmos**, a Phoenix 1.8 + LiveView + Ecto +
PostgreSQL app. They have just cloned the repo. By the end they should be
looking at it on `http://localhost:4000` with a green test suite, having
typed very little.

## 🧭 How to run this

- **One question per message.** Ask, wait, then ask the next. Use
  `AskUserQuestion` when the answer is a choice; plain text when free-form.
- **Offer a default for everything** you can derive (the dev DB settings in
  `config/dev.exs`, the port `4000`).
- **Say what you're about to do before you do it**, in one line, and how long
  it takes if it's slow (`mix setup` compiles every dep — a few minutes the
  first time).
- **Fix causes, not symptoms.** If a step fails, read the error out in plain
  words and fix the actual cause (wrong Elixir version, Postgres not
  running, wrong DB credentials). Never skip a failing step to "finish".
- **Resume, don't restart.** Re-running `/onboard` re-checks each step and
  picks up at the first one that isn't done.

## 🚨 Hard rules

- **Never touch a non-local database.** Only the dev/test DBs configured in
  `config/dev.exs` / `config/test.exs`. If `DATABASE_URL` is set in the shell,
  say so and ask before running anything that could use it.
- **Never edit config to paper over a local problem** (e.g. changing the DB
  password in `config/dev.exs` to match their machine) without asking. Offer
  an env var or a local `.envrc` instead, and keep it out of git.
- **Never echo a secret** back into the conversation.
- **No `mix deps.clean --all`** unless a dep is genuinely corrupt — say why
  first.

## 1 · Welcome

Three lines at most: what Firmos is (read the first lines of `README.md` and
`docs/PROJECT.md` if present — don't invent a pitch), that you'll ask one
question at a time, and that `/onboard` can be re-run anytime.

## 2 · Toolchain

Run in parallel and report as a short checklist:

- `elixir --version` — must satisfy `elixir:` in `mix.exs` (currently
  `~> 1.15`). If it doesn't, stop and offer the fix: `asdf`/`mise` with a
  `.tool-versions`, or Homebrew. Ask which they use; don't install a version
  manager unasked.
- `psql --version` and `pg_isready` — Postgres installed and accepting
  connections on localhost:5432. If not running, offer the right start
  command for how it was installed (`brew services start postgresql@16`,
  Postgres.app, or `docker run -d -p 5432:5432 -e POSTGRES_PASSWORD=postgres postgres:16`).
- `mix hex.info` / `mix local.hex --if-missing --force` and
  `mix local.rebar --if-missing --force` if Hex/Rebar are missing.

## 3 · Setup

1. Check the DB credentials `config/dev.exs` expects (default
   `postgres`/`postgres`) against their Postgres. If they differ, ask how
   they want to resolve it (see Hard rules).
2. `mix setup` — deps, `ecto.setup` (create + migrate + seeds), assets.
3. `mix test` — must be green before going further. A red suite on a fresh
   clone is a bug worth reporting: show the failure and offer `/git-issue`.

## 4 · Run it

Start the server in the background (`mix phx.server`), wait for
`Running FirmosWeb.Endpoint`, then tell them to open
`http://localhost:4000`. Mention `iex -S mix phx.server` for a console, and
`/dev/dashboard` for LiveDashboard.

## 5 · Hand over

A short map, five lines max:

- 📘 Rules for Claude live in `CLAUDE.md` → `AGENTS.md`.
- 🧭 Phase commands: `/explore` → `/design` → `/plan` → `/build-loop`;
  `/document` anytime; `/quick-fix` for small stuff.
- 🌿 Git: `/git-commit`, `/git-pr`, `/git-merge`, `/git-issue`.
- ✅ Before any commit: `mix precommit`.

Ask if they want to start with `/explore` (if `docs/PROJECT.md` is missing
or a stub) or pick an open issue (`gh issue list`).
