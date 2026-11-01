---
name: security-web
description: >-
  Web application security review for Elixir/Phoenix 1.8 + LiveView + Ecto +
  PostgreSQL apps, server and browser side: XSS and HEEx escaping (`raw/1`),
  CSRF (`protect_from_forgery`, LiveView socket token, `check_origin`),
  clickjacking and CSP (`put_secure_browser_headers`), secrets leaking into
  assets/rendered HTML, authn/authz and IDOR (LiveView `handle_event` /
  `handle_params` as public endpoints, `on_mount` + `current_scope`),
  injection (Ecto `fragment`/raw SQL, `System.cmd`/`:os.cmd`, `Code.eval_*`),
  atom exhaustion (`String.to_atom`), `binary_to_term`, SSRF with Req, mass
  assignment via `cast/3`, file upload and path traversal, session cookie
  config, rate limiting, and dependency risk (`mix hex.audit`,
  `mix_audit`, `sobelow`). Use when reviewing or writing Phoenix/LiveView
  code for vulnerabilities, triaging a security finding, or answering "is
  this exploitable / how do I fix it" questions. Ships secure-default config
  templates and a finding report format.
---

# Web Application Security Review (Phoenix / LiveView)

Treat every byte that crossed a network boundary as hostile until proven
otherwise, and prove it on the server. The browser is an untrusted rendering
surface you do not control. Phoenix adds convenience (LiveView events over a
websocket, `phx-value-*`, `on_mount`, changesets) that *hides* the trust
boundary — this skill's job is to make the reviewer see the boundary the
framework obscured.

## 🎯 Why: Design for Change

The goal of writing software is to be able to **change it safely**.
Secure-by-default config (CSP, cookie flags, parameterized queries,
scope-filtered queries, `cast/3` allowlists) means the next feature ships
without re-litigating the threat model. Every insecure default you accept
becomes a foothold the next change has to step around.

This skill is for *security review and secure implementation*. For general
Elixir correctness use `elixir-best-practices`; for schema-level integrity
(constraints, RLS, roles) use `postgres-dba`. This skill never assumes
another layer will catch it.

## How to use this skill (review workflow)

1. **Map the attack surface first.** Identify every trust boundary:
   router scopes and pipelines, controller actions, every LiveView
   `mount`/`handle_params`/`handle_event`, channels/sockets, `Plug.Upload`,
   outbound `Req` calls, Oban job args built from input, JS hooks and
   `push_event` payloads, config reaching assets or HTML. A vuln you didn't
   enumerate is a vuln you didn't find.
2. **Triage each input against the decision guide** below; open the matching
   `references/*.md` for the exploit, the vulnerable pattern, the fix, and
   the false-positive caveat.
3. **Apply `references/phoenix.md`** — the generic finding almost always has
   a Phoenix-specific trap or a Phoenix-specific fix.
4. **Report findings in the standard format** (`templates/finding.md`):
   severity, location (`file:line`), a concrete exploit walkthrough, and the
   minimal fix. No exploit path stated → it is an observation, not a
   finding; say which.
5. **Recommend the secure default**, not a bespoke patch. The `templates/`
   configs (CSP, security headers, session cookie, CORS, changeset
   boundary) are the target state; a one-off escape is a stopgap.

## Severity (how to rank a finding)

| Severity | Bar |
|---|---|
| **Critical** | Unauthenticated RCE, auth bypass, secret/PII mass disclosure, SQLi on a reachable path |
| **High** | Stored XSS, IDOR on sensitive data, SSRF to internal network, privilege escalation, CSRF on a state-changing action |
| **Medium** | Reflected XSS needing interaction, missing security headers with a real impact, weak session handling, verbose error leakage |
| **Low** | Defense-in-depth gaps with no direct exploit, missing hardening, informational |

Rank by *exploitability and blast radius on this codebase*, not by the
generic CVSS of the bug class. State the assumption that makes it that
severity.

## The hard rules (non-negotiable defaults)

