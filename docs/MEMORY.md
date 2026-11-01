# 🧠 Memory

Dated decisions log, one line each, with the why.

- **2026-11-01** (#5): First market is Polish SMBs with a PL UI (udaina-style), not global solo founders, because it's a narrower, reachable audience and EN can be added later through Gettext.
- **2026-11-01** (#5): MVP (M1) is idea → AI plan → published landing page. The nightly autonomous loop is M2, because trust (activity log + undo) has to exist before agents act alone.
- **2026-11-01** (#5): LLM is the Claude API via Req behind a behaviour, so it can be mocked with Mox and swapped later.
- **2026-11-01** (#5): Integrations (inbox, ads, invoicing) are deferred to M3–M5 and are independent of each other, because each Polish integration is its own project.
- **2026-11-01** (#5): Issue #5 is docs only (PROJECT.md + STORIES.md). PLAN.md and pending specs wait for `/design`, because the open questions (site hosting, job library, research source) gate the task DAG.
- **2026-11-01** (#7): Auth is `mix phx.gen.auth Accounts User users --live`. Magic link is the primary flow and the generator's optional password is kept, because that means less custom code; "owner" is a role in the docs, not a table name.
- **2026-11-01** (#7): `/dashboard` ships as a placeholder LiveView (T2 after gen-auth T1), because AC2/AC4 need a protected landing page before M1 fills it.
