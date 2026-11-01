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
- **2026-11-01** (#13): A 200 is only `{:ok, text}` on a finished turn with text; `refusal` → `{:refusal, details}`, `max_tokens`/context-window → `{:truncated, text}`, empty → `:empty_response`, because thinking eats `max_tokens` and a silently partial business plan is worse than an error. Default `max_tokens` is 16_000.
- **2026-11-01** (#15): The home-page idea is stored server-side as an `ideas` draft keyed by a random token (passed as `/users/register?idea=<token>`), not in the cookie session, because 2000 Polish characters can exceed the 4 KB cookie and magic-link sign-up may finish on another device; the token only reads that one unattached draft and is spent once the draft is attached to a user.
- **2026-11-01** (#15): `ideas.claimed_at` means "turned into a company" (set by STORY-006), not "attached to a user" (that is `user_id`), so `Ideas.latest_unclaimed_for_user/1` is the seam STORY-006 reads from.
- **2026-11-01** (#15): Idea length (20–2000) is counted in codepoints after trimming, matching the DB CHECK `char_length`, so the changeset and the constraint can never disagree on a grapheme-vs-codepoint edge case.
- **2026-11-01** (#16): The idea becomes a company when the owner lands on `/dashboard` (`Companies.ensure_company_from_idea/1` in mount), not inside registration, because magic-link sign-up finishes in another request and possibly on another device; claiming with a conditional `UPDATE … WHERE claimed_at IS NULL` inside the insert's transaction makes the double LiveView mount and parallel tabs create exactly one company, with a unique index on `companies.idea_id` as the backstop.
- **2026-11-01** (#16): `companies.idea_id` is nullable with `on_delete: :nilify_all`, because companies can exist without an idea (STORY-011 adds more) and deleting an idea must never delete the company built from it.
- **2026-11-01** (#16): A new company's name is the translated placeholder "Moja firma", not a truncation of the idea, because a cut-off sentence makes a bad company name and the owner renames it on the profile.
