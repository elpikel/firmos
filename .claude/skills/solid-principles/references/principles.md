# SOLID Principles — Elixir Reference

Each section: intent → smell → bad example → refactor → Elixir notes →
when applying it is over-engineering.

---

## S — Single Responsibility Principle (SRP)

**Intent:** A module should have one reason to change. Group code by the
actor/stakeholder it serves, not by superficial similarity.

**Smell:** A module mixes business rules, persistence, and presentation; a
change to the report format risks breaking save logic; the module name
contains "And" or "Manager"; a context function builds HTML.

### Bad

```elixir
defmodule Firmos.Invoices do
  def total(%Invoice{items: items}), do: items |> Enum.map(& &1.cents) |> Enum.sum()

  # Persistence concern
  def save(invoice) do
    Repo.insert_all("invoices", [%{total: total(invoice)}])
  end

  # Presentation concern
  def to_html(invoice), do: "<h1>Invoice</h1><p>Total: $#{total(invoice) / 100}</p>"
end
```

Three reasons to change: tax rules, the database, the HTML template.

### Refactor

```elixir
# Schema: shape + validation + invoice math
defmodule Firmos.Invoices.Invoice do
  use Ecto.Schema
  # schema ... changeset/2 ...
  def total(%__MODULE__{items: items}), do: items |> Enum.map(& &1.cents) |> Enum.sum()
end

# Context: domain API + persistence
defmodule Firmos.Invoices do
  def create_invoice(attrs), do: %Invoice{} |> Invoice.changeset(attrs) |> Repo.insert()
end

# Web layer: presentation
defmodule FirmosWeb.InvoiceComponents do
  use FirmosWeb, :html

  attr :invoice, Firmos.Invoices.Invoice, required: true
  def invoice_total(assigns) do
    ~H"""
    <p id="invoice-total">Total: {Firmos.Money.format(Invoice.total(@invoice))}</p>
    """
  end
end
```

`Invoice` now only changes when invoice *math* or shape changes.

**Elixir notes:** Phoenix's layering is SRP by design: web (controllers,
LiveViews, components) / contexts / schemas / `Repo`. A `Utils` module that
grows unrelated helpers is the same smell — split by consumer. Oban workers
should decode args and delegate to a context, not hold business rules.

**Over-engineering when:** the "responsibilities" always change together, or
splitting produces one-function modules that just forward calls. A small
Mix task's `run/1` doing three things is fine.

---

## O — Open/Closed Principle (OCP)

**Intent:** Add new behavior by adding code, not by editing existing,
tested code.

**Smell:** Every new variant adds a clause to the same `case` in several
modules that must each be updated.

### Bad

```elixir
def area(%{kind: :circle, r: r}), do: :math.pi() * r * r
def area(%{kind: :square, side: s}), do: s * s
# adding :triangle forces edits here AND in perimeter/1, render/1, ...
```

### Refactor (protocol)

```elixir
defprotocol Firmos.Shape do
  @spec area(t) :: float()
  def area(shape)
end

defmodule Firmos.Circle do
  defstruct [:r]

  defimpl Firmos.Shape do
    def area(%{r: r}), do: :math.pi() * r * r
  end
end

defmodule Firmos.Square do
  defstruct [:side]

  defimpl Firmos.Shape do
    def area(%{side: s}), do: s * s
  end
end

# Adding Triangle = new struct + defimpl, zero edits to existing code.
def total(shapes), do: shapes |> Enum.map(&Firmos.Shape.area/1) |> Enum.sum()
```

For swappable *implementations* rather than data types (e.g. a new export
format, a new payment provider), use a behaviour plus a module-per-variant
selected by config or a lookup map.

**Elixir notes:** Multi-clause functions over a closed set of atoms are *not
always* an OCP violation. If the variants are genuinely closed (an
`Ecto.Enum` status you own), keep the clauses together and let a missing
clause raise `FunctionClauseError` — or keep a single dispatch point:

