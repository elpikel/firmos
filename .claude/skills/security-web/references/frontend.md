# Frontend / Browser-Side — full reference

Each section: **threat**, a **vulnerable** pattern, the **fix**, **review
notes**, and **false positives** (when it is not a finding). HEEx renders
on the server, but the result runs in a browser you don't control, and
LiveView JS hooks are ordinary DOM code. Every output sink is a potential
interpreter.

---

## §XSS — Cross-Site Scripting

**Threat:** untrusted data reaches an HTML/JS/URL/CSS interpreter and runs
as code in the victim's origin: session riding over the LiveView socket,
account takeover, data exfiltration. Stored XSS is High–Critical;
reflected/DOM XSS is Medium–High.

### The sinks to grep for

Server: `raw(`, `Phoenix.HTML.raw`, `{:safe, `, custom `Phoenix.HTML.Safe`
impls, `Earmark.as_html`/`MDEx.to_html` output passed to `raw`,
`Phoenix.HTML.javascript_escape` misuse, interpolation inside `<script>`
or `<style>`, `href={@user_url}`, `style={@user_value}`, Swoosh
`html_body` built by string concat.
Client (`assets/js`, colocated hooks): `innerHTML`, `outerHTML`,
`insertAdjacentHTML`, `document.write`, `eval`, `new Function`,
`setTimeout(string)`, `el.setAttribute("href", data.url)`.

```heex
<%!-- ❌ comment body is attacker-controlled --%>
<div>{raw(@comment.body)}</div>
<div>{raw(Earmark.as_html!(@comment.body))}</div>
```

**Fix — pick the weakest tool that works:**

1. **Don't render HTML.** `{@comment.body}` — HEEx escapes it. This
   closes the bug and is the default expectation.
2. **If HTML is genuinely required**, sanitize with an allowlist
   sanitizer in the proven path — store raw, sanitize on output so the
   policy can change:

```elixir
# HtmlSanitizeEx.basic_html/1 or markdown_html/1; MDEx: sanitize: MDEx.Document.default_sanitize_options()
def render_markdown(md), do: md |> Earmark.as_html!() |> HtmlSanitizeEx.markdown_html() |> raw()
```

3. **Contextual encoding for non-HTML sinks.** Safe in HTML text ≠ safe in
   an attribute, `<script>`, URL, or CSS. Don't interpolate into
   `<script>` (also forbidden by AGENTS.md). Pass data through
   `data-*` attributes (HEEx escapes them) and `JSON.parse` in a hook, or
   via `push_event`.

**Review notes:** trace the data, don't pattern-match the line. A regex
that strips `<script>` is still a finding (`onerror=`, `javascript:`,
SVG, `<iframe srcdoc>` bypass it). Markdown renderers emit raw HTML by
default. CSP is *mitigation*, not a fix; report the XSS even with a CSP.

**False positives:** the `raw` argument is a developer-authored constant
or output of a sanitizer you traced; the value is HEEx-interpolated
without bypass.

---

## §hooks — LiveView JS hooks, colocated hooks, `push_event`

**Threat:** server-escaped data becomes unescaped again when a hook
writes it with `innerHTML`. `push_event` payloads and `data-*` values
are request-derived data on the client; the hook is the sink.

```js
// ❌ inside a colocated hook (<script :type={Phoenix.LiveView.ColocatedHook} name=".Preview">)
mounted() {
  this.handleEvent("preview", ({html}) => { this.el.innerHTML = html })   // XSS
  this.el.innerHTML = this.el.dataset.label                                // re-sinks escaped data
}
```
```js
// ✅ text, not markup; validate URLs; treat payloads as untrusted
mounted() {
  this.handleEvent("preview", ({text}) => { this.el.textContent = text })
}
```

**Review notes:** `phx-update="ignore"` hooks own their DOM — LiveView no
longer escapes for you there. `push_event` sends to the client: never
include more than the hook needs (no tokens, no full structs).
`pushEvent` from a hook to the server is just another `handle_event` —
see `phoenix.md` §liveview. `JS.dispatch`/`window.addEventListener("phx:...")`
listeners receive data from the page; validate shape.

**False positives:** the hook uses `textContent`/`setAttribute` on
non-URL attributes; HTML in the payload is sanitized server-side first.

---

## §URL / navigation sinks

**Threat:** `javascript:`/`data:` URLs in `href`/`src`/`window.open`
execute script (HEEx escapes quotes, not schemes); `target="_blank"`
without `rel` allows reverse tabnabbing; user-controlled redirect targets
enable open redirect → phishing / OAuth code theft.

```heex
<%!-- ❌ javascript: executes; tabnabbing --%>
<a href={@user.website} target="_blank">site</a>
```
```elixir
# ❌ open redirect
redirect(conn, external: params["return_to"])
```
```elixir
# ✅ scheme allowlist; local-only redirects
def safe_url(url) do
  case URI.parse(url || "") do
    %URI{scheme: s, host: h} when s in ["https", "http"] and is_binary(h) -> url
    _ -> nil
  end
end
# <a :if={u = safe_url(@user.website)} href={u} target="_blank" rel="noopener noreferrer">
redirect(conn, to: local_path_or_default(params["return_to"]))   # `to:` rejects external URLs
```

