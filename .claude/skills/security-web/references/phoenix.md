# Phoenix / LiveView — framework traps and fixes

Phoenix ships good defaults (CSRF plug, HEEx escaping, signed session
cookie, `check_origin`). Most findings are a default that was removed,
bypassed, or never extended to a LiveView event. Check each section against
`lib/firmos_web/router.ex`, `endpoint.ex`, and `config/*.exs`.

---

## §router — pipelines

```elixir
pipeline :browser do
  plug :accepts, ["html"]
  plug :fetch_session
  plug :fetch_live_flash
  plug :put_root_layout, html: {FirmosWeb.Layouts, :root}
  plug :protect_from_forgery          # never remove; never skip per-route
  plug :put_secure_browser_headers, %{"content-security-policy" => @csp}
  plug :fetch_current_scope_for_user  # phx.gen.auth
end
```

- `:protect_from_forgery` missing from a pipeline that reads the session
  cookie → CSRF on every mutation there (High).
- A cookie-session route moved to `:api` (no CSRF plug) "because the form
  posts JSON" → CSRF. `:api` routes must authenticate by header token only.
- `put_secure_browser_headers` with no map sets Phoenix's baseline only;
  pass a real CSP (see `templates/security-headers.md`).
- Auth plugs (`:require_authenticated_user`) belong in the pipeline or a
  scope, and routes must not be declared *outside* that scope by accident.
  Read the router top to bottom — scope order and `pipe_through` matter.
- `live_dashboard`, `/dev/mailbox`, Oban Web, admin tools: inside
  `if Application.compile_env(:firmos, :dev_routes)` or behind an admin
  auth pipeline. Exposed in prod → High–Critical.

## §socket — LiveView socket, CSRF, origin

- `assets/js/app.js` passes `params: {_csrf_token: csrfToken}`; LiveView
  only hands the session to `mount` when that token validates. Removing it
  or building a socket without `connect_info: [session: @session_options]`
  breaks session-auth on the socket.
- `check_origin` is `true` by default (host from endpoint `url:`). Prod
  config with `check_origin: false` → cross-site websocket hijacking: any
  site can open an authenticated LiveView/channel socket (High). If
  multiple hosts are needed, list them: `check_origin: ["https://app.example.com"]`.
  `false` in `dev.exs` is fine.
- Custom `Phoenix.Socket`/channels: `connect/3` must verify a
  `Phoenix.Token` (with `max_age`), not trust a `user_id` param.

## §auth — `live_session`, `on_mount`, `current_scope`

```elixir
live_session :require_authenticated_user,
  on_mount: [{FirmosWeb.UserAuth, :require_authenticated}] do
  live "/invoices/:id", InvoiceLive.Show, :show
end
```

- The `:require_authenticated_user` plug protects only the initial HTTP
  render. `on_mount` runs on **both** the dead render and the websocket
  connect; a LiveView without it can be mounted over the socket
  unauthenticated. Every authenticated `live` route must be inside a
  `live_session` with an auth `on_mount`.
- `live_session` boundaries matter: `push_navigate` across sessions does a
  full remount; within a session it doesn't re-run plugs, only `on_mount`.
  Put role checks in `on_mount` (e.g. `:require_admin`), not just plugs.
- Phoenix 1.8 scope pattern: context functions take `%Scope{}` as the first
  argument and filter by it (`Invoices.get_invoice!(scope, id)`). A context
  function that takes a bare id is the IDOR smell — pass
  `socket.assigns.current_scope` everywhere.
- Session renewal: `UserAuth.log_in_user` renews the session
  (`configure_session(renew: true)`) and clears CSRF state; custom login
  code must do the same (fixation). Logout must disconnect live sockets
  (`FirmosWeb.Endpoint.broadcast(live_socket_id, "disconnect", %{})`).

## §liveview — every event is an endpoint

```elixir
# ❌ trusts the id the button carried; button only rendered for owners
def handle_event("delete", %{"id" => id}, socket) do
  Invoices.delete_invoice!(Repo.get!(Invoice, id))
  {:noreply, stream_delete(socket, :invoices, ...)}
end
```
```elixir
# ✅ re-authorize per event through the scope
def handle_event("delete", %{"id" => id}, socket) do
  scope = socket.assigns.current_scope
  invoice = Invoices.get_invoice!(scope, id)        # scoped query; raises → 404
  {:ok, _} = Invoices.delete_invoice(scope, invoice)
  {:noreply, stream_delete(socket, :invoices, invoice)}
end
```

