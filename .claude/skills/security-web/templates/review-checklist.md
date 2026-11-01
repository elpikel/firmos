# Web security review checklist (Phoenix / LiveView)

Run before sign-off. For each item: pass / finding (→ `templates/finding.md`)
/ N/A-with-reason. Skipping an item silently is not allowed.

## Attack surface mapped
- [ ] Every router scope/pipeline, controller action, LiveView `mount`/
      `handle_params`/`handle_event`, channel `handle_in`, upload, outbound
      `Req` call, Oban job fed by input, JS hook / `push_event`, and
      config reaching assets/HTML enumerated.

## AuthN / AuthZ (rules 1, 8)
- [ ] Every authenticated `live` route sits in a `live_session` with an
      auth `on_mount`; controllers behind the auth plug.
- [ ] Every id from params / `phx-value-*` / hidden input is authorized
      at the **object** level (scope in the query; context takes `%Scope{}`).
- [ ] Every `handle_event` re-authorizes; nothing relies on a button not
      being rendered.
- [ ] Role checks in `on_mount`/plug *and* context, not only in HEEx.
- [ ] Sessions renewed on login; logout disconnects live sockets; tokens
      expire (`max_age`), compared with `Plug.Crypto.secure_compare`.

## Input & output (rules 2, 4)
- [ ] External input parsed via changeset at the boundary (no raw params
      deeper than the web layer).
- [ ] `cast/3` lists exclude role/owner/admin fields; no `change(struct, params)`.
- [ ] No `raw/1` / `{:safe, _}` / hook `innerHTML` on request-derived data
      without a traced sanitizer; `href`s from users scheme-checked.
- [ ] SQL via Ecto DSL / `$n` params; dynamic fields allowlisted; no
      `:os.cmd`/`sh -c`/`Code.eval_*` with input.
- [ ] No `String.to_atom`/`keys: :atoms`/`binary_to_term` on input.

## Network & data egress (rules 3, 5)
- [ ] No secret in `assets/js`, compile-time config, rendered HTML,
      assigns that reach templates, `push_event`, or the repo.
- [ ] Rendered/encoded data projected (no full structs to the client).
- [ ] Outbound user-influenced URLs: scheme+host allowlist, private-IP
      block, `redirect: false` / re-validated (SSRF).
- [ ] CORS (if any) exact-match allowlist, `:api` pipeline only.

## Hardening (rules 6, 7, 9)
- [ ] `:protect_from_forgery` in every cookie-session pipeline; LiveView
      socket sends `_csrf_token`; `check_origin` not `false` in prod.
- [ ] `put_secure_browser_headers` with a real CSP; no inline scripts;
      `force_ssl` with HSTS in prod.
- [ ] Session cookie: `secure`, `same_site`, `max_age`, `encryption_salt`
      if sensitive; `secret_key_base` from `runtime.exs`.
- [ ] Rate limits (`Hammer`/`PlugAttack`) on auth/reset/OTP/expensive events;
      `Plug.Parsers` `length:`; pagination caps.
- [ ] Uploads: generated names, `Path.safe_relative`, type by content, size
      cap, not in `priv/static`.
- [ ] `redirect(external:)` never fed a param.
- [ ] `debug_errors: false` in prod; `filter_parameters` covers tokens/secrets;
      no `inspect(params)` logging.
- [ ] Dev-only routes (`/dev/dashboard`, mailbox) gated or admin-only.
- [ ] `mix sobelow`, `mix deps.audit`, `mix hex.audit` clean or triaged.

## Framework pass
- [ ] Ran the `references/phoenix.md` triage table against the diff.

## Output
- [ ] Findings reported in `templates/finding.md` format with severity +
      concrete exploit + minimal fix. Observations labeled as such.
