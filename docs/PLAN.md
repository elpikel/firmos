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

- [ ] **T1 · locale: default to Polish** — Set `config :firmos, FirmosWeb.Gettext, default_locale: "pl"` and `<html lang="pl">` in `root.html.heex`. Acceptance: `Gettext.get_locale(FirmosWeb.Gettext) == "pl"` in a fresh process.
  `story: STORY-002` · `depends-on: —` · `parallel-group: —`
- [ ] **T2 · gettext: wrap generated auth copy** — Run every user-facing string in `FirmosWeb.UserLive.*`, `UserSessionController`, `UserAuth` flashes and the `PageController` home template through `gettext/1` (English msgids). Replace the Phoenix placeholder on `/` with a minimal Firmos landing (`id="home-hero"`). `mix gettext.extract`.
  `story: STORY-002` · `depends-on: T1` · `parallel-group: —`
- [ ] **T3 · translations: pl .po files** — `mix gettext.merge priv/gettext --locale pl`; translate every msgid in `pl/LC_MESSAGES/default.po` and `errors.po` (incl. the custom `User` changeset messages) into Polish. Update generated tests that assert English copy to the Polish text (expected strings only). Un-skip `test/features/polish_ui_test.exs`. Acceptance: the feature spec passes through `get(conn, ~p"/")` and the Gettext backend.
  `story: STORY-002` · `depends-on: T2` · `parallel-group: —`
