# Finding report format

Every reported issue uses this shape. No exploit path → label it
**Observation**, not Finding, and skip Severity.

---

### [SEVERITY] Short title (vuln class)

- **Severity:** Critical | High | Medium | Low — and the one assumption
  that makes it that (e.g. "assumes the route is unauthenticated, which it
  is — no auth middleware on this path").
- **Location:** `lib/firmos_web/live/foo_live.ex:42` (and the sink/source if split across
  files).
- **Class:** XSS / IDOR / SSRF / injection / authz / secret-exposure / …
- **Exploit:** concrete walkthrough. Who the attacker is, the exact
  request/input they send, what they get. A real payload, not "could be
  abused". If you can't write this, it's an Observation.
- **Fix:** the minimal change, with the corrected snippet. Reference the
  rule (`SKILL.md` rule N) and the secure default
  (`templates/…`) — don't invent a one-off if a standard fix exists.
- **Confidence:** High (traced) | Medium (likely, unverified path) |
  needs-confirmation (and what to check).

---

### Example

### [High] Invoice IDOR via `phx-value-id` (authz / IDOR)

- **Severity:** High — any authenticated user can read any other tenant's
  invoice; ownership is never checked.
- **Location:** `lib/firmos_web/live/invoice_live/index.ex:31`
  (`handle_event("show", ...)`), query at `lib/firmos/invoices.ex:18`.
- **Class:** Broken object-level authorization (IDOR).
- **Exploit:** Log in as a normal user, open `/invoices`, change a row
  button's `phx-value-id` to `9001` in devtools and click (or push the
  `"show"` event over the socket directly). The context calls
  `Repo.get!(Invoice, id)` with no scope, so invoice 9001 is rendered
  regardless of owner — cross-tenant financial data disclosure.
- **Fix:** pass the scope and filter by it:
  `Invoices.get_invoice!(socket.assigns.current_scope, id)` with
  `where: i.id == ^id and i.org_id == ^scope.org.id`; `Ecto.NoResultsError`
  → 404 (don't confirm existence). See `backend.md` §authz-idor,
  `phoenix.md` §liveview, SKILL.md rule 1.
- **Confidence:** High — traced source→sink, no intervening policy check.
