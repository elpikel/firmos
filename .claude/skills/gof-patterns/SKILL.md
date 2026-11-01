---
name: gof-patterns
description: >-
  Gang of Four design patterns reference for Elixir/Phoenix projects (Ecto,
  OTP, Oban). Use when choosing or implementing a design pattern, refactoring
  toward a known pattern, reviewing code for pattern misuse, or answering
  "which pattern fits here" / "what's the Elixir way to do X pattern"
  questions. Covers all 23 creational, structural, and behavioral patterns
  with idiomatic Elixir equivalents (behaviours, protocols, pipelines,
  processes, PubSub, Plug) and guidance on when (and when not) to use each.
---

# Gang of Four Patterns in Elixir

The 23 classic design patterns from *Design Patterns: Elements of Reusable
Object-Oriented Software* (Gamma, Helm, Johnson, Vlissides), translated to
idiomatic Elixir/Phoenix. Many were invented to work around limits of
class-based OO; in a functional, immutable, process-based language several
dissolve into a plain function, a struct update, or something OTP/Phoenix
already ships. Each entry says so honestly and shows the native equivalent.

## 🎯 Why: Design for Change

The goal of writing software is to be able to **change it safely**. Every
GoF pattern is a named seam that isolates one axis of change: Strategy
hides algorithm choice, Adapter hides a vendor swap, Observer hides who's
listening, Factory hides what's instantiated. Reach for a pattern when
you have a *demonstrated* axis of change to absorb. A pattern installed
speculatively adds coupling without buying any change-safety.

In Elixir the seams are usually: a **behaviour** (swap a module), a
**protocol** (dispatch on data type), a **function argument** (swap code at
the call site), or a **process boundary** (swap/supervise a running thing).

## How to use this skill

1. Identify the *kind* of problem from the decision guide below.
2. Open the matching reference file for the Elixir example and the
   "when to use / when not to" notes.
3. Prefer the simplest construct that solves the problem: a function, a
   multi-clause function with pattern matching, a struct, or a pipeline. Add
   a behaviour, protocol, or process only when the indirection earns its keep.

## Reference files

- `references/creational.md` — creation: Factory Method, Abstract Factory,
  Builder, Prototype, Singleton.
- `references/structural.md` — composition: Adapter, Bridge, Composite,
  Decorator, Facade, Flyweight, Proxy.
- `references/behavioral.md` — interaction & responsibility: Chain of
  Responsibility, Command, Interpreter, Iterator, Mediator, Memento, Observer,
  State, Strategy, Template Method, Visitor.

## Decision guide — symptom → pattern

| You are trying to… | Consider | Elixir shape | Category |
|---|---|---|---|
| Create data without naming the concrete implementation | Factory Method, Abstract Factory | Function returning a struct; config-selected behaviour module | Creational |
| Build a complex value step by step | Builder | Pipeline over a struct (`Ecto.Changeset`, `Ecto.Multi`, `Ecto.Query`) | Creational |
| Copy an existing value | Prototype | `%{struct \| field: v}` — free with immutability | Creational |
| Guarantee exactly one instance | Singleton | Named GenServer/Agent, `:persistent_term`, app env | Creational |
| Make an incompatible interface usable | Adapter | Behaviour + adapter modules (Swoosh, Ecto adapters) | Structural |
| Vary abstraction and implementation independently | Bridge | Behaviour/protocol on each side | Structural |
| Treat individual items and groups uniformly | Composite | Recursive data + recursive functions | Structural |
| Add behavior without changing the callee | Decorator | Higher-order function wrapping, Plug, `:telemetry.span` | Structural |
| Hide a complex subsystem behind one interface | Facade | Phoenix context module | Structural |
| Share many fine-grained values cheaply | Flyweight | Atoms, shared binaries, `:persistent_term`, ETS | Structural |
| Control access to a resource (lazy, remote, guarded) | Proxy | GenServer in front, `Stream`, Ecto preload | Structural |
| Pass a request along a series of handlers | Chain of Responsibility | Plug pipeline, `with`, `Enum.reduce_while` | Behavioral |
| Encapsulate a request as a value (undo, queue) | Command | Tuple/struct as data; Oban job; `Ecto.Multi` | Behavioral |
| Evaluate sentences in a small language | Interpreter | Pattern-matched AST evaluator | Behavioral |
| Traverse a collection without exposing its structure | Iterator | `Enumerable` protocol, `Stream`, `Repo.stream` | Behavioral |
| Reduce many-to-many coupling | Mediator | Phoenix.PubSub, Registry, coordinating GenServer | Behavioral |
| Capture and restore state | Memento | Keep the old immutable value; event sourcing | Behavioral |
| Notify dependents of state changes | Observer | Phoenix.PubSub, `:telemetry`, Registry dispatch | Behavioral |
| Change behavior when internal state changes | State | `:gen_statem`, state-tagged clauses | Behavioral |
| Swap one of several algorithms at runtime | Strategy | Pass a function or behaviour module | Behavioral |
| Fix an algorithm skeleton, vary steps | Template Method | Behaviour + `__using__` with `defoverridable` | Behavioral |
| Add operations over a set of types without editing them | Visitor | Protocols, multi-clause functions | Behavioral |

## Elixir-specific guidance

- **Behaviours are the interface; config picks the implementation.**
  `Application.get_env(:firmos, :mailer_impl, Firmos.Mailer.Swoosh)` plus a
  `@callback` contract is the Elixir answer to Factory, Adapter, Bridge, and
  Strategy at once — and it is exactly what Mox needs in tests.
- **Protocols dispatch on data, behaviours dispatch on modules.** Use a
  protocol when the *value's type* decides behavior (Visitor, Iterator via
  `Enumerable`); use a behaviour when *configuration or the caller* decides.
- **Immutability makes Prototype and Memento nearly free.** Keeping the old
  value *is* the snapshot; `%{s | x: 1}` *is* the clone.
- **Processes are not objects.** Don't wrap every module in a GenServer to get
  "an instance". Use a process only for state that outlives a call,
  concurrency, or fault isolation. A single named process is a serialization
  point — a Singleton GenServer on a hot path becomes a bottleneck.
- **Pipelines are Builders and Chains.** `Plug.Conn`, `Ecto.Changeset`,
  `Ecto.Multi`, and `Ecto.Query` are production builders/chains; extend them
  rather than inventing parallel abstractions.
- **Macros are the last resort.** `use`/`__using__`/`defoverridable`
  (Template Method) and `quote` (Interpreter) create compile-time coupling and
  hide control flow. Prefer explicit function calls and behaviours.
- Pattern match in function heads, prefer `with` for dependent steps, and use
  named bindings (`from(p in Post, as: :post)`) in Ecto examples.