**Review notes:** allowlist schemes, never denylist `javascript:`. For
redirects prefer `to:` (local paths only) or a session-stored return path
(`phx.gen.auth`'s `:user_return_to`). `push_navigate`/`<.link navigate>`
are local-only. Still require explicit `rel` on `_blank`.

**False positives:** href is a `~p` verified route; redirect target is
resolved server-side from a token.

---

## §postMessage / cross-window messaging

**Threat:** a `message` listener (in a hook or `app.js`) that doesn't
verify `event.origin` accepts commands from any page that framed or
opened you.

```js
// ❌
window.addEventListener("message", (e) => this.pushEvent("apply", e.data))
// ✅
window.addEventListener("message", (e) => {
  if (e.origin !== "https://trusted.example.com") return
  // validate shape; the server re-validates in handle_event anyway
})
```
Sending side: explicit `targetOrigin`, never `"*"`, for non-public data.
Remove listeners in the hook's `destroyed()`.

**False positives:** origin allowlisted just below; listener handles only
public, side-effect-free data.

---

## §Clickjacking / framing

**Threat:** authenticated, state-changing UI framed transparently over
attacker bait.

**Fix:** CSP `frame-ancestors 'none'` (or `'self'`) via
`put_secure_browser_headers` — Phoenix's default CSP sets
`frame-ancestors 'self'`; overriding the CSP header must keep it.
Sensitive actions (`data-confirm` / a confirm step, re-auth via
`sudo_mode` in phx.gen.auth) also need a second control. See
`templates/security-headers.md`.

**False positives:** route is public, read-only, intentionally embeddable
— document the allowlist.

---

## §CSP with LiveView

- LiveView works under `script-src 'self'` as long as all JS ships in
  `app.js` (colocated hooks are bundled there). AGENTS.md forbids inline
  `<script>` — keep it that way; no `unsafe-inline`.
- The generated `root.html.heex` has an **inline theme script** — move it
  into `app.js` or give it a per-request nonce (`assign(conn, :csp_nonce,
  ...)` + `nonce={@csp_nonce}`) / hash; otherwise strict CSP breaks it or
  someone adds `unsafe-inline`.
- `connect-src 'self'` covers the same-origin `wss:` socket in modern
  browsers; add the explicit `wss://host` only if older Safari matters.
- `phx-click="..."`, `phx-*` attributes are not inline JS — CSP-safe.
  `JS.set_attribute({"style", ...})` and topbar's inline styles may need
  `style-src 'self' 'unsafe-inline'`; that's a far smaller risk than in
  `script-src` — note it, don't block on it.

---

## §Secrets in the asset bundle / rendered HTML

**Threat:** `priv/static/assets/*.js`, source maps, rendered HTML, LiveView
diffs over the socket, `push_event` payloads, and `localStorage` are
attacker-readable. Common leaks: a key hardcoded in `assets/js`, an
esbuild `--define` of an env var, a full `%User{}` rendered into a
`data-*`/JSON blob, a token placed in assigns and rendered.

```heex
<%!-- ❌ ships hashed_password, tokens, PII to the browser --%>
<div id="app" data-user={Jason.encode!(@current_scope.user)}></div>
```
```heex
<%!-- ✅ project exactly what the client needs --%>
<div id="app" data-user={Jason.encode!(%{id: @user.id, name: @user.name})}></div>
```

**Review notes:** anything `esbuild` inlines is public. Assigns that are
never rendered stay on the server — but a later template change can
render them, so don't stash secrets there either. Use
`@derive {Jason.Encoder, only: [...]}` and `@derive {Inspect, except: [...]}`
on schemas with sensitive fields. Leaked secret → **rotate, not redact**.
Session tokens belong in the `HttpOnly` cookie, not `localStorage`.

**False positives:** designed-public values (Stripe publishable key,
Sentry DSN, public map token) — confirm it's the publishable variant.

---

## §Third-party scripts & supply chain (client)

**Threat:** a third-party script runs with full origin privileges —
including the LiveView socket. A compromised CDN/npm package = full
client compromise.

**Fix:** AGENTS.md already requires vendoring into `app.js` (no external
`src`); keep it. Pin npm deps in `assets/package-lock.json` if used.
Strict CSP `script-src 'self'`. Minimize third parties on auth/payment
pages.

**False positives:** dependency vendored, pinned, and CSP-scoped.

---

## Quick triage table

| Seen in diff | Default severity if request-derived |
|---|---|
| `raw/1` / `{:safe, _}` / hook `innerHTML` on stored data | High (stored XSS) |
| same, on reflected params | Medium–High |
| `eval`/`new Function` in a hook with non-constant | High |
| credential in `assets/js` / esbuild define / rendered HTML | High (rotate) |
| full struct encoded into `data-*` / `push_event` | Med–High (PII/secret) |
| `postMessage` listener, no origin check | Medium–High |
| `redirect(external:)` with a param | Medium (High in OAuth flow) |
| `href` from user without scheme check | Medium |
| missing `frame-ancestors` on sensitive UI | Medium |
| `target="_blank"` no `rel` | Low |