```elixir
def handle(%Event{type: :created} = e), do: ...
def handle(%Event{type: :archived} = e), do: ...
# no catch-all: an unknown type crashes loudly instead of being ignored
```

Use protocols/behaviours when variants are open-ended or added by other
teams/libraries; use clauses when they are closed and you *want* central
updates.

**Over-engineering when:** you add a behaviour and a registry for a
two-branch condition that has not changed in a year. Wait for the second
real reason to extend.

---

## L — Liskov Substitution Principle (LSP)

**Intent:** Code written against a contract (behaviour or protocol) must work
unchanged with any implementation. Implementations may not demand more of
callers (narrower inputs) or deliver less (different return shapes, raising
where the contract says `{:error, _}`).

**Smell:** One implementation of a behaviour raises `"not supported"`,
returns `nil` where others return `{:error, reason}`, or quietly does
nothing; callers need `case impl do ...` checks before using it.

### Bad

```elixir
defmodule Firmos.Storage do
  @callback fetch(key :: String.t()) :: {:ok, binary()} | {:error, term()}
end

defmodule Firmos.Storage.S3 do
  @behaviour Firmos.Storage
  @impl true
  def fetch(key), do: {:ok, download!(key)}
end

defmodule Firmos.Storage.Local do
  @behaviour Firmos.Storage
  @impl true
  def fetch(key), do: File.read!(key)   # returns bare binary, raises on missing
end

# Caller written against the contract breaks for Local:
with {:ok, body} <- storage.fetch(key), do: process(body)
```

`Local` is not substitutable for the `Storage` contract.

### Refactor

Honor the callback's return contract in every implementation.

```elixir
defmodule Firmos.Storage.Local do
  @behaviour Firmos.Storage
  @impl true
  def fetch(key), do: File.read(key)   # {:ok, binary} | {:error, posix}
end
```

**Elixir notes:** `@callback` + `@impl true` check that functions *exist*
with the right arity; Dialyzer checks typespecs loosely — neither enforces
behavioral contracts, so LSP violations compile fine. Watch for: impls that
raise where the contract returns errors, different `{:error, _}` reason
shapes callers match on, extra required opts, and protocol impls that only
handle some field combinations. Mox mocks must follow the same contract,
or tests prove nothing.

**Over-engineering when:** there is no behaviour/protocol at all — LSP only
governs substitutable implementations. Don't invent a behaviour to
"apply LSP."

---

## I — Interface Segregation Principle (ISP)

**Intent:** No client should depend on functions it does not use. Prefer
several small role behaviours over one general-purpose one.

**Smell:** Implementers define callbacks that just raise; a change to an
unused callback forces every implementation (and its Mox expectations) to
change.

### Bad

```elixir
defmodule Firmos.Machine do
  @callback print(doc :: String.t()) :: :ok
  @callback scan(doc :: String.t()) :: String.t()
  @callback fax(doc :: String.t()) :: :ok
end

defmodule Firmos.SimplePrinter do
  @behaviour Firmos.Machine
  @impl true
  def print(_doc), do: :ok
  @impl true
  def scan(_doc), do: raise("not supported")   # LSP+ISP smell
  @impl true
  def fax(_doc), do: raise("not supported")
end
```

### Refactor

```elixir
defmodule Firmos.Printer do
  @callback print(doc :: String.t()) :: :ok
end

defmodule Firmos.Scanner do
  @callback scan(doc :: String.t()) :: String.t()
end

defmodule Firmos.SimplePrinter do
  @behaviour Firmos.Printer
  @impl true
  def print(_doc), do: :ok
end

defmodule Firmos.AllInOne do
  @behaviour Firmos.Printer
  @behaviour Firmos.Scanner
  @impl Firmos.Printer
  def print(_doc), do: :ok
  @impl Firmos.Scanner
  def scan(_doc), do: "..."
end

# Consumers depend only on what they need:
def batch_print(printer, docs), do: Enum.each(docs, &printer.print/1)
```