- The client can push **any** event name with **any** params (`liveSocket`
  in devtools). `:if={@admin?}` on the button is not a control.
- `phx-value-*`, hidden inputs, `JS.push(value: ...)`, and form params are
  attacker-controlled. Prefer ids already held server-side (e.g. the record
  loaded in `mount`, kept in assigns) over ids sent back by the client.
- `handle_params/3` receives URL params on every `push_patch` — re-check
  ownership when the id changes, not only in `mount`.
- Assigns live on the server, but anything rendered goes to the client
  (and to the static render HTML). Don't render full structs into
  `data-*`, JSON, or `push_event`; project fields.
- Uploads: `allow_upload` with `accept:`, `max_entries:`, `max_file_size:`;
  `consume_uploaded_entries` writes to a generated path (see §files).
- `handle_info` is not client-reachable, but PubSub topics are: subscribe
  only to topics derived from the scope (`"org:#{scope.org.id}"`), never
  from a param.

## §heex — escaping and its escape hatches

- `{@value}` and attribute interpolation are HTML-escaped. Safe by default.
- Sinks: `raw/1` / `Phoenix.HTML.raw/1`, returning `{:safe, iodata}`,
  `Phoenix.HTML.Safe` impls that skip escaping, Markdown (`Earmark`/`MDEx`)
  output passed to `raw`. Needs `HtmlSanitizeEx` (or MDEx's sanitize
  option) in the proven path.
- `href={@url}`: HEEx escapes but does **not** block `javascript:` URLs —
  validate scheme (see `frontend.md` §navigation).
- `<script>` with interpolated data, `phx-no-curly-interpolation` blocks
  with `<%= %>`: avoid; pass data via `data-*` attributes + `JSON.parse`
  in a hook, or `push_event`.

## §ecto — scoping, casting, raw SQL

- `Repo.get!(Invoice, id)` / `Repo.get_by` with an id from params and no
  scope filter → IDOR. Put ownership in the query:
  `from(i in Invoice, as: :invoice, where: i.id == ^id and i.org_id == ^scope.org.id)`.
- `cast(params, [:name, :role, :user_id, :admin])` → mass assignment.
  Privilege/ownership fields are set with `put_change`/`put_assoc` or on
  the struct from the scope (`%Invoice{org_id: scope.org.id}`).
- `fragment("lower(#{col})")` does not compile (Ecto requires a literal)
  but `Ecto.Adapters.SQL.query(Repo, "... #{x}")` and `Repo.query` with
  interpolation do → SQLi. Use `$1` placeholders + params list.
- Dynamic sort/filter: map strings to atoms through an allowlist
  (`%{"name" => :name, "inserted_at" => :inserted_at}`), then
  `order_by([invoice: i], [{^dir, field(i, ^col)}])`.

## §runtime — atoms, eval, processes, deserialization

- `String.to_atom(param)` → atoms are never GC'd; ~1M distinct values
  crash the VM (DoS). Use explicit maps or `String.to_existing_atom/1`
  (still guard with an allowlist — it raises on unknown input).
  Same for `Jason.decode(..., keys: :atoms)` on untrusted JSON.
- `:erlang.binary_to_term(bytes)` on untrusted input can create atoms and
  funs → use `Plug.Crypto.non_executable_binary_to_term(bytes, [:safe])`,
  or better, JSON. Signed tokens (`Phoenix.Token`) are the right way to
  round-trip terms through a client.
- `Code.eval_string`, `Code.eval_quoted`, `EEx.eval_string` with input →
  RCE (Critical).
- `System.cmd("convert", [path, "out.png"])` takes an arg list, no shell —
  safe from injection (still validate the arg isn't `-`-prefixed option
  injection). `:os.cmd(~c"convert #{path}")` and `System.cmd("sh", ["-c", ...])`
  → command injection (Critical).

## §files — paths, uploads, static

