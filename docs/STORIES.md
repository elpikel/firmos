# 📋 User Stories

> Canonical backlog, consumed by the `bdd-specs` skill. Story → Feature, AC → Scenario, each `Then` → one Specification.
> Milestones are defined in [PROJECT.md](PROJECT.md#-milestones). M0–M1 are fully specified. M2 has its ACs drafted. M3–M6 are placeholders to refine before they're picked up.

## ✅ Definition of Ready

- Role, capability and value are stated and non-hollow.
- Happy-path ACs exist in Given/When/Then form.
- Out-of-scope notes make the boundary explicit.
- The story passes INVEST (its ACs can be enumerated).

## 🏁 Definition of Done

- All ACs pass as executable specs (`test/features/`).
- Sad-path ACs are covered.
- `mix precommit` is clean, and the change is reviewed by the `reviewer` agent.
- User-facing copy is in Polish through Gettext.

## 👥 Roles

- **Visitor**: not signed in, on the home page.
- **Owner**: signed-in business owner. Owns one or more companies.
- **Customer**: a member of the public who visits an owner's generated site.

---

## 🧱 Epic M0: Foundations

_Shared plumbing that every later milestone builds on._

### STORY-001 — Owner account

As an **owner**,
I want **to sign up and log in with my email**,
so that **my companies and plans are saved and private to me**.

**Size:** M · **Status:** ready

**Acceptance criteria**

_Happy path:_

```
AC1 — sign up
  Given a visitor on the registration page
  When  they submit a valid email
  Then  an account is created and a login link is emailed

AC2 — log in
  Given a registered owner with a valid magic link
  When  they open the link
  Then  they are signed in and redirected to their dashboard
```

_Sad path:_

```
AC3 — rejects invalid email
  Given a visitor on the registration page
  When  they submit "not-an-email"
  Then  the form shows an email format error

AC4 — dashboard requires login
  Given a visitor who is not signed in
  When  they open /dashboard
  Then  they are redirected to the login page
```

**Out of scope:** social login, 2FA, teams/multiple users per company.

**Notes:** > ASSUMPTION: `mix phx.gen.auth` with magic links, and `current_scope` per Phoenix 1.8.

---

### STORY-002 — Polish UI

As an **owner**,
I want **the whole interface in Polish**,
so that **I can use Firmos without switching languages**.

**Size:** S · **Status:** ready

**Acceptance criteria**

```
AC1 — default locale is Polish
  Given any visitor
  When  they open the home page
  Then  the UI copy is rendered in Polish
```

_Sad path:_

```
AC2 — missing translation falls back
  Given a message with no PL translation
  When  it is rendered
  Then  the source (EN) string is shown instead of an error
```

**Out of scope:** a language switcher and EN content generation.

---

### STORY-003 — AI provider adapter

As an **owner**,
I want **AI-generated content to come from one reliable provider integration**,
so that **plans and sites are generated consistently and failures are handled gracefully**.

**Size:** M · **Status:** ready

**Acceptance criteria**

```
AC1 — generate text
  Given a configured Claude API key
  When  the app requests a completion for a prompt
  Then  it returns {:ok, text}
```

_Sad path:_

```
AC2 — provider error is surfaced
  Given the provider returns a 5xx or times out
  When  the app requests a completion
  Then  it returns {:error, reason} without crashing the caller

AC3 — tests never hit the network
  Given the test environment
  When  any feature generates AI content
  Then  the call goes to the Mox mock, not the real API
```

**Out of scope:** multi-provider routing and streaming to the UI (revisit in M1 if generation is slow).

**Notes:** a behaviour (e.g. `Firmos.AI`) with a Req-based Claude adapter. The key comes from runtime config.

---

### STORY-004 — Activity log

As an **owner**,
I want **every action taken on my company recorded with what changed**,
so that **I can see and trust what the AI did**.

**Size:** M · **Status:** ready

**Acceptance criteria**

```
AC1 — action is recorded
  Given an owner's company
  When  any agent or the owner changes company content
  Then  an activity entry is stored with actor, action, timestamp and summary

AC2 — owner sees their log
  Given a company with activity entries
  When  the owner opens the activity log
  Then  entries are listed newest first
```

_Sad path:_

```
AC3 — log is private
  Given owner A and owner B's company
  When  owner A requests B's activity log
  Then  access is denied (404)
```

**Out of scope:** undo (STORY-010) and export.

---

## 💡 Epic M1: Idea → Company (MVP)

_A visitor describes an idea and leaves with an AI business plan and a live landing page._

### STORY-005 — Describe the business idea

As a **visitor**,
I want **to type my business idea into a single prompt on the home page**,
so that **I can start without filling in long forms**.

**Size:** S · **Status:** ready

**Acceptance criteria**

```
AC1 — prompt is the home page
  Given a visitor
  When  they open /
  Then  a single idea input with a submit button is shown

AC2 — idea is accepted
  Given a visitor on the home page
  When  they submit an idea of 20–2000 characters
  Then  they are taken to the sign-up step with the idea preserved
```

_Sad path:_

```
AC3 — too short
  Given a visitor on the home page
  When  they submit an idea shorter than 20 characters
  Then  a validation error asks for more detail

AC4 — too long
  Given a visitor on the home page
  When  they submit an idea longer than 2000 characters
  Then  a validation error states the limit
```

**Out of scope:** file and URL attachments, voice input.

**Notes:** > ASSUMPTION: sign-up is required before any AI generation (cost and abuse control). See the open question in PROJECT.md.

---

### STORY-006 — Create a company from the idea

As an **owner**,
I want **my submitted idea saved as a new company once I sign up**,
so that **I don't have to type it again**.

**Size:** S · **Status:** ready

**Acceptance criteria**

```
AC1 — company created after sign-up
  Given a visitor who submitted an idea and then signed up
  When  they land on the dashboard
  Then  a company exists that is owned by them, with the idea as its description

AC2 — company profile basics
  Given a new company
  When  the owner opens its profile
  Then  they can edit name, industry, city and contact email
```

_Sad path:_

```
AC3 — profile validation
  Given a company profile form
  When  the owner clears the name and saves
  Then  a "name is required" error is shown
```

**Out of scope:** importing data from CEIDG/KRS/GUS (later), multiple owners.

---

### STORY-007 — AI business plan

As an **owner**,
I want **an AI-generated business plan for my idea**,
so that **I know who my customer is, what to offer, at what price and what to do first**.

**Size:** L · **Status:** ready

**Acceptance criteria**

```
AC1 — generation starts automatically
  Given a newly created company
  When  the owner reaches the dashboard
  Then  plan generation runs in the background and a progress state is shown

AC2 — plan has required sections
  Given plan generation succeeded
  When  the owner opens the plan
  Then  it shows offer, target customer, competitors, pricing, channels and a 30-day task list

AC3 — plan is logged
  Given plan generation succeeded
  When  the owner opens the activity log
  Then  a "plan generated" entry is listed

AC4 — owner rates the plan
  Given a generated plan
  When  the owner clicks thumbs up or thumbs down
  Then  the rating is stored on the plan
```

_Sad path:_

```
AC5 — generation fails
  Given the AI provider returns an error
  When  plan generation runs
  Then  the owner sees a failure message with a "try again" button

AC6 — regenerate
  Given an existing plan
  When  the owner clicks "regenerate"
  Then  a new plan version is created and the previous one is kept
```

**Out of scope:** live web research (open question), editing the plan section by section.

---

### STORY-008 — Generate a landing page

As an **owner**,
I want **a landing page generated from my plan**,
so that **customers can find my business right away**.

**Size:** L · **Status:** ready

**Acceptance criteria**

```
AC1 — draft site generated
  Given a company with a generated plan
  When  the owner clicks "create website"
  Then  a draft landing page is generated with hero, offer, pricing and contact sections

AC2 — preview
  Given a draft site
  When  the owner opens the preview
  Then  the draft is rendered exactly as customers would see it
```

_Sad path:_

```
AC3 — no plan yet
  Given a company without a plan
  When  the owner opens the website section
  Then  "create website" is disabled with a hint to generate a plan first

AC4 — generation fails
  Given the AI provider returns an error
  When  site generation runs
  Then  the owner sees a failure message and no draft is saved
```

**Out of scope:** multi-page sites, custom templates and a drag-and-drop editor.

---

### STORY-009 — Edit and publish the site

As an **owner**,
I want **to edit my site's text and publish it to a public URL**,
so that **customers see accurate information about my business**.

**Size:** M · **Status:** ready

**Acceptance criteria**

```
AC1 — edit content
  Given a draft site
  When  the owner changes the hero headline and saves
  Then  the preview shows the new headline

AC2 — publish
  Given a draft site
  When  the owner clicks "publish"
  Then  the site is reachable by a customer at its public URL

AC3 — publish is logged
  Given a site was published
  When  the owner opens the activity log
  Then  a "site published" entry is listed
```

_Sad path:_

```
AC4 — unpublished site is private
  Given a site that was never published
  When  a customer opens its public URL
  Then  they get a 404

AC5 — slug collision
  Given another company already uses slug "piekarnia"
  When  the owner sets their slug to "piekarnia"
  Then  a "slug already taken" error is shown
```

**Out of scope:** custom domains and SEO settings.

**Notes:** the URL scheme (subdomain or path) is an open question for `/design`.

---

### STORY-010 — Undo a change

As an **owner**,
I want **to undo any site change with one click**,
so that **I can safely let the AI make edits**.

**Size:** M · **Status:** ready

**Acceptance criteria**

```
AC1 — roll back
  Given a published site with two versions
  When  the owner clicks "undo" on the latest change in the activity log
  Then  the previous version is live again

AC2 — undo is logged
  Given the owner undid a change
  When  they open the activity log
  Then  an "undo" entry referencing the original change is listed
```

_Sad path:_

```
AC3 — nothing to undo
  Given a site with a single version
  When  the owner views its activity entry
  Then  no undo action is offered
```

**Out of scope:** undoing plan versions (they're kept side by side instead).

---

### STORY-011 — Company dashboard

As an **owner**,
I want **one dashboard showing my plan, my site status and recent activity**,
so that **I can see the state of my business at a glance**.

**Size:** M · **Status:** ready

**Acceptance criteria**

```
AC1 — overview
  Given a company with a plan and a published site
  When  the owner opens the dashboard
  Then  plan summary, site status with public link, and the 5 latest activities are shown

AC2 — switch company
  Given an owner with two companies
  When  they select the other company
  Then  the dashboard shows that company's data
```

_Sad path:_

```
AC3 — empty state
  Given an owner with no companies
  When  they open the dashboard
  Then  they are prompted to describe a business idea
```

**Out of scope:** analytics and traffic stats (M2 report).

---

## 🌙 Epic M2: Autonomous loop

_Agents work overnight and report every morning, within limits the owner approves._

### STORY-012 — Nightly task

As an **owner**,
I want **an agent to pick and complete one high-value task for my company each night**,
so that **the business moves forward without my time**.

**Size:** L · **Status:** ready

**Acceptance criteria**

_Happy path:_

```
AC1 — nightly website task
  Given a company with a ready plan and a site draft
  When  the nightly run executes (02:00 Europe/Warsaw)
  Then  the agent picks the next open 30-day plan task that the website can serve,
        creates a new site version (source agent), marks the task done,
        and logs it in the activity log (undoable)

AC2 — publishing waits for approval
  Given a published site
  When  the nightly run changes the draft
  Then  the change is not published; a publish approval is queued (STORY-014)
```

_Sad path:_

```
AC3 — provider fails
  Given the AI provider fails
  When  the nightly run executes
  Then  the run is marked failed, no version is created, and the next night tries again

AC4 — nothing to do
  Given a company without a ready plan, without a site, or with no open tasks
  When  the nightly run executes
  Then  the run is skipped and nothing changes; at most one run per company per night
```

**Out of scope:** integrations (inbox, ads, invoices) and choosing tasks outside the website.

---

### STORY-013 — Morning report

As an **owner**,
I want **a morning email summarising what was done overnight and what needs my decision**,
so that **I stay in control in two minutes a day**.

**Size:** M · **Status:** ready

**Acceptance criteria**

_Happy path:_

```
AC1 — report is sent
  Given completed agent tasks since the last report or pending approvals
  When  it is 07:00 Europe/Warsaw
  Then  the owner receives a Polish email listing completed tasks and pending approvals with links
```

_Sad path:_

```
AC2 — nothing to report
  Given no agent activity and no pending approvals
  When  the report runs
  Then  no email is sent

AC3 — once a day
  Given a report was already sent today
  When  the report runs again
  Then  no second email is sent
```

**Out of scope:** report settings/opt-out, ad and invoice sections (M4/M5).

---

### STORY-014 — Approval queue

As an **owner**,
I want **to approve or reject agent actions that publish outside the plan**,
so that **nothing goes live without my consent**.

**Size:** M · **Status:** ready

**Acceptance criteria**

_Happy path:_

```
AC1 — approve
  Given a pending request to publish a site version
  When  the owner approves it
  Then  that version is published and the approval is logged

AC2 — reject
  Given a pending request to publish a site version
  When  the owner rejects it
  Then  it is discarded, nothing is published, and the rejection is logged
```

_Sad path:_

```
AC3 — outdated request
  Given the owner edited the draft after the request was created
  When  the owner approves the request
  Then  it is refused as outdated

AC4 — private
  Given owner A and owner B's approval
  When  owner A opens or acts on it
  Then  access is denied (404)
```

**Notes:** the dashboard shows the number of pending approvals. Spending money arrives with M4/M5.

---

### STORY-015 — On-demand task

As an **owner**,
I want **to ask the agent for a specific task now**,
so that **I don't wait for the night**.

**Size:** M · **Status:** ready

**Acceptance criteria**

_Happy path:_

```
AC1 — run a task now
  Given a company with a ready plan and a site draft
  When  the owner submits a task (e.g. "dodaj sekcję FAQ")
  Then  the agent runs it in the background, creates a new site version, logs it,
        and queues a publish approval if the site is published
```

_Sad path:_

```
AC2 — daily limit
  Given 3 successful on-demand tasks today (Europe/Warsaw)
  When  the owner submits another one
  Then  it is refused with a daily-limit message; failed runs do not count

AC3 — task text validation
  Given the on-demand task form
  When  the owner submits fewer than 5 or more than 500 characters
  Then  a validation error is shown

AC4 — provider fails
  Given the AI provider fails
  When  the on-demand task runs
  Then  the owner sees a failure message and no version is created
```

**Notes:** the 3/day cap is replaced by plan credits in M6 (STORY-031).

---

## 💬 Epic M3: Customer communication _(placeholders)_

- **STORY-016**: Owner connects a Gmail/Outlook inbox so that the agent can read customer emails.
- **STORY-017**: Owner uploads a price list and opening hours so that replies are accurate.
- **STORY-018**: The agent drafts replies to customer emails for one-click send (and auto-sends once the owner allows it).
- **STORY-019**: Complaints and unusual messages are escalated to the owner instead of answered.
- **STORY-020**: The agent drafts replies to Google Business reviews.

## 📣 Epic M4: Ads _(placeholders)_

- **STORY-021**: Owner connects Meta Ads with a monthly budget cap.
- **STORY-022**: The agent creates a campaign from the plan, pending owner approval.
- **STORY-023**: The agent pauses underperforming ads and logs why.
- **STORY-024**: Owner connects Google Ads (same flow as Meta).
- **STORY-025**: Ad spend and results appear in the morning report.

## 🧾 Epic M5: Invoicing & payments _(placeholders)_

- **STORY-026**: Owner connects Fakturownia/inFakt so that the agent can issue invoices.
- **STORY-027**: Invoices are sent to KSeF.
- **STORY-028**: Overdue invoices trigger polite payment reminders.
- **STORY-029**: Payments from Przelewy24/Stripe are matched to invoices.

## 💳 Epic M6: Plans, billing & data _(030–031 placeholders)_

- **STORY-030**: Owner subscribes to Start, Biznes or Pro (PLN, net prices).
- **STORY-031**: Plan limits are enforced (features, number of on-demand credits).

### STORY-032 — Export my data

As an **owner**,
I want **to download all my data**,
so that **I can take it elsewhere (GDPR data portability)**.

**Size:** S · **Status:** ready

**Acceptance criteria**

```
AC1 — download
  Given a signed-in owner
  When  they click "Pobierz moje dane" in settings
  Then  a JSON file downloads with their account, companies, ideas, plans, site versions and activity
```

_Sad path:_

```
AC2 — only own data
  Given owner A and owner B
  When  owner A downloads their export
  Then  it contains none of owner B's data
```

---

### STORY-033 — Delete my account

As an **owner**,
I want **to delete my account and all my data**,
so that **nothing about me stays in Firmos (GDPR right to erasure)**.

**Size:** M · **Status:** ready

**Acceptance criteria**

```
AC1 — delete everything
  Given a signed-in owner in settings
  When  they confirm deletion by typing their email
  Then  the account and all their companies, ideas, plans, sites, versions and activity are deleted,
        they are logged out on every device, and their public sites return 404
```

_Sad path:_

```
AC2 — wrong confirmation
  Given the delete form
  When  the owner types a different email
  Then  nothing is deleted and an error is shown

AC3 — queued work
  Given queued agent jobs for the owner's companies
  When  the account is deleted
  Then  those jobs finish without doing anything
```
