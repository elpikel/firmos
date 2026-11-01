---
description: Take a GitHub issue from open to PR — triage, route to quick-fix or plan → build-loop, open a PR that closes it. Works interactively and in CI.
argument-hint: <issue number or URL>
model: claude-opus-5-5
---

# issue

The default entry point for work that starts as a GitHub issue. You
**route**; the phase commands and agents do the work.

## Mode

- **CI mode** when `GITHUB_ACTIONS=true` (check `echo $GITHUB_ACTIONS`).
  Nobody is watching: never use `AskUserQuestion`. Every question becomes a
  comment on the issue (`gh issue comment`), then stop.
- **Interactive mode** otherwise: ask with `AskUserQuestion`, batched.

## Preflight

1. Resolve `$ARGUMENTS` to an issue number. Empty → ask (interactive) or
   stop (CI).
2. `gh issue view <n> --comments`. Read title, body, labels, and every
   comment — answers to earlier questions live there.
3. Refuse if the issue is closed, or an open PR already references it
   (`gh pr list --search "<n> in:body" --state open`) — report the PR
   instead of duplicating it.
4. Working tree must be clean. Start from an up-to-date `main`:
   `git switch main && git pull --ff-only`.
5. Read `CLAUDE.md` and, if present, `docs/PROJECT.md`, `docs/SPEC.md`,
   `docs/MEMORY.md`.

## Triage

Classify the issue into exactly one route:

| Route | When |
|---|---|
| **clarify** | Acceptance is unclear, or it needs a product/architecture decision nobody has made (new context, new external service, schema shape with real trade-offs). |
| **quick-fix** | One spot, single concern, ~20 lines, no new behavior to specify. Typo, wrong condition, copy change, small bug with an obvious cause. |
| **feature** | Everything else: new behavior, multiple files, migrations, new routes/LiveViews. |

When in doubt between quick-fix and feature, pick **feature**.

### clarify

Write the smallest set of questions that unblocks the work (≤5), each with
your recommended answer so a reply can be "yes". CI: post them as one issue
comment ending with `Reply here and mention @claude to continue.`, then stop.
Interactive: ask, then re-triage with the answers.

### quick-fix

1. Branch `fix/<n>-<slug>` from `main`.
2. Run `/quick-fix` with the issue's description. Its "ask before
   committing" step is pre-authorized by this command.
3. Commit per the `github` skill with `Closes #<n>` in the footer.
4. Go to **Ship**.

### feature

1. Branch `feat/<n>-<slug>` from `main`.
2. **Plan, scoped to the issue.** Treat the issue (plus answered comments)
   as the spec for this slice: run `/plan` against it — it produces
   `docs/STORIES.md`, `docs/PLAN.md` entries for this issue only, and
   pending specs in `test/features/`. If `docs/SPEC.md` is missing, don't
   bounce to `/design`; the issue *is* the spec. In CI, `/plan`'s
   confirmation questions are skipped — record your assumptions in
   `docs/MEMORY.md` and in the PR body instead.
3. Commit the plan + pending specs (`docs: plan #<n>`).
4. Run `/build-loop docs/PLAN.md` — builder builds, reviewer gates, one
   commit per task. Only this issue's unchecked tasks.
5. If the loop stops on a task it can't get past review, push what passed,
   open the PR as **draft**, and say exactly what's blocked.
6. Go to **Ship**.

## Ship

1. `mix precommit` must be clean on the branch.
2. `git push -u origin HEAD`.
3. Run `/git-pr` (base `main`), body ends with `Closes #<n>`. In CI the
   draft-confirmation step is skipped; open it ready for review unless step
   5 above made it a draft.
4. Comment on the issue with the PR link and a one-line summary.

## Rules

- One issue → one branch → one PR. Don't fold in other issues.
- Never push to `main`. Never force-push.
- Never invent acceptance criteria — missing ones are a **clarify**.
- In CI, never wait for input; question → comment → stop.

## Hand off

Route taken, branch, commits, PR URL (or the clarifying comment URL).
