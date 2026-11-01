# Backend / Server-Side — full reference

Each section: **threat**, a **vulnerable** pattern, the **fix**, **review
notes**, **false positives**. The server is the only place trust decisions
are real. Every controller action and every LiveView `handle_event` is
internet-facing regardless of which UI you think calls it.

---

## §auth-sessions — Authentication, sessions, tokens, cookies

**Threats:** credential stuffing/brute force, session fixation, token
theft/replay, weak password storage, unsigned/unexpiring tokens, missing
rotation, user-enumeration oracles.

```elixir
# ❌ fast hash, timing-leaky compare, no expiry, forever-valid token
:crypto.hash(:sha256, pw) == user.hashed_password
api_key == provided_key
Phoenix.Token.verify(Endpoint, "user", token, max_age: :infinity)
```
```elixir
# ✅
Bcrypt.verify_pass(pw, user.hashed_password)    # or Argon2; Bcrypt.no_user_verify() on miss
Plug.Crypto.secure_compare(api_key, provided_key)
Phoenix.Token.verify(Endpoint, "user auth", token, max_age: 86_400)
conn |> configure_session(renew: true) |> put_session(:user_token, token)
```

**Review checklist:**
- Password hash = `Bcrypt`/`Argon2`/`Pbkdf2` (comeonin family) with real
  cost. `:crypto.hash` / `:erlang.md5` for passwords → High.
- Tokens: `Phoenix.Token` or `phx.gen.auth` DB tokens (hashed at rest,
  expiring, revocable on password change). JWT (`Joken`): pin the signer/
  alg, short exp, server-only key.
- Session renewed on login/privilege change (`renew: true`) → no fixation.
  Logout deletes DB tokens and disconnects live sockets.
- Session cookie: signed (+ `encryption_salt` if contents matter),
  `secure`, `same_site`, `max_age`. See `phoenix.md` §config.
- Login/reset/registration give **identical** responses & timing for
  valid/invalid accounts. Rate-limited + backoff.
- Reset/magic-link/confirm tokens: single-use, expiring, high-entropy
  (`:crypto.strong_rand_bytes/1`), compared in constant time or looked up
  by hash.

**False positives:** generated `phx.gen.auth` code with defaults intact;
the "hash" is for a non-secret (cache key, ETag).

---

## §authz-idor — Authorization & Insecure Direct Object Reference

**Threat:** the request (path param, form field, `phx-value-id`) supplies
an id and the server returns or mutates it **without checking the scope
owns/may access it**. The single most common High/Critical web bug.
Authentication ≠ authorization.

```elixir
# ❌ any logged-in user reads any invoice by changing the id
def show(conn, %{"id" => id}), do: render(conn, :show, invoice: Repo.get!(Invoice, id))
```
```elixir
# ✅ ownership is part of the query; context takes the scope
def get_invoice!(%Scope{} = scope, id) do
  from(i in Invoice, as: :invoice)
  |> where([invoice: i], i.id == ^id and i.org_id == ^scope.org.id)
  |> Repo.one!()                          # Ecto.NoResultsError → 404, existence not confirmed
end
```

**Review notes:** check **every** action/event that takes an id-like input
— reads *and* writes, nested resources, `handle_params` on patch, batch
"select all" events, downloads, exports, Oban jobs enqueued with a
client-supplied id. Ownership must be in the WHERE clause or an explicit
policy check *before* the effect. Role checks: enforced in `on_mount`/plug
and in the context, not only by hiding UI. Bulk events authorize each
element. Preloads can leak too (`preload: [:org, :users]` rendered).
UUIDs are defense-in-depth, never the control.

**False positives:** the resource is genuinely public; ownership enforced
by a policy you traced for this action/event; Postgres RLS enforces it
(verify the connection sets the tenant per checkout).

---

## §injection — SQL / Ecto raw / command / eval

**Threat:** input crosses into an interpreter (SQL, shell, Elixir
evaluator, EEx) as code. SQLi on a reachable path is Critical; command
injection and eval are Critical (RCE).

```elixir
# ❌ SQL string-built
Repo.query("select * from users where email = '#{email}'")
Ecto.Adapters.SQL.query!(Repo, "... order by #{params["sort"]}")
# ❌ command — shell parses the string
:os.cmd(~c"convert #{name} out.png")
System.cmd("sh", ["-c", "convert #{name} out.png"])
# ❌ eval / template compile
Code.eval_string(params["expr"]); EEx.eval_string(user_template, assigns)
```
```elixir
# ✅ parameterize / structure
Repo.query("select * from users where email = $1", [email])
from(u in User, as: :user) |> where([user: u], u.email == ^email)
where(q, [user: u], fragment("lower(?)", u.email) == ^String.downcase(email))
sort = Map.fetch!(%{"name" => :name, "date" => :inserted_at}, params["sort"])
System.cmd("convert", ["--", name, "out.png"])   # arg list, no shell
# templates: user input is assigns passed to a compiled template, never the source
```

