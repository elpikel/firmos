# 🗺 Plan

Executable checklist for `/build-loop`. Top-to-bottom = dependency order.

## M0 — 🧱 Foundations

### STORY-001 — Owner account (#7)

> Decisions (#7): `mix phx.gen.auth Accounts User users --live` — magic link is the primary flow, generator's optional password kept as-is; `current_scope.user` per Phoenix 1.8; `/dashboard` is a placeholder LiveView that later M1 stories fill.
> Spec: `test/features/owner_account_test.exs` (pending until these tasks un-skip it).

- [x] **T1 · gen-auth** — Run `mix phx.gen.auth Accounts User users --live`, `mix deps.get`, `mix ecto.migrate`. Keep generator output (magic link + optional password). Generated tests in `test/firmos/accounts_test.exs` and `test/firmos_web/` pass. Un-skip the AC1 (sign up) and AC3 (invalid email) scenarios in `test/features/owner_account_test.exs`; they pass through `live(conn, ~p"/users/register")`.
  `story: STORY-001` · `depends-on: —` · `parallel-group: —`
- [x] **T2 · wire: dashboard into router** — Add `FirmosWeb.DashboardLive` at `live "/dashboard"` inside the `:require_authenticated_user` `live_session`. It renders `<Layouts.app flash={@flash} current_scope={@current_scope}>` with `id="dashboard"`, greets the owner's email, and shows an empty state (`id="dashboard-empty"`). Set `UserAuth.signed_in_path/1` to `~p"/dashboard"`, and update the generated tests that assert `~p"/"` as the post-login redirect. Un-skip AC2 (magic link → `/dashboard`) and AC4 (anonymous `/dashboard` → `/users/log-in`). Acceptance: the feature spec passes through the router.
  `story: STORY-001` · `depends-on: T1` · `parallel-group: —`

### STORY-002 — Polish UI (#12)

> Decisions (#12): Polish is the Gettext backend's `default_locale` (no per-request locale plug, no switcher — out of scope); English msgids stay the source, so an untranslated msgid falls back to EN. Generated phx.gen.auth copy and flashes go through `gettext/1`; Ecto errors through `errors.po`. `/` becomes a minimal Polish landing placeholder until STORY-005.
> Spec: `test/features/polish_ui_test.exs` (pending until these tasks un-skip it).

- [x] **T1 · locale: default to Polish** — Set `config :firmos, FirmosWeb.Gettext, default_locale: "pl"` and `<html lang="pl">` in `root.html.heex`. Acceptance: `Gettext.get_locale(FirmosWeb.Gettext) == "pl"` in a fresh process.
  `story: STORY-002` · `depends-on: —` · `parallel-group: —`
- [x] **T2 · gettext: wrap generated auth copy** — Run every user-facing string in `FirmosWeb.UserLive.*`, `UserSessionController`, `UserAuth` flashes and the `PageController` home template through `gettext/1` (English msgids). Replace the Phoenix placeholder on `/` with a minimal Firmos landing (`id="home-hero"`). `mix gettext.extract`.
  `story: STORY-002` · `depends-on: T1` · `parallel-group: —`
- [x] **T3 · translations: pl .po files** — `mix gettext.merge priv/gettext --locale pl`; translate every msgid in `pl/LC_MESSAGES/default.po` and `errors.po` (incl. the custom `User` changeset messages) into Polish. Update generated tests that assert English copy to the Polish text (expected strings only). Un-skip `test/features/polish_ui_test.exs`. Acceptance: the feature spec passes through `get(conn, ~p"/")` and the Gettext backend.
  `story: STORY-002` · `depends-on: T2` · `parallel-group: —`

### STORY-003 — AI provider adapter (#13)

> Decisions (#13): `Firmos.AI` is the behaviour + facade; it resolves the adapter at call time from `config :firmos, Firmos.AI, adapter:` (`Firmos.AI.Claude` by default, `Firmos.AI.Mock` in test). `Firmos.AI.Claude` POSTs to the Anthropic Messages API with Req; model, `max_tokens`, `receive_timeout` and retry come from `config :firmos, Firmos.AI.Claude` and per-call opts override them. The key is read in `runtime.exs` (required in prod, optional in dev, never read in test). Errors are values, never raised: `{:http_status, status, summary}`, the transport reason (e.g. `:timeout`), or `:missing_api_key`. No UI; the entry point is `Firmos.AI.complete/2`.
> Spec: `test/features/ai_provider_adapter_test.exs` (pending until these tasks un-skip it).

- [x] **T1 · deps: add Mox** — Add `{:mox, "~> 1.2", only: :test}`, `mix deps.get`. `Mox.defmock(Firmos.AI.Mock, for: Firmos.AI)` in `test/test_helper.exs`.
  `story: STORY-003` · `depends-on: —` · `parallel-group: —`
- [x] **T2 · behaviour: `Firmos.AI` facade** — `@callback complete(prompt, opts) :: {:ok, String.t()} | {:error, term()}` and `complete/2` that dispatches to the adapter read with `Application.fetch_env!/2` at call time. Un-skip AC3.
  `story: STORY-003` · `depends-on: T1` · `parallel-group: —`
- [x] **T3 · adapter: `Firmos.AI.Claude`** — Req POST `/v1/messages` (`x-api-key`, `anthropic-version: 2023-06-01`, JSON body `model`, `max_tokens`, `messages`, optional `system`); join the `text` content blocks. Map non-2xx → `{:error, {:http_status, status, summary}}`, transport errors → `{:error, reason}`, blank key → `{:error, :missing_api_key}`. Retry `:transient` with `max_retries` from config. Unit tests with `Req.Test` in `test/firmos/ai/claude_test.exs`. Un-skip AC1 and AC2.
  `story: STORY-003` · `depends-on: T2` · `parallel-group: —`
- [x] **T4 · wire: config** — `config.exs`: default adapter + Claude defaults (`base_url`, `model: "claude-sonnet-5-5"`, `max_tokens`, `receive_timeout`, retry). `test.exs`: `Firmos.AI.Mock`, `plug: {Req.Test, Firmos.AI.Claude}`, retry off, fake key. `runtime.exs`: `ANTHROPIC_API_KEY` for every env except test (required in prod, optional in dev). Acceptance: the full feature spec passes and `mix precommit` is clean.
  `story: STORY-003` · `depends-on: T3` · `parallel-group: —`

## M1 — 💡 Idea → plan → site

### STORY-005 — Describe the business idea (#15)

> Decisions (#15): `/` becomes `FirmosWeb.HomeLive` (in the `:current_user` live_session) with one idea textarea; `PageController` is removed. The idea is persisted server-side as a draft (`Firmos.Ideas`, table `ideas`), never in the cookie session (2000 PL chars can blow the 4 KB cookie, and magic-link sign-up may finish on another device). A visitor is sent to `/users/register?idea=<token>`; the registration form carries the token as a hidden field and `Ideas.attach_to_user/2` assigns the draft to the new user. A signed-in owner's idea is attached directly → `/dashboard`. Validation: trimmed text, 20–2000 codepoints, mirrored by a DB CHECK. `claimed_at` stays nil until STORY-006 turns the idea into a company; `Ideas.latest_unclaimed_for_user/1` is its read seam.
> Spec: `test/features/idea_prompt_test.exs` (pending until these tasks un-skip it).

- [ ] **T1 · schema: `ideas` table** — `mix ecto.gen.migration create_ideas`: `text` (text, NOT NULL, CHECK `ideas_text_length` 20–2000 `char_length`), `token` (text, NOT NULL, unique index), `user_id` (nullable FK → users, `on_delete: :delete_all`, `# nullable-fk:` comment), `claimed_at` (utc_datetime), timestamps (utc_datetime); index on `user_id`. `Firmos.Ideas.Idea` schema + changeset (trim, `validate_length` with gettext-able messages, `check_constraint`, `unique_constraint`; `user_id`/`token` never cast; Inspect hides `token`).
  `story: STORY-005` · `depends-on: —` · `parallel-group: —`
- [ ] **T2 · context: `Firmos.Ideas`** — `change_idea/1`, `create_draft/1` (random URL-safe token), `create_for_user/2` (scope), `get_draft_by_token/1` (only unattached drafts), `attach_to_user/2` (scope, token → `{:ok, idea} | {:error, :not_found}`), `latest_unclaimed_for_user/1` (scope). Unit tests in `test/firmos/ideas_test.exs` (boundaries 19/20/2000/2001, trimming, token read only while unattached).
  `story: STORY-005` · `depends-on: T1` · `parallel-group: —`
- [ ] **T3 · wire: `/` → `FirmosWeb.HomeLive`** — Replace `get "/", PageController, :home` with `live "/", HomeLive, :index` in the `:current_user` live_session; delete `PageController`, `PageHTML` and its test. Hero copy stays around `#idea-form` (`#idea-input` textarea, `#idea-submit`). Visitor submit → `Ideas.create_draft/1` → `push_navigate` to `/users/register?idea=<token>`; owner submit → `Ideas.create_for_user/2` → `/dashboard`. Un-skip AC1, AC3, AC4.
  `story: STORY-005` · `depends-on: T2` · `parallel-group: —`
- [ ] **T4 · wire: registration keeps the idea** — `UserLive.Registration` reads `?idea=` via `Ideas.get_draft_by_token/1`, renders `#preserved-idea` (escaped, no `raw/1`), carries `idea_token` as a hidden input, and after `Accounts.register_user/1` calls `Ideas.attach_to_user/2`. Un-skip AC2.
  `story: STORY-005` · `depends-on: T3` · `parallel-group: —`
- [ ] **T5 · translations: pl** — `mix gettext.extract --merge`; translate every new msgid in `pl/LC_MESSAGES/default.po` and `errors.po` (plural forms for the `%{count}` validation messages). Update copy-asserting tests. Acceptance: full feature spec green, `mix precommit` clean.
  `story: STORY-005` · `depends-on: T4` · `parallel-group: —`
