# Firmos

Phoenix 1.8 web app (LiveView 1.1, Ecto 3.13, PostgreSQL, Tailwind v4, Req, Swoosh).
OTP app `:firmos` — domain in `lib/firmos/`, web in `lib/firmos_web/`.

Phoenix/LiveView/HEEx/Ecto rules: @AGENTS.md

## 🛠 Commands

- `mix setup` — deps, DB create/migrate/seed, assets
- `mix phx.server` / `iex -S mix phx.server` — run on http://localhost:4000
- `mix test` · `mix test path/to/file_test.exs:LINE` · `mix test --failed`
- `mix precommit` — compile (warnings as errors), unlock unused deps, format, test. **Run before saying you're done.**
- `mix ecto.gen.migration name_with_underscores` — always generate migrations this way

## 📏 Rules

- DO NOT REPORT SOMETHING IS FIXED IF YOU HAVEN'T COMPILED THE APP (`mix compile --warnings-as-errors` at minimum, `mix precommit` before done).
- DO NOT dig through `deps/` for answers. Check hexdocs.pm / `mix help <task>` first.
- Add Hex deps to `mix.exs` with a version requirement from hex.pm, then `mix deps.get`. No deps the task didn't ask for.
- Web layer (`FirmosWeb.*`) talks to contexts, never to `Firmos.Repo` directly.
- Ecto queries use named bindings: `from(o in Order, as: :order)`.
- Tests: ExUnit; BDD feature specs live in `test/features/` (see `bdd-specs` skill).
- Use emoji for markdown documents for readability.
- Get to the point, be terse. Tokens are water, we're in the desert.

## 🧭 Workflow (phase commands)

Each doc has **one owner** — only that command writes it (others append to `docs/MEMORY.md`).

| Command | Owns |
|---|---|
| `/init` | `CLAUDE.md`, `docs/` skeleton |
| `/explore` | `docs/PROJECT.md` — problem, who, scope |
| `/design` | `docs/ARCHITECTURE.md`, `docs/SPEC.md` — contexts, schema, decisions |
| `/plan` | `docs/STORIES.md`, `docs/PLAN.md` + pending specs in `test/features/` |
| `/spec` | pending ExUnit specs for stories without coverage |
| `/build-loop` | executes `docs/PLAN.md`: `builder` agent builds → `reviewer` agent gates → commit |
| `/document` | `README.md`, curates `docs/MEMORY.md` |
| `/quick-fix` | small one-spot fixes, no plan |
| `/issue` | GitHub issue → triage → quick-fix or plan + build-loop → PR |

**Given a GitHub issue URL or number, run `/issue`.** Issues labelled `claude` run it automatically in CI (`.github/workflows/claude-issue.yml`).

Git: `/git-commit`, `/git-pr`, `/git-merge`, `/git-issue`, `/git-remote` (follow the `github` skill). Main branch: `main`.

## 🧠 Skills (`.claude/skills/`)

`elixir-best-practices` · `postgres-dba` (Ecto migrations/schemas) · `security-web` (Phoenix/LiveView) ·
`design-principles` · `solid-principles` · `gof-patterns` · `bdd-specs` (ExUnit) · `user-stories` ·
`github` · `agent-teams` · `onboard`
