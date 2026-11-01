# Secure response headers & cookie flags — target state (Phoenix)

Recommend these defaults; a per-route relaxation must carry a comment
saying why. Tighten CSP to your actual sources — a CSP with
`unsafe-inline`/`unsafe-eval` in `script-src` (or `*`) is barely a CSP;
flag it.

## The header set

| Header | Value (baseline) | Why |
|---|---|---|
| `Content-Security-Policy` | `default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' data:; connect-src 'self'; object-src 'none'; base-uri 'self'; frame-ancestors 'none'; form-action 'self'` (nonces/hashes, not `unsafe-inline`) | XSS mitigation, anti-framing |
| `X-Content-Type-Options` | `nosniff` | stop MIME sniffing |
| `Strict-Transport-Security` | `max-age=63072000; includeSubDomains` | HTTPS only (via `force_ssl`) |
| `Referrer-Policy` | `strict-origin-when-cross-origin` | limit referrer leakage |
| `Permissions-Policy` | `camera=(), microphone=(), geolocation=()` (deny unused) | reduce feature surface |
| `Cache-Control` (authed responses) | `no-store` | don't cache per-user data |

Phoenix 1.8's bare `put_secure_browser_headers` sets `nosniff`,
`referrer-policy`, `x-permitted-cross-domain-policies: none`, and a
minimal CSP (`base-uri 'self'; frame-ancestors 'self'`). Passing your own
`content-security-policy` **replaces** that CSP — keep `frame-ancestors`
and `base-uri` in it.

## Router

```elixir
# lib/firmos_web/router.ex
@csp Enum.join(
       [
         "default-src 'self'",
         "script-src 'self'",
         "style-src 'self' 'unsafe-inline'",   # LiveView/topbar inline styles; drop if unused
         "img-src 'self' data: blob:",
         "font-src 'self'",
         "connect-src 'self'",                 # same-origin wss:// for /live
         "object-src 'none'",
         "base-uri 'self'",
         "form-action 'self'",
         "frame-ancestors 'none'"
       ],
       "; "
     )

pipeline :browser do
  # ...
  plug :protect_from_forgery
  plug :put_secure_browser_headers, %{
    "content-security-policy" => @csp,
    "permissions-policy" => "camera=(), microphone=(), geolocation=()"
  }
end
```

Inline scripts: AGENTS.md forbids them — move the generated theme script
from `root.html.heex` into `app.js`. If an inline script is unavoidable,
use a per-request nonce plug (`:crypto.strong_rand_bytes(16) |> Base.encode64()`
→ `assign(conn, :csp_nonce, n)` + build the CSP header with
`'nonce-#{n}'` + `<script nonce={@csp_nonce}>`), never `unsafe-inline`.

## HSTS / HTTPS

```elixir
# config/prod.exs (compile-time)
config :firmos, FirmosWeb.Endpoint,
  force_ssl: [hsts: true, rewrite_on: [:x_forwarded_proto]]
```

## Session cookie (endpoint)

```elixir
# lib/firmos_web/endpoint.ex
@session_options [
  store: :cookie,
  key: "_firmos_key",
  signing_salt: "…",
  encryption_salt: "…",          # cookie is readable without this
  same_site: "Lax",
  secure: true,                  # or Mix.env()-gated; force_ssl alone doesn't set it
  http_only: true,               # default, keep it
  max_age: 60 * 60 * 24 * 14
]
```

- `HttpOnly` — JS can't read it (limits XSS token theft).
- `Secure` — HTTPS only.
- `same_site: "Lax"` minimum; `"None"` requires `secure` **and** a written
  cross-site reason; `"Strict"` for the most sensitive.
- `secret_key_base` comes from `config/runtime.exs` (`SECRET_KEY_BASE`
  env); salts may live in code.
- The `"remember me"` cookie from `phx.gen.auth` (`put_resp_cookie` with
  `sign: true`) needs the same `same_site`/`secure`/`max_age` review.

## Websocket origin

```elixir
# config/runtime.exs (prod)
config :firmos, FirmosWeb.Endpoint,
  url: [host: host, port: 443, scheme: "https"],
  check_origin: ["https://#{host}"]     # never false in prod
```
