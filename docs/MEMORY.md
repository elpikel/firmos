# 🧠 Memory

Dated decisions log, one line each, with the why.

- **2026-11-01** (#5): First market is Polish SMBs with a PL UI (udaina-style), not global solo founders, because it's a narrower, reachable audience and EN can be added later through Gettext.
- **2026-11-01** (#5): MVP (M1) is idea → AI plan → published landing page. The nightly autonomous loop is M2, because trust (activity log + undo) has to exist before agents act alone.
- **2026-11-01** (#5): LLM is the Claude API via Req behind a behaviour, so it can be mocked with Mox and swapped later.
- **2026-11-01** (#5): Integrations (inbox, ads, invoicing) are deferred to M3–M5 and are independent of each other, because each Polish integration is its own project.
- **2026-11-01** (#5): Issue #5 is docs only (PROJECT.md + STORIES.md). PLAN.md and pending specs wait for `/design`, because the open questions (site hosting, job library, research source) gate the task DAG.
- **2026-11-01** (#7): Auth is `mix phx.gen.auth Accounts User users --live`. Magic link is the primary flow and the generator's optional password is kept, because that means less custom code; "owner" is a role in the docs, not a table name.
- **2026-11-01** (#7): `/dashboard` ships as a placeholder LiveView (T2 after gen-auth T1), because AC2/AC4 need a protected landing page before M1 fills it.
- **2026-11-01** (#7): Auth tables keep phx.gen.auth's `timestamp` (utc_datetime) columns, not timestamptz, because the token expiry queries compare against `ago/2` (a timestamp param); timestamptz would make expiry depend on the DB session time zone.
- **2026-11-01** (#12): Polish is the Gettext backend's `default_locale`, not a per-request locale plug, because a language switcher is out of scope; EN msgids stay the source so untranslated copy falls back to English instead of raising.
- **2026-11-01** (#13): `Firmos.AI` resolves its adapter from app config at call time (not a module attribute), so test config can swap in `Firmos.AI.Mock` and no feature ever reaches the network.
- **2026-11-01** (#13): `Firmos.AI.Claude` returns errors as values (`{:http_status, s, summary}`, transport reason, `:missing_api_key`) and never raises, because AI calls will run inside LiveViews and Oban jobs where a crash would lose the owner's work; Req retries transient 5xx/429/timeouts twice, disabled in test.
- **2026-11-01** (#13): `ANTHROPIC_API_KEY` is required in prod but optional in dev, so the app boots locally without a key and AI calls answer `{:error, :missing_api_key}` instead of crashing.