**Review notes:** the fix is *structural*, never escaping. Ecto's DSL
with `^pinned` values is parameterized; `fragment` forbids interpolating
its first argument, so the risk is `Repo.query`/`SQL.query` strings and
dynamic identifiers (`field(u, ^col)`, `order_by`) built from
`String.to_atom(param)` — allowlist them. `System.cmd/3` never invokes a
shell; still guard against option injection (`--`). `Port.open({:spawn, cmd})`
uses a shell — treat like `:os.cmd`.

**False positives:** value is a changeset-validated enum/integer bound as
a parameter; interpolated pieces are compile-time constants.

---

## §ssrf — Server-Side Request Forgery

**Threat:** the server makes a request to a URL/host the user influenced
(webhook, avatar fetch, link preview, import-from-URL, OIDC discovery).
Attacker pivots to cloud metadata (`169.254.169.254`), internal services,
port scans. High–Critical.

```elixir
# ❌ fetches whatever the user asked for, follows redirects by default
Req.get!(params["image_url"])
```
```elixir
# ✅ allowlist + resolve + block private ranges + no redirect + caps
@allowed_hosts MapSet.new(["images.example.com"])

def fetch_public(raw) do
  with %URI{scheme: "https", host: host} = uri when is_binary(host) <- URI.parse(raw),
       true <- MapSet.member?(@allowed_hosts, host),
       {:ok, ip} <- :inet.getaddr(String.to_charlist(host), :inet),
       false <- private_ip?(ip) do
    Req.get(uri, redirect: false, receive_timeout: 5_000, retry: false)
  else
    _ -> {:error, :forbidden_url}
  end
end
```

**Review notes:** denylisting IP literals is insufficient — DNS rebinding,
IPv6 (`::1`, `::ffff:127.0.0.1`), decimal IPs, `0.0.0.0`, redirects bypass
it. Real fix: scheme+host allowlist, resolve and reject private/loopback/
link-local/ULA, `redirect: false` (or re-validate each `Location`),
timeouts, response size cap (stream with `into:` and halt), and network-
level egress filtering (strongest — recommend it). Same rules for Oban
jobs that fetch URLs later. Cloud metadata reachable → Critical.

**False positives:** fixed allowlist of your own/partner hosts with
redirects disabled; egress firewalled and documented.

---

## §mass-assignment — over-posting via `cast/3`

**Threat:** params bound into a schema let the attacker set fields they
shouldn't (`role`, `admin`, `user_id`, `org_id`, `balance`,
`confirmed_at`).

```elixir
# ❌ user controls privilege/ownership columns
user |> cast(params, [:name, :email, :role, :org_id]) |> Repo.update()
Repo.insert(struct(Invoice, atomize(params)))
```
```elixir
# ✅ cast is the allowlist; privileged fields come from the scope/server
%Invoice{org_id: scope.org.id, created_by_id: scope.user.id}
|> cast(params, [:number, :amount, :due_on])
|> validate_required([:number, :amount])
```

**Review notes:** `cast/3`'s field list *is* the mass-assignment control —
one changeset per use case (`registration_changeset`,
`admin_changeset`), not one shared changeset with everything castable.
Watch `cast_assoc`/`cast_embed` (nested writes to children you don't
own), `Ecto.Changeset.change(struct, params)` (no allowlist), and
`Repo.insert_all`/`update_all` fed params.

**False positives:** the changeset used on this path casts only safe
fields; privileged fields cast only in an admin changeset behind an admin
check you traced.

---

## §deserialization — untrusted bytes → terms

**Threat:** `:erlang.binary_to_term/1` on client bytes can allocate atoms
(DoS) and build funs (code exec when invoked); `String.to_atom`/
`Jason.decode(keys: :atoms)` exhaust the atom table and crash the node;
`Code.eval_*` on "config" is RCE.

**Fix:** JSON (`Jason.decode/1` with string keys) + changeset validation
for data; `Plug.Crypto.non_executable_binary_to_term(bin, [:safe])` if
ETF is unavoidable; `Phoenix.Token`/`Plug.Crypto.sign` for terms that
round-trip through the client; `String.to_existing_atom/1` behind an
allowlist, or an explicit string→atom map.

**False positives:** input is server-internal (your own cache/DB bytes
never client-writable); atoms come from a fixed allowlist.

---

## §files — upload, download, path traversal

