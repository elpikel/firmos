# CORS — correct allowlist pattern (Phoenix)

The only safe credentialed CORS is an **exact-match allowlist**. `*` with
credentials is browser-rejected; reflecting `Origin` unconditionally
reintroduces the same hole. Substring/regex matches are how
`evil-example.com` and `example.com.attacker.io` get in — use a list.

Browser-only Phoenix/LiveView apps usually need **no CORS at all**. Add it
only to the `:api` pipeline (or a dedicated one), never to `:browser`.

## Corsica (preferred)

```elixir
# lib/firmos_web/router.ex
pipeline :api do
  plug :accepts, ["json"]

  plug Corsica,
    origins: Application.compile_env(:firmos, :cors_origins, []),  # list of exact strings
    allow_credentials: true,
    allow_methods: ["GET", "POST", "PUT", "DELETE"],
    allow_headers: ["content-type", "authorization"],
    max_age: 600
end
```

```elixir
# config/config.exs (origins are not secrets; per-env overrides OK)
config :firmos, :cors_origins, ["https://app.example.com", "https://admin.example.com"]
```

Corsica answers preflight (`OPTIONS`) with the same allowlist and sets
`Vary: Origin` when the origin isn't `*`. If the plug sits in a router
pipeline, add `options "/*path", ...` routes or place Corsica in the
endpoint before the router so preflights reach it.

## cors_plug

```elixir
plug CORSPlug,
  origin: ["https://app.example.com"],   # list, NOT ~r/example\.com/
  credentials: true,
  methods: ["GET", "POST", "PUT", "DELETE"],
  headers: ["content-type", "authorization"]
```

If a regex or function is unavoidable, anchor it fully:
`~r/^https:\/\/(app|admin)\.example\.com$/`.

## Rules

- Public, credential-free, read-only API → `origins: "*"` is acceptable
  (and then **never** `allow_credentials: true`).
- Credentialed API → exact-match allowlist only, always `Vary: Origin`.
- `null` origin (sandboxed iframe, `file://`, some redirects) is **not**
  trusted — never allowlist the literal string `"null"`.
- Preflight must apply the *same* allowlist as the actual request; don't
  blanket-allow `OPTIONS`.
- CORS controls who can *read cross-origin responses in a browser*. It is
  **not** authn/authz and not CSRF defense — and it does not apply to the
  LiveView websocket; that's `check_origin`.