- `Path.join(@upload_dir, params["name"])` → traversal. Generate names
  (`Ecto.UUID.generate()`), or `Path.safe_relative(name, base)` and reject
  `:error`. Never trust `%Plug.Upload{filename:, content_type:}` — both
  come from the client.
- `send_download/3` / `send_file/3` with a user path: resolve and confine;
  set `disposition: :attachment` for user content; serve user HTML/SVG
  from another origin or as attachment.
- `Plug.Static` serves only `FirmosWeb.static_paths/0` under
  `priv/static`. Writing uploads into `priv/static/uploads` (and adding it
  to `static_paths`) makes uploaded HTML/SVG same-origin stored XSS.

## §redirects

- `redirect(conn, to: path)` / `push_navigate(to:)` reject non-local paths
  (raise on `//evil.com`). `redirect(conn, external: params["return_to"])`
  is the open-redirect sink — allowlist hosts, or keep `return_to` as a
  local path in the session (phx.gen.auth's `:user_return_to` pattern).

## §config — endpoint, secrets, logging

- Session (`@session_options` in `endpoint.ex`): the cookie is **signed,
  not encrypted** by default — contents are readable. Add
  `encryption_salt:` if anything sensitive is stored; set `secure: true`
  in prod (or rely on `force_ssl` + `__Host-` key), keep `same_site: "Lax"`,
  set `max_age`. Salts are not secrets; `secret_key_base` is.
- Secrets: `config/runtime.exs` with `System.fetch_env!/1`. A
  `System.get_env` in `config.exs`/`prod.exs`, or `Application.compile_env`
  of a secret, bakes it into the release `.beam`/`sys.config` → leak via
  artifacts. Committed `secret_key_base` in `dev.exs`/`test.exs` is fine;
  in `prod.exs` it's Critical (rotate).
- `force_ssl: [hsts: true, rewrite_on: [:x_forwarded_proto]]` in prod.
- `debug_errors: false` and `code_reloader: false` in prod; error views
  (`ErrorHTML`/`ErrorJSON`) render generic messages only.
- `config :phoenix, :filter_parameters, ["password", "token", "secret", "api_key"]`
  — default is only `["password"]`. Also don't `Logger.info(inspect(params))`
  or log full changesets/structs with PII. Use `@derive {Inspect, except: [...]}`
  / `redact: true` on sensitive schema fields.
- Passwords: `Bcrypt` (`bcrypt_elixir`) or `Argon2` (`argon2_elixir`) via
  `phx.gen.auth`; `Bcrypt.no_user_verify/0` on unknown users to equalize
  timing. Token compare: `Plug.Crypto.secure_compare/2`, never `==`.
- `Phoenix.Token.verify(..., max_age: ...)` — omitting `max_age` means a
  leaked token is valid forever (1.8 defaults to 1 day; be explicit).
- Rate limiting: none built in. `Hammer` (plug or in `handle_event`) or
  `PlugAttack` on login, reset, magic-link, OTP, expensive LiveView events.

## §tooling

- `mix sobelow --config` — Phoenix-aware static analysis (XSS via `raw`,
  SQLi, traversal, missing CSRF/headers, config). Triage, don't blindly
  ignore with `.sobelow-skips`.
- `mix deps.audit` (`mix_audit`) — known CVEs in `mix.lock`.
- `mix hex.audit` — retired packages.
- Run them in CI next to `mix precommit`.

## Quick triage table

| Seen in diff | Default severity |
|---|---|
| `handle_event` mutating by client-sent id without scope | High |
| `live` route outside an auth `live_session` / no `on_mount` | High |
| `check_origin: false` in prod | High |
| `:protect_from_forgery` removed / cookie route in `:api` | High |
| `raw/1` on user content | High (stored) / Medium (reflected) |
| `Code.eval_*` / `:os.cmd` / `sh -c` with input | Critical |
| `String.to_atom` / `binary_to_term` on input | Medium–High (DoS / RCE) |
| `cast` includes role/owner/admin field | High |
| Secret in compile-time config / assets / `prod.exs` | High (rotate) |
| `redirect(external:)` with param | Medium |
| `filter_parameters` missing token/secret | Low–Medium |
