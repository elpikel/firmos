# 🏢 Firmos — Project

> An AI team that runs the day-to-day of a small Polish business. The owner sets the direction; agents do the work and report back.

References: [polsia.com](https://polsia.com/) (idea → plan → nightly autonomous work → morning report) · [udaina.com](https://udaina.com/) (AI team for Polish SMBs: website, ads, customer service, invoices).

## 🎯 Problem

Owners of micro and small businesses in Poland handle the website, ads, customer messages and invoicing on their own, usually in the evenings. Agencies and freelancers cost too much and work too slowly for a business of 1–5 people. Today these tasks are either done badly or not done at all.

## 👤 Who it's for

- **Primary:** an owner of a Polish micro or small business (service or e-commerce, 1–10 people) who already has an idea or a running business and lacks the time to execute.
- **Secondary:** a would-be founder who wants to validate an idea quickly with a plan and a live landing page.
- **Not for:** larger companies with a marketing or IT team, regulated industries that need human sign-off on every message, or bookkeeping (that stays with the owner's accountant).

## 🧩 Core functionality

1. **💡 Idea prompt.** The home page is one input: "Describe your business." It works without an account until the owner saves.
2. **🔎 Research & plan.** AI researches the market and drafts a business plan: offer, target customer, competitors, pricing, channels, and a first-30-days task list.
3. **🌐 Website.** The plan becomes a generated landing page at a public URL that the owner can edit, publish and roll back.
4. **📊 Dashboard & activity log.** Every action an agent takes is logged with its inputs and outputs, and can be undone with one click.
5. **🌙 Autonomous loop.** Each night the agents review the business, pick the most valuable task, do it, and email a morning report.
6. **✋ Approvals.** Anything that spends money or publishes outside the approved plan waits for the owner's consent.
7. **💬 Customer communication.** AI drafts or sends replies to email, Messenger and Google reviews from the owner's price list and calendar. Complaints are escalated to the owner.
8. **📣 Ads.** Meta and Google campaigns run within a budget cap, and underperforming ads are paused.
9. **🧾 Invoicing & payments.** Invoices go through KSeF or Fakturownia/inFakt, with overdue reminders and payment tracking.
10. **💳 Plans & billing.** Start, Biznes and Pro subscriptions, with GDPR data export and deletion.

## 🗺 Milestones

| # | Milestone | Outcome | Depends on |
|---|---|---|---|
| **M0** | 🧱 Foundations | Accounts, PL locale, LLM adapter (Claude via Req behind a behaviour), background jobs, and an activity log | — |
| **M1** | 💡 Idea → Company *(MVP)* | Prompt → account → AI business plan → published landing page → dashboard with activity log and undo | M0 |
| **M2** | 🌙 Autonomous loop | Nightly agent task, morning email report, approval queue, task credits | M1 |
| **M3** | 💬 Customer communication | Connected inbox (Gmail/Outlook), AI replies from the price list, escalation, Google reviews | M2 |
| **M4** | 📣 Ads | Meta and Google Ads campaigns with a budget cap, auto-pause, and performance in the report | M2 |
| **M5** | 🧾 Invoicing & payments | KSeF/Fakturownia invoices, overdue reminders, Przelewy24/Stripe payment tracking | M2 |
| **M6** | 💳 Plans, billing & data | Start/Biznes/Pro subscriptions, plan limits, GDPR export and account deletion | M1 (M2 for credits) |

M3, M4 and M5 are independent of each other and can run in parallel once M2 lands. Stories for each milestone are in [STORIES.md](STORIES.md).

## ✅ Success (MVP)

- An owner gets from the first prompt to a published landing page in **under 10 minutes**.
- At least **60%** of generated plans are rated "useful" by the owner (thumbs up/down on the plan).
- Every agent action appears in the activity log and **100%** of reversible actions can be undone.

## 📦 Scope

- **In (M0–M1):** prompt input, sign-up/login, company profile, AI research and plan, generated landing page with publish and rollback, dashboard, activity log, PL UI.
- **Out (for now):** autonomous nightly work, external integrations (ads, inbox, invoicing, payments), billing, mobile apps, an EN UI, and bookkeeping.

## 🚧 Constraints

- 🇵🇱 Polish UI and content first, through Gettext, so EN can be added later.
- 🇪🇺 Data is stored in the EU under GDPR. Customer data is never used to train models for others.
- The owner stays the sender of every outbound message, and nothing is spent or published outside the plan without consent.
- Stack: Phoenix 1.8 / LiveView / Ecto / Postgres. The LLM is the Claude API via `Req`, behind a behaviour so it can be mocked in tests.

## ❓ Open questions

- TODO: Hosting for generated sites: subdomain (`<slug>.firmos.pl`) or path, and whether custom domains come in M1 or later?
- TODO: Choice of background-job library (Oban?) is left to `/design`.
- TODO: Web research source for the plan (Claude web search tool or a separate search API)?
- TODO: Is anonymous use allowed before sign-up, and how much (rate limits, abuse)?
- TODO: Final pricing and credit model (udaina: 99/259/459 zł; polsia: $49 + credits).

## ⚠️ Riskiest unknowns

- **Output quality:** generated plans and sites may be generic, which kills trust. Mitigation: owner feedback on every output, plus editable results.
- **Integration surface:** each Polish integration (KSeF, Allegro, InPost…) is its own project. Mitigation: no integrations until M3 or later, one at a time.
- **LLM cost per company:** the nightly loop has to fit inside the plan price.
