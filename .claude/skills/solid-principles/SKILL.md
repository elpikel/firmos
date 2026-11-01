---
name: solid-principles
description: >-
  SOLID design principles applied to Elixir/Phoenix projects (Ecto,
  PostgreSQL, Oban). Use when designing or refactoring modules, Phoenix
  contexts, behaviours, and protocols, reviewing code for design smells
  (rigid, fragile, tightly coupled code), deciding how to split
  responsibilities or introduce abstractions (behaviours + Mox, protocols,
  function arguments), or answering "is this good design / which SOLID
  principle applies here" questions. Covers all five principles with
  idiomatic Elixir before/after examples and guidance on when applying them
  helps and when it is over-engineering.
---

# SOLID Principles in Elixir

Five design principles (Robert C. Martin) that keep code flexible, testable,
and resistant to rot — adapted to idiomatic Elixir, where modules, behaviours,
protocols, pattern matching, and plain function arguments replace classes and
interfaces, often satisfying a principle without ceremony.

## 🎯 Why: Design for Change

The goal of writing software is to be able to **change it safely**. SOLID
is a toolkit for that goal: SRP limits *what* changes when a reason
to change appears, OCP lets you extend without editing tested code, LSP
keeps substitutions safe, ISP keeps consumers from breaking on unrelated
changes, DIP lets you swap implementations without rewriting policy.
Every rule below earns its keep only if it shrinks the next diff.

## How to use this skill

1. Match the symptom in the decision guide below to a principle.
2. Open `references/principles.md` for the full before/after Elixir
   example and the "when this is over-engineering" note for that principle.
3. Apply the smallest change that removes the actual pain. SOLID is a
   response to *demonstrated* change pressure, not a checklist to apply
   preemptively. A small context does not need a behaviour per module.

## Reference file

- `references/principles.md` — all five principles (SRP, OCP, LSP, ISP, DIP)
  with motivation, a bad example, a refactor, Elixir-specific notes, and
  when *not* to apply each.

## The five principles

| Letter | Principle | One-line intent |
|---|---|---|
| **S** | Single Responsibility | A module/context should have one reason to change. |
| **O** | Open/Closed | Open for extension, closed for modification. |
| **L** | Liskov Substitution | Every behaviour/protocol implementation must honor the contract. |
| **I** | Interface Segregation | Many small behaviours beat one fat one. |
| **D** | Dependency Inversion | Depend on behaviours you own, not concrete modules. |

## Decision guide — symptom → principle

| You notice… | Apply | Letter |
|---|---|---|
| A module changes for unrelated reasons (Repo + formatting + business rules) | Single Responsibility | S |
| Adding a new variant means editing the same `case` in several modules | Open/Closed | O |
| A behaviour impl raises, returns `nil`, or a different shape than `@callback` says | Liskov Substitution | L |
| Implementers must define callbacks they don't use (stubs that raise) | Interface Segregation | I |
| A context calls `Req`/an SDK/a vendor module directly | Dependency Inversion | D |
| Unit tests need the network, a real external API, or a real clock | Dependency Inversion | D |
| One change ripples across many unrelated modules | Single Responsibility | S |
| `case x.__struct__` / `is_struct(x, Foo)` chains decide behavior | Open/Closed (protocol or behaviour) | O |

## Elixir-specific guidance

- **Behaviours are interfaces; protocols are polymorphism over data.** Use a
  behaviour (`@callback`) when you swap *implementations* (HTTP client,
  payment provider); use a protocol when behavior varies by *data type*.
- **Prefer function arguments over fat behaviours.** A dependency that is
  "something that can save a user" can be a `(User.t() -> :ok)` function
  argument, not a `Repository` behaviour — ISP and DIP in one move.
- **Multi-clause functions over a closed set of atoms are a valid OCP
  alternative.** When variants are known and owned by you, a `case`/function
  heads over `:circle | :square` is clearer than a protocol.
- **Config-injected modules + Mox are the default DIP mechanism.** Resolve the
  implementation via `Application.get_env/3` (or `compile_env`), define a Mox
  mock for the behaviour in tests. Don't call vendor modules from contexts.
- **Don't abstract on speculation.** Introduce a behaviour when you have a
  second implementation or a real Mox testing need — not "just in case."