1. **All trust decisions happen server-side, per request/event, per object.**
   Authentication (`on_mount`, `:require_authenticated_user` plug)
   establishes *who*; authorization re-checks *may this scope touch this
   specific resource* on every controller action **and every LiveView
   event**. A hidden button, a `:if` in HEEx, or a disabled input is UX,
   never a control. Assume every id in params or `phx-value-*` was tampered
   (IDOR). See `references/backend.md`, `references/phoenix.md`.

2. **Untrusted data is validated at the boundary and encoded at the sink.**
   Parse external input through an Ecto changeset (schema or
   `embedded_schema`) into a typed value; never pass raw params maps deeper.
   Encode for the *exact* context at output — HTML, attribute, JS, URL,
   SQL, shell, OS path differ. `raw/1`, `{:safe, _}`, or `innerHTML` in a
   hook with anything request-derived is a finding until a vetted sanitizer
   (e.g. `HtmlSanitizeEx`) is proven in the path. See
   `references/frontend.md`, `references/backend.md`.

3. **Secrets never cross to the client.** Anything compiled into
   `assets/js`, rendered into HTML, put in assigns that reach a template,
   sent via `push_event`, or committed to the repo is public. Secrets live
   in `config/runtime.exs` read from env, never compile-time config. Treat
   any secret that ever shipped as compromised: the fix is rotation, not
   deletion. See `references/frontend.md`, `references/phoenix.md`.

4. **Injection is closed by structure, not by filtering.** Ecto query DSL
   with `^pinned` values, `fragment("... ?", ^v)` placeholders, and
   `Ecto.Adapters.SQL.query(repo, sql, [params])` for SQL; `System.cmd/3`
   with an argument list (never `:os.cmd`, never `sh -c`) for processes;
   no input into `Code.eval_*`, `String.to_atom/1`, or
   `:erlang.binary_to_term/1`. Denylists and escaping-by-hand are findings.
   See `references/backend.md`.

5. **Outbound requests to user-influenced URLs are denied by default.**
   SSRF: allowlist host + scheme, resolve and reject private/link-local/
   metadata IPs, and disable or re-validate redirects (`Req` follows
   redirects by default). "We fetch the URL the user gave us" is High until
   proven constrained. See `references/backend.md`.

6. **Cookies and headers carry their security flags or it's a finding.**
   Session cookie (`Plug.Session` options in the endpoint): `http_only`,
   `secure`, `same_site: "Lax"` minimum, `encryption_salt` if contents are
   sensitive, sane `max_age`. Responses: CSP via `put_secure_browser_headers`
   (no `unsafe-inline`/`unsafe-eval` without justification), `nosniff`,
   `frame-ancestors`, HSTS via `force_ssl`. See
   `templates/security-headers.md`.

7. **State-changing requests are CSRF-protected.** Browser pipelines keep
   `:protect_from_forgery`; the LiveView socket receives `_csrf_token` in
   connect params and the endpoint keeps `check_origin` on in prod. Never
   move a cookie-authenticated POST into the `:api` pipeline to dodge the
   token. Token-in-header APIs are exempt only if they never accept the
   credential from a cookie.

8. **Framework "magic" endpoints are public endpoints.** Every
   `handle_event/3` and `handle_params/3` is an internet-facing handler —
   the client can send any event name with any payload, whether or not
   your template renders the button. It gets explicit authz, input
   validation, and rate limiting where expensive. Same for channel
   `handle_in/3` and controller actions. The caller is the attacker, not
   your form.

9. **Fail closed and quiet.** On auth/validation failure: deny, log
   server-side with context (with `filter_parameters` in effect), return a
   generic error. No stack traces (`debug_errors: false` in prod), no SQL,
   no internal hostnames, no "user not found vs wrong password" oracles.

## Decision guide

