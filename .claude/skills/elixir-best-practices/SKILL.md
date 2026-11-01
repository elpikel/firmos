---
name: elixir-best-practices
description: >-
  Idiomatic Elixir, Phoenix, Ecto and OTP conventions for this codebase:
  tagged tuples `{:ok, v} | {:error, reason}` chained with `with`, bang
  functions only where crashing is right, pattern matching in function heads
  and guards, structs with `@enforce_keys` and `@type t`, `@spec` on public
  functions, contexts as the boundary (web never calls Repo), changesets as
  boundary validation, named-binding Ecto queries and preloads (no N+1),
  processes only for runtime concerns, supervision, `Task.async_stream`,
  Req for HTTP, behaviours + Mox for external services, runtime config,
  Logger metadata, and the project rule that every struct derives
  `Inspect`/`Jason.Encoder` deliberately so secrets never leak. Use when
  writing or reviewing Elixir/Phoenix/Ecto/OTP code, designing a context,
  schema, GenServer or external-service adapter, or answering "what is the
  idiomatic Elixir way to do this". Ships templates for a context, schema,
  domain error, behaviour adapter and supervised GenServer.
---

# Elixir Best Practices & Idioms

How to write Elixir that stays easy to change: make success and failure
explicit in return values, let pattern matching do the branching, keep
side effects behind context and behaviour boundaries, and use processes
for runtime properties — not as a way to organize code.

Framework-level Phoenix/LiveView/HEEx/Ecto rules (forms, streams, HEEx
syntax, `<Layouts.app>`, test helpers, `mix precommit`) live in the
project's `AGENTS.md`. They are binding; this skill does not repeat them.
It covers the language/design idioms underneath.

## 🎯 Why: Design for Change

The goal of writing software is to be able to **change it safely**.
Tagged tuples and `with` make every failure a value the caller must
handle, so a new error reason shows up at each call site instead of as a
3am crash. Contexts and behaviours put a seam between "what the app does"
and "how it is stored / which API it calls", so either side can move
without the other noticing. `@spec` + Dialyzer and pattern-matched heads
turn the compiler into a change-detector. Explicit `@derive` rules make
the log/JSON shape a contract instead of an accident. Idiomatic Elixir
exists to keep the next refactor mechanical instead of archaeological.

For OO-style design pressure use `solid-principles` / `design-principles`;
for named patterns `gof-patterns`; for SQL/schema design `postgres-dba`.

## How to use this skill

1. Match the symptom in the decision guide to a rule.
2. Open the reference for that rule: rationale, bad example, idiomatic
   version, and when it is over-engineering.
3. Copy the closest file from `templates/` and adapt it — they already
   follow every rule below (specs, derives, tagged tuples, named bindings).
4. Run `mix precommit` (compile with warnings-as-errors, format via
   Styler, tests) before calling it done. Never fight the formatter.

## Hard rules

These fail silently or leak data when broken; apply them everywhere:

1. **Expected failures return `{:ok, value} | {:error, reason}`**; chain
   them with `with`. Raise only for programmer errors / broken invariants.
   Bang functions (`get!`, `insert!`) only where a crash is the correct
   outcome (e.g. 404 from a router param, seeds, tests).
2. **Public functions have `@spec`; public modules have `@moduledoc`.**
   Structs declare `@type t` and `@enforce_keys` for required fields.
3. **Never `String.to_atom/1` on external input** — use
   `String.to_existing_atom/1` or an explicit whitelist map.
4. **Web layer never calls `Repo`** — it calls context functions.
   External data enters through a changeset (or explicit parsing) at the
   context boundary.
5. **Ecto queries use named bindings** (`from(o in Order, as: :order)`)
   and preload associations that callers will touch. No queries in loops.
6. **Every struct that may be logged or serialized has deliberate
   `@derive` rules**: `{Inspect, except: [secrets]}` and
   `{Jason.Encoder, only: [public fields]}`. Secrets never reach logs or
   JSON. See `references/protocols-inspect-json.md`.
7. **Processes are for runtime concerns** (state, concurrency, fault
   isolation) and are always supervised. Not for code organization.