**Elixir notes:** The narrowest interface is a function argument — no named
behaviour required:

```elixir
def batch_print(print_fun, docs) when is_function(print_fun, 1),
  do: Enum.each(docs, print_fun)
```

Behaviours can also mark callbacks optional with `@optional_callbacks`, but
that's usually a sign the behaviour should be split.

**Over-engineering when:** you split a cohesive behaviour whose callbacks are
always implemented and consumed together (e.g. an HTTP client's
`get/post`). Segregate along *real* client boundaries, not for symmetry.

---

## D — Dependency Inversion Principle (DIP)

**Intent:** High-level policy should not depend on low-level details. Both
depend on abstractions. The abstraction (behaviour) is owned by the
high-level module.

**Smell:** A context calls a vendor SDK or `Req` directly; unit tests need
the real API (or `Bypass` for every business test); swapping the vendor
means editing core logic.

### Bad

```elixir
defmodule Firmos.Signups do
  def register(email) do
    # hard-wired detail inside policy
    Req.post!("https://api.mailvendor.com/contacts", json: %{email: email})
    Accounts.create_user(%{email: email})
  end
end
```

Untestable without the network; vendor lock-in in the policy layer.

### Refactor (behaviour + config injection)

```elixir
# Abstraction owned by the high-level module:
defmodule Firmos.Signups.Mailer do
  @callback add_contact(email :: String.t()) :: :ok | {:error, term()}
end

defmodule Firmos.Signups do
  defp mailer, do: Application.get_env(:firmos, :signups_mailer, Firmos.Signups.MailVendor)

  def register(email) do
    with :ok <- mailer().add_contact(email) do
      Accounts.create_user(%{email: email})
    end
  end
end

# Detail depends on the abstraction:
defmodule Firmos.Signups.MailVendor do
  @behaviour Firmos.Signups.Mailer
  @impl true
  def add_contact(email) do
    case Req.post("https://api.mailvendor.com/contacts", json: %{email: email}) do
      {:ok, %Req.Response{status: 200}} -> :ok
      other -> {:error, other}
    end
  end
end

# config/test.exs:   config :firmos, signups_mailer: Firmos.Signups.MailerMock
# test_helper.exs:   Mox.defmock(Firmos.Signups.MailerMock, for: Firmos.Signups.Mailer)
# test:              expect(Firmos.Signups.MailerMock, :add_contact, fn _ -> :ok end)
```

**Elixir notes:**
- The abstraction can be a function argument instead of a behaviour:
  `register(email, add_contact \\ &MailVendor.add_contact/1)`.
- Keep the behaviour next to its *consumer* (`Firmos.Signups.Mailer`), not
  next to the vendor module — that is what "inversion" means.
- `Application.get_env/3` at runtime keeps config swappable;
  `Application.compile_env/3` avoids the lookup but requires recompiling.
  Avoid DI frameworks — config + Mox is enough.

**Over-engineering when:** the dependency is stable, owned by you, and has no
alternate implementation or test seam (`Repo` in a context, a pure
date-math helper, `Jason`). A behaviour with exactly one implementation that
you'll never mock adds indirection for nothing.

---

## Quick review checklist

- [ ] Does each module/context have a single stakeholder/reason to change? (S)
- [ ] Can a new variant be added without editing tested code — or are the
      function clauses intentionally central over a closed set? (O)
- [ ] Does every behaviour/protocol impl (and Mox mock) honor the callback's
      return contract without caller special-casing? (L)
- [ ] Do implementers ever define callbacks that just raise? (I)
- [ ] Does policy depend on a behaviour it owns, with the concrete module
      chosen by config and mocked with Mox in tests? (D)
- [ ] Is each abstraction earning its keep (≥2 impls or a real test seam),
      not added on speculation?