| Symptom / what you're reviewing | Where |
|---|---|
| Request data rendered in HEEx / a component / an email | `references/frontend.md` §XSS |
| `raw/1`, `Phoenix.HTML.raw`, `{:safe, ...}`, Markdown → HTML | `references/frontend.md` §XSS, `phoenix.md` §heex |
| `innerHTML`/`insertAdjacentHTML` in a JS hook, `push_event` data into DOM | `references/frontend.md` §hooks |
| `postMessage` handler without strict `origin` check | `references/frontend.md` §postMessage |
| Page can be framed; clickjacking on a sensitive action | `references/frontend.md` §clickjacking |
| Token/key/PII in `assets/js`, rendered HTML, assigns, or `push_event` | `references/frontend.md` §secrets, `phoenix.md` §config |
| `target="_blank"` without `rel`, `redirect(external:)`, `javascript:` URL | `references/frontend.md` §navigation |
| Login/session/token/cookie handling, `phx.gen.auth` changes | `references/backend.md` §auth-sessions, `phoenix.md` §auth |
| `handle_event`/`handle_params`/controller action using an id from params | `references/backend.md` §authz-idor, `phoenix.md` §liveview |
| `fragment`, `Ecto.Adapters.SQL.query`, dynamic `order_by`/field names | `references/backend.md` §injection |
| `System.cmd`, `:os.cmd`, `Port.open`, `Code.eval_*` | `references/backend.md` §injection |
| `String.to_atom`, `binary_to_term`, `:erlang.term_to_binary` round-trips | `references/backend.md` §deserialization |
| `Req`/`Finch` call to a URL/host the user supplied | `references/backend.md` §ssrf |
| `cast/3` with role/user_id/admin, `Repo.insert(struct(Mod, params))` | `references/backend.md` §mass-assignment |
| `Plug.Upload`, `allow_upload`, `send_file`, `Path.join` with input | `references/backend.md` §files, `phoenix.md` §files |
| Rate limiting / brute force / enumeration / resource exhaustion | `references/backend.md` §abuse |
| CORS config (`Corsica`/`cors_plug`), `*` with credentials | `references/backend.md` §cors, `templates/cors.md` |
| `mix.lock`, new deps, `hex.audit`, `sobelow` output | `references/backend.md` §supply-chain |
| Router pipelines, endpoint, `check_origin`, `Plug.Static`, runtime config | `references/phoenix.md` |

## Reference files

- `references/frontend.md` — browser-side: XSS in HEEx and JS hooks, CSP
  with LiveView, `push_event` payloads, `postMessage`, clickjacking,
  tabnabbing, open redirect, secrets in the asset bundle and rendered HTML,
  third-party scripts.
- `references/backend.md` — server-side: authn/session/tokens, authz/IDOR,
  injection (Ecto/SQL/command/eval), SSRF with Req, mass assignment via
  `cast/3`, deserialization and atoms, file handling/path traversal, CORS,
  rate limiting/abuse, error handling, supply chain.
- `references/phoenix.md` — Phoenix/LiveView traps: router pipelines,
  CSRF on the LiveView socket, `check_origin`, `live_session` + `on_mount`
  + `current_scope`, per-event authz, HEEx sinks, Ecto scoping, endpoint
  session config, `Plug.Static`, runtime vs compile-time secrets, logging,
  tooling (`sobelow`, `mix_audit`, `hex.audit`).

## Templates (recommend these as the target state)

| File | Use |
|---|---|
| `templates/finding.md` | The report format every finding must follow |
| `templates/security-headers.md` | CSP + headers + session cookie for Phoenix |
| `templates/cors.md` | Exact-match origin allowlist (`Corsica` / `cors_plug`) |
| `templates/input-validation.ex` | Boundary parse with `embedded_schema` + changeset |
| `templates/review-checklist.md` | The pass to run before sign-off |

## What this skill will not do

- Bless input *sanitization by denylist/regex* as an injection or XSS fix.
  Structure (parameterization, contextual encoding, vetted sanitizer) only.
- Bless client-side-only authorization or validation, or "security by
  obscurity" (unrendered buttons, unlinked routes, minified JS).
- Bless `raw/1` / `{:safe, _}` / hook `innerHTML` on request-derived data
  without a named sanitizer in the proven path.
- Bless `Access-Control-Allow-Origin: *` together with credentials, or
  reflecting `Origin` (or a regex match) without an exact allowlist.
- Bless custom crypto/token/hash/CSRF code where a vetted library exists
  (`Plug.CSRFProtection`, `Phoenix.Token`, `Bcrypt`/`Argon2`,
  `Plug.Crypto.secure_compare`).
- Downgrade a finding to "won't fix" inside this skill — it reports
  severity and the fix; the human owns acceptance.