8. **External services sit behind a behaviour**, implemented with `Req`,
   selected via config, and replaced by a Mox mock in tests.
9. **Secrets and environment-dependent config go in `config/runtime.exs`**,
   read with `System.fetch_env!/1`. Never `Application.get_env` at
   compile time (module attributes) for runtime values.

## Decision guide

| Symptom / question | Rule | Where |
|---|---|---|
| Function returns `nil`, `false` or raises for an expected failure | Return `{:ok, v} \| {:error, reason}` | idioms.md §1 |
| Nested `case` pyramids | `with` + tagged tuples | idioms.md §2 |
| `get!` / `insert!` in a context function called by user input | Non-bang + tagged tuple; bang only where crashing is right | idioms.md §3 |
| `if`/`cond` inspecting a map's shape | Pattern match in function heads + guards | idioms.md §4 |
| Bare map passed around as a domain value | Struct with `@enforce_keys` + `@type t` | idioms.md §5, templates/schema.ex |
| Dialyzer silent / no idea what a function returns | `@spec` on public functions, narrow types | idioms.md §6 |
| `String.to_atom(params["sort"])` | Whitelist / `to_existing_atom` | idioms.md §7 |
| LiveView/controller calls `Repo.*` | Move into a context function | idioms.md §8, templates/context.ex |
| Validating params by hand in the web layer | Changeset at the context boundary | idioms.md §9, templates/schema.ex |
| Positional query bindings `[o, c, i]` getting confused | Named bindings `as:` | idioms.md §10 |
| Template triggers a query per row | Preload / join-preload | idioms.md §11 |
| Multi-step write must be all-or-nothing | `Ecto.Multi` + `Repo.transaction` | idioms.md §12, templates/context.ex |
| Domain error needs a type, message and fields | Error struct / `defexception` | idioms.md §13, templates/error.ex |
| GenServer used just to "group functions" | Plain module; process only for state/concurrency/isolation | otp.md §1 |
| Need long-lived state, a cache, a rate limiter | Supervised GenServer with client API | otp.md §2, templates/genserver.ex |
| Dynamic per-entity processes | `DynamicSupervisor` + `Registry` | otp.md §3 |
| Concurrent map over a collection | `Task.async_stream(..., timeout: :infinity)` | otp.md §4 |
| Fire-and-forget work | `Task.Supervisor.start_child` | otp.md §4 |
| Calling a third-party HTTP API | Behaviour + Req adapter + Mox | idioms.md §14, templates/behaviour_adapter.ex |
| `Application.get_env` in a module attribute / secret in `config.exs` | `config/runtime.exs` + `System.fetch_env!` | idioms.md §15 |
| `Logger.info("user #{inspect(user)} did x")` | Logger metadata, no struct dumps | idioms.md §16 |
| Struct with a password/token gets logged or rendered as JSON | `@derive` Inspect/Jason rules | protocols-inspect-json.md |
| `"#{order}"` fails with Protocol.UndefinedError | Implement `String.Chars` (only for value-like structs) | protocols-inspect-json.md |

## Reference files

- `references/idioms.md` — §1–§16 with intent, bad/idiomatic examples,
  notes, and when the rule is over-engineering.
- `references/otp.md` — when (not) to use a process; GenServer,
  Supervisor, Registry, DynamicSupervisor, Task essentials.
- `references/protocols-inspect-json.md` — the mandatory `@derive`
  rule (the Elixir analogue of `toString()`/`toJSON()`): contract,
  redaction, testing.

## Templates (copy and adapt)

| File | Use case |
|---|---|
| `templates/context.ex` | Phoenix context: list/get/create/update/delete, changesets, named-binding query, preload, `Ecto.Multi` |
| `templates/schema.ex` | Ecto schema + changesets with `@type t`, `@derive` Inspect/Jason rules, virtual secret field |
| `templates/error.ex` | Domain error via `defexception` + tagged-error conventions |
| `templates/behaviour_adapter.ex` | Behaviour + Req implementation + config + Mox setup |
| `templates/genserver.ex` | Minimal supervised GenServer with client API and `@spec`s |