**Threat:** `../` in a filename reads/writes outside the intended dir;
uploaded content served back and executed (stored XSS via SVG/HTML);
client `content_type` trusted; zip-slip; decompression bombs.

```elixir
# ❌ path traversal, client filename trusted
send_file(conn, 200, Path.join(@upload_dir, params["name"]))
File.cp!(upload.path, Path.join(@upload_dir, upload.filename))
```
```elixir
# ✅ generate the name; confine; sniff type
dest = Path.join(@upload_dir, Ecto.UUID.generate())
File.cp!(upload.path, dest)
# for user-chosen relative paths:
{:ok, rel} = Path.safe_relative(params["name"], @upload_dir)
```

**Review notes:** never use `%Plug.Upload{filename}` or LiveView
`entry.client_name` in a stored path. Validate type by magic bytes, not
`content_type`/`client_type`. Enforce size before reading
(`Plug.Parsers` `length:`, `allow_upload max_file_size:`). Store outside
`priv/static`; serve with `content-disposition: attachment` + nosniff or
from a separate origin. `:zip.extract` — check entry paths and total size.

**False positives:** path segment is a server-generated id; uploads
confined to a non-served dir with size limits configured.

---

## §cors — Cross-Origin Resource Sharing

**Threat:** `*` *with credentials*, or reflecting any `Origin` with
`Allow-Credentials: true`, lets any site make authenticated cross-origin
calls and read responses.

```elixir
# ❌ reflects any origin + credentials; regex suffix matches evil-example.com
plug Corsica, origins: "*", allow_credentials: true
plug CORSPlug, origin: ~r/example\.com/
```
```elixir
# ✅ exact allowlist
plug Corsica, origins: ["https://app.example.com"], allow_credentials: true
```

**Review notes:** `*` only for public, credential-free APIs. Regex
origins must be fully anchored (`~r/^https:\/\/app\.example\.com$/`) —
prefer a list. See `templates/cors.md`.

**False positives:** API is public and stateless; allowlist is exact-match.

---

## §abuse — rate limiting, brute force, resource exhaustion

**Threat:** no throttling on login, reset, magic link, OTP, search, or
expensive LiveView events → credential stuffing, enumeration, cost/DoS.
ReDoS from user regex (`Regex.compile(param)`); unbounded body; unbounded
`limit` params; event floods over the socket; atom exhaustion.

**Fix:** `Hammer` or `PlugAttack` per-IP **and** per-account on auth
endpoints (and inside hot `handle_event`s); `Plug.Parsers` `length:`;
cap pagination (`min(limit, 100)`); `Repo` `timeout:`; `phx-debounce`/
`phx-throttle` are UX only — throttle server-side too; Oban `unique:` for
idempotency on payment-class jobs.

**False positives:** an upstream gateway/WAF enforces limits (verify it
covers this route and the `/live` websocket).

---

## §error-handling — leakage & fail-open

**Threat:** stack traces (`debug_errors: true`), SQL, paths, hostnames in
responses; `rescue _ -> :ok` that swallows an auth error and continues;
distinct errors for "no such user" vs "bad password"; changeset errors
that echo internal field names on admin-only fields.

**Fix:** generic `ErrorHTML`/`ErrorJSON`; structured server log with
`filter_parameters`; let it crash in auth paths (fail closed) rather than
rescue-and-continue; uniform auth responses.

**False positives:** verbose errors gated to dev config you traced.

---

## §supply-chain — dependencies

**Threat:** compromised/typosquatted hex or npm package, unpinned
versions, abandoned deps with CVEs, CDN scripts without SRI, git deps on a
moving branch.

**Fix:** committed `mix.lock` (and `assets` lockfile if npm is used);
`mix deps.audit`, `mix hex.audit`, `mix sobelow` in CI; review new deps
(recent, low-download, or handling crypto/auth/parsing); pin git deps to
a `ref:`; SRI for any CDN asset (prefer vendoring into `app.js`).

**False positives:** dep is well-known, locked, and audit-clean.

---

## Quick triage table

| Pattern | Default severity |
|---|---|
| SQLi / `:os.cmd` / `Code.eval_*` on a reachable path | Critical |
| Auth bypass / missing `on_mount` on authed LiveView | Critical–High |
| IDOR on sensitive data (read or write, controller or event) | High |
| SSRF reaching internal/metadata | High–Critical |
| `cast` of a privilege/ownership field | High |
| Weak password hashing | High |
| CORS reflect-origin + credentials | High |
| Path traversal in file read/write | High |
| `String.to_atom`/`binary_to_term` on input | Medium–High |
| No rate limit on auth/OTP | Medium |
| Session cookie missing `secure`/`same_site` | Medium |
| Error/stack leakage | Low–Medium |
