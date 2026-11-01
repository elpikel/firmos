---
name: design-principles
description: >-
  General software design principles for Elixir/Phoenix projects (Ecto,
  PostgreSQL, Oban) that are NOT part of SOLID or the Gang of Four patterns —
  coupling and cohesion (incl. connascence), DRY, YAGNI, KISS, separation of
  concerns (web layer vs contexts vs schemas vs Repo), encapsulation /
  information hiding (context boundaries, @opaque types), Tell Don't Ask, Law
  of Demeter, composition over `use` macros, program-to-a-behaviour,
  Command–Query Separation, Principle of Least Astonishment, and fail-fast /
  let it crash. Use when designing or refactoring modules and contexts,
  reviewing code for coupling/duplication/leaky-abstraction smells, deciding
  whether an abstraction earns its keep, or answering "is this good design /
  which principle applies" questions that SOLID and GoF do not cover.
---

# Design Principles in Elixir (beyond SOLID & GoF)

The design heuristics that predate and underpin SOLID: how to measure and
reduce coupling, maximize cohesion, avoid premature/false abstraction, and keep
modules in charge of their own data — adapted to idiomatic Elixir, Phoenix
contexts, and Ecto.

## 🎯 Why: Design for Change

The goal of writing software is to be able to **change it safely**. Coupling
is the cost of the next change; cohesion is its locality. Tell-Don't-Ask,
Demeter, encapsulation, composition-over-inheritance — all of these exist
to shrink the blast radius of an edit. DRY and YAGNI cut both ways: too
little abstraction and a change ripples; too much and the seam is in the
wrong place. Pick the abstraction that makes the *next* diff small.

## Scope — how this differs from the other two skills

- **`solid-principles`** owns SRP, OCP, LSP, ISP, DIP. This skill does **not**
  re-explain those. Where a principle here is adjacent (Separation of Concerns
  ≈ SRP at the architecture level; Program-to-a-Behaviour ≈ DIP/ISP), the
  reference file states the distinction and defers to `solid-principles`.
- **`gof-patterns`** owns the 23 named patterns. This skill explains the
  *forces* (coupling, cohesion, Tell-Don't-Ask) that motivate those patterns
  but never re-documents a pattern. "Composition over inheritance" here is the
  general principle; the patterns that apply it (Strategy, Decorator) live in
  `gof-patterns`.

## How to use this skill

1. Match the symptom in the decision guide to a principle.
2. Open `references/principles.md` for that principle's full before/after
   Elixir example and its "when this is over-engineering" note.
3. Apply the smallest change that removes real pain. These are heuristics that
   trade off against each other (DRY vs. coupling, YAGNI vs. extensibility) —
   resolve the conflict in favor of the code that is cheapest to change *now*.

## Reference file

- `references/principles.md` — all principles with intent, a smell, a bad
  example, a refactor, Elixir-specific notes, and when *not* to apply.

## The principles

| Principle | One-line intent |
|---|---|
| **Coupling** (loose vs. tight) | Minimize what one module must know about another; measure it with connascence. |
| **Cohesion** | Group things that change together and are used together. |
| **DRY** | Every piece of *knowledge* has one authoritative representation. |
| **YAGNI** | Don't build it until a real requirement demands it. |
| **KISS** | Prefer the simplest design that works; complexity must be earned. |
| **Separation of Concerns** | Web, domain (contexts), and persistence live in distinct layers. |
| **Encapsulation / Information Hiding** | Hide representation behind a context/module API; expose intent. |
| **Tell, Don't Ask** | Call a context function; don't pull a struct's state out to decide for it. |
| **Law of Demeter** | Talk only to immediate collaborators; don't navigate nested preloads. |
| **Composition over Inheritance** | Assemble behavior from explicit functions; beware `use` macros as hidden inheritance. |
| **Program to an Interface** | Depend on a behaviour/contract (or a function), not a concrete module. |
| **Command–Query Separation** | A function either changes state or returns data — not both (with honest exceptions). |
| **Principle of Least Astonishment** | Behavior should match the name and the caller's reasonable expectation. |
| **Fail Fast** | Reject invalid state at the boundary, loudly; let it crash under a supervisor. |

## Decision guide — symptom → principle

| You notice… | Apply |
|---|---|
| Changing module A forces edits in B, C, D | Reduce **Coupling** (find the connascence) |
| A `Helpers`/`Utils` module groups unrelated functions used by different callers | Improve **Cohesion** |
| The same business rule is encoded in three places | **DRY** |
| Two code paths look identical today but model different concepts | *Stop* applying DRY — see false-DRY note |
| A behaviour/config key exists "for the future" with one implementation | **YAGNI** |
| A clever macro/metaprogramming layer nobody can explain | **KISS** |
| Params parsing, business rules, and `Repo` calls interleaved in a controller/LiveView | **Separation of Concerns** |
| Callers outside a context call `Repo` or build changesets on its schemas | **Encapsulation** |
| Callers read struct fields, decide, then `Repo.update` it themselves | **Tell, Don't Ask** |
| `order.customer.address.country` reached through preloads in business code | **Law of Demeter** |
| A `use MyApp.Base` injects functions you then override or work around | **Composition over Inheritance** |
| Domain code calls `Req`/an SDK module directly; tests hit the network | **Program to an Interface** (then see `solid-principles` DIP) |
| A `get_*` function inserts rows, or a query function has side effects | **Command–Query Separation** |
| `get_user/1` returns `nil` while `get_user!/1` *creates* one | **Principle of Least Astonishment** |
| `nil` or bad params travel three layers before a `FunctionClauseError` | **Fail Fast** |

## Elixir-specific guidance

- **Connascence is the practical coupling metric.** Prefer connascence of
  *name* over connascence of *position* — replace long positional argument
  lists with a keyword list (`opts`) or map. Keep stronger forms (meaning,
  algorithm, timing) local to one module. See the Coupling section.
- **Phoenix contexts are the encapsulation boundary.** Callers use
  `Accounts.register_user/1`, never `Repo` or another context's schema
  changesets. Use `@moduledoc false` for internal modules and `@opaque` types
  when callers must not depend on a struct's shape.
- **A function argument *is* an interface.** "Program to an interface" rarely
  needs a behaviour; passing `notify :: (event -> :ok)` decouples just as
  well. Reach for a behaviour + config-injected module + Mox when you need a
  swappable boundary across the app (HTTP clients, external APIs).
- **Pattern matching, guards, and changesets** make fail-fast cheap: match the
  shape you expect in the function head and let anything else raise.
  Validate external input once, with a changeset, at the boundary.
- **Tell-Don't-Ask does not apply to templates.** LiveViews and HEEx
  legitimately *ask* (render struct fields). Apply Tell-Don't-Ask to
  contexts, workers, and domain code.
- **DRY is about knowledge, not characters.** Two functions with identical
  bodies that encode *different* decisions should stay separate; coupling them
  to save lines creates a change-amplifier. Rule of Three before extracting.
- **`use` is the closest thing to inheritance.** It runs arbitrary code in
  your module. Prefer explicit `import`/`alias`/`defdelegate`; keep
  `__using__` small and limited to framework wiring (`use FirmosWeb, :live_view`).
