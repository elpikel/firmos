# Design Principles — Elixir Reference

Each section: intent → smell → bad example → refactor → Elixir notes →
when applying it is over-engineering. Principles covered by `solid-principles`
or `gof-patterns` are referenced, not repeated.

---

## Coupling — keep it loose; measure it with connascence

**Intent:** Minimize what one module must know about another so a change stays
local. "Coupling" is vague on its own; **connascence** makes it actionable —
two pieces of code are connascent if changing one forces a change in the other.
Weak/visible forms are tolerable; strong/distant forms are debt.

Strength ladder (weak → strong): **Name** → **Type** → **Meaning** →
**Position** → **Algorithm** → **Timing/Execution-order**. Rule of thumb:
weaken the form, or shrink its distance to a single module.

**Smell:** Editing one function forces ripple edits elsewhere; callers must
pass arguments in a magic order; two modules must agree on an undocumented
convention (`-1 means "not found"`, `0` means admin).

### Bad

```elixir
# Connascence of Position (arg order) + Meaning (magic integers)
def create_user(name, age, role, active) do
  # role: 0 admin, 1 member | active: 0 no, 1 yes (callers must "just know")
end

create_user("Ada", 36, 0, 1)
```

### Refactor

```elixir
# Connascence of Name only — keys and atoms carry the meaning
@type role :: :admin | :member

@spec create_user(%{name: String.t(), age: integer(), role: role(), active: boolean()}) ::
        {:ok, User.t()} | {:error, Ecto.Changeset.t()}
def create_user(attrs) do
  %User{} |> User.changeset(attrs) |> Repo.insert()
end

create_user(%{name: "Ada", age: 36, role: :admin, active: true})
```

**Elixir notes:** Maps and keyword lists convert connascence of position →
name; atoms and `Ecto.Enum` convert connascence of meaning → name (and
Dialyzer/typespecs can check it). Keep connascence of algorithm (e.g. a token
hash both sides must compute identically) inside one module exposing a
function — never duplicated across a context boundary.

**Over-engineering when:** two modules genuinely *are* one concept; forcing a
behaviour between them just to "decouple" adds an indirection with one
implementation (that is also a YAGNI violation). Some coupling is the design.

---

## Cohesion — group what changes and is used together

**Intent:** A module's functions should belong together. Highest value is
*functional* cohesion (everything serves one well-defined job). Avoid
*coincidental* ("misc utils") and *temporal* ("things we happen to do at
startup") cohesion.

**Smell:** `Firmos.Utils` / `Firmos.Helpers` aliased by half the codebase for
unrelated reasons; a context whose functions share no schemas with each other.

### Bad

```elixir
# Coincidental cohesion: unrelated functions sharing a module by accident
defmodule Firmos.Utils do
  def format_currency(cents), do: ...
  def retry(fun, attempts), do: ...
  def valid_email?(email), do: ...
end
```

### Refactor

```elixir
defmodule Firmos.Money do
  def format(cents), do: ...
end

defmodule Firmos.Retry do
  def run(fun, attempts), do: ...
end

# Email validation belongs with the schema that owns the rule:
# Firmos.Accounts.User.validate_email/1 inside the changeset
```

A telling test: if you can describe the module without "and", it is cohesive.

**Elixir notes:** Cohesion shows up in `alias` lines — a module aliased for
one of its ten functions by every caller signals it should be split. Phoenix
contexts are cohesion units: group schemas and functions by the domain
concept they serve, and keep validation in the schema's changeset rather than
a global helper module.

**Over-engineering when:** splitting yields one-function modules with more
`alias` noise than logic, or a "context per table" structure. Cohesion is
about *related change*, not minimal file size. (Module-level SRP overlaps here
— see `solid-principles`; this entry adds the cohesion *taxonomy*.)

---

## DRY — one authoritative source for each piece of knowledge

**Intent:** Each business rule, formula, or fact has exactly one
representation. Duplication of *knowledge* means a change must be made in N
places and one will be missed.

**Smell:** The same tax rule, validation regex, or status-transition table
copied into several modules; a bug fixed in one copy but not the others.

### Bad

```elixir
# Knowledge "free shipping over $50" duplicated and already drifting
def cart_summary(cart), do: %{free_shipping: cart.total >= 50}      # dollars
def checkout(cart), do: if(cart.total >= 5000, do: :free, else: :paid) # cents
```

### Refactor

```elixir
defmodule Firmos.Shipping do
  @free_shipping_cents 5_000

  def free_shipping?(total_cents), do: total_cents >= @free_shipping_cents
end
```

### The counter-rule (false DRY)

```elixir
# These look identical TODAY but encode unrelated decisions.
# Coupling them means a change to one breaks the other. Keep separate.
def eligible_for_trial?(user), do: user.country == "US" and user.age >= 18
def can_purchase_alcohol?(user), do: user.country == "US" and user.age >= 18
```

**Elixir notes:** DRY *shapes* with a single source of truth — the Ecto
schema (`@type t`, `Ecto.Enum` values via `Ecto.Enum.values/2`) — instead of
hand-syncing atom lists across modules. Share query fragments as composable
functions (`def active(query), do: where(query, [user: u], u.active)`), not
copy-pasted `where` clauses.

**Over-engineering when:** you deduplicate incidental similarity. Apply the
**Rule of Three**: tolerate the second occurrence; extract on the third, once
the shared *concept* is proven. Premature abstraction is harder to undo than
duplication.

---

## YAGNI — You Aren't Gonna Need It

**Intent:** Don't add capability, configurability, or generality until a
concrete, present requirement demands it. Speculative flexibility is carrying
cost (more code, more tests, more coupling) for unproven benefit.

**Smell:** Config keys with one value; a behaviour with one implementation
and no Mox mock; "we might support Postgres *and* Mongo" plumbing when only
Postgres ships; a GenServer wrapping state that could be a function argument.

### Bad

```elixir
# One payment provider exists. This abstracts three that don't.
defmodule Firmos.Payments.Gateway do
  @callback charge(map()) :: {:ok, map()} | {:error, term()}
end
# + GatewayRegistry, gateway config per env, a dispatcher ... all for Stripe-only
```

### Refactor

```elixir
# Ship the concrete thing. Introduce the behaviour when the SECOND
# provider (or a real Mox test-double need) actually arrives.
defmodule Firmos.Payments do
  def charge(attrs), do: Firmos.Payments.Stripe.charge(attrs)
end
```

**Elixir notes:** YAGNI tensions with OCP/DIP from `solid-principles` —
resolve it by *deferring*: as long as callers go through the context function
(`Payments.charge/1`), extracting a behaviour later touches one module, not
every call site. Also: don't reach for a process (GenServer/Agent) until you
need state, concurrency, or fault isolation — a module of functions is the
default.

**Over-engineering when:** the future need is essentially certain and the
reversal is expensive (public API shape, persisted schema/migrations, wire
formats, Oban job args already enqueued). YAGNI is about *speculative* needs,
not known irreversibility — those warrant upfront design.

---

## KISS — Keep It Simple

**Intent:** Among designs that meet the requirement, prefer the one with the
fewest moving parts and the lowest reader cognitive load. Complexity must buy
something measurable.

**Smell:** A macro/metaprogramming DSL where a plain function or `case` would
do; a "framework" for a three-case problem; a GenServer for a pure function.

### Bad

```elixir
# Generates handle_start/0, handle_stop/0 at compile time from a list
for cmd <- [:start, :stop] do
  def unquote(:"handle_#{cmd}")(), do: apply(__MODULE__, unquote(cmd), [])
end
```

### Refactor

```elixir
def handle(:start), do: start()
def handle(:stop), do: stop()
```

**Elixir notes:** Reach for the simplest construct first: multi-clause
function before a protocol, a function before a macro, a module before a
process. "Don't write macros" is the first rule of macro club — use them only
when a function cannot express it.

**Over-engineering when:** "simple" becomes a 400-line `case` or copy-paste
that a known pattern would tame. KISS is fewest *essential* parts, not fewest
abstractions at any cost — see `gof-patterns` for when indirection earns its
keep.

---

## Separation of Concerns

**Intent:** Different concerns (transport, business policy, persistence,
presentation) live in different layers: controllers/LiveViews (web),
contexts (domain API), schemas (data shape + validation), `Repo`
(persistence). Oban workers are another transport — keep them thin.

**Smell:** A LiveView `handle_event` that parses params, applies business
rules, calls `Repo` directly, and formats output — untestable without a
socket.

### Bad

```elixir
def handle_event("place_order", %{"items" => items}, socket) do
  total = Enum.reduce(items, 0, &(&2 + String.to_integer(&1["price"])))  # policy
  {:ok, order} = Repo.insert(%Order{total: total, user_id: socket.assigns.current_scope.user.id})
  {:noreply, put_flash(socket, :info, "Total $#{total / 100}")}            # presentation
end
```

### Refactor

```elixir
# Context: the domain API (pure policy + persistence behind one function)
defmodule Firmos.Orders do
  def place_order(%Scope{} = scope, attrs) do
    %Order{user_id: scope.user.id}
    |> Order.changeset(attrs)          # schema: casting + validation + total
    |> Repo.insert()
  end
end

# LiveView: thin wiring
def handle_event("place_order", %{"order" => params}, socket) do
  case Orders.place_order(socket.assigns.current_scope, params) do
    {:ok, order} -> {:noreply, push_navigate(socket, to: ~p"/orders/#{order}")}
    {:error, changeset} -> {:noreply, assign(socket, form: to_form(changeset))}
  end
end
```

**Elixir notes:** Keep contexts free of `Plug.Conn`/socket types so they are
testable with plain `DataCase` tests. An Oban worker's `perform/1` should
decode args and call one context function. This is SRP "in the large";
`solid-principles` covers the module-level case — the addition here is the
*layering* lens.

**Over-engineering when:** a CRUD context with no business logic is split into
service → repository → mapper modules wrapping `Repo` one-to-one. Phoenix
contexts already *are* the layer; add more only when domain complexity
demands it.

---

## Encapsulation / Information Hiding

**Intent:** Hide *how* a module represents its state; expose *what* it can do.
In Elixir the boundary is the module/context API, not field privacy — structs
are open data, so callers must be steered to functions.

**Smell:** Code outside `Firmos.Billing` calls `Repo.update` on a
`Billing.Wallet` or builds its changesets; callers maintain invariants the
context should own.

### Bad

```elixir
# In a LiveView or another context — anyone can set it negative
wallet
|> Ecto.Changeset.change(balance_cents: wallet.balance_cents - 100)
|> Repo.update()
```

### Refactor

```elixir
defmodule Firmos.Billing do
  alias Firmos.Billing.Wallet

  def withdraw(%Wallet{} = wallet, cents) when is_integer(cents) and cents > 0 do
    wallet
    |> Wallet.withdraw_changeset(cents)   # validates "never negative"
    |> Repo.update()
  end
end
```

**Elixir notes:** Contexts are the public API; schemas and `Repo` are their
internals. Mark helper modules `@moduledoc false`; use `@opaque t` for
data structures (not Ecto schemas) whose shape callers must not pattern-match
on, and construct them only via `new/1`. Keep `defp` for internals —
a private function cannot be called from outside.

**Over-engineering when:** wrapping a plain map / config / decoded JSON
payload in accessor functions that add no invariant. Data with no rules can
stay a plain map or struct with `@type`.

---

## Tell, Don't Ask

**Intent:** Call a function that does the job; don't extract a struct's state
to make the decision for it. Logic that uses a schema's data belongs in the
module (context or schema) that owns that data.

**Smell:** `if account.status == :active and account.balance >= amount, do:
Repo.update(...)` at call sites; the same decision repeated in several
LiveViews and workers.

### Bad

```elixir
if account.status == :active and account.balance_cents >= amount do
  account |> Ecto.Changeset.change(balance_cents: account.balance_cents - amount) |> Repo.update()
else
  {:error, :cannot_debit}
end
```

### Refactor

```elixir
defmodule Firmos.Accounts do
  def debit(%Account{status: :active, balance_cents: bal} = account, amount)
      when bal >= amount do
    account |> Account.debit_changeset(amount) |> Repo.update()
  end

  def debit(%Account{status: :active}, _amount), do: {:error, :insufficient_funds}
  def debit(%Account{}, _amount), do: {:error, :inactive_account}
end

Accounts.debit(account, amount)
```

**Elixir notes:** This is the force behind GoF Strategy/State/Command (see
`gof-patterns`). Apply it to contexts and workers. Deliberately *do not*
apply it to LiveView templates and JSON views — they legitimately read
struct fields to render.

**Over-engineering when:** it pushes rendering/formatting logic into a context
just to avoid reading a field in HEEx, hurting cohesion. Reading state for
display is fine; *deciding domain behavior* from outside the owner is not.

---

## Law of Demeter (Principle of Least Knowledge)

**Intent:** A function should talk only to its arguments, values it creates,
and modules it directly depends on. Don't navigate through one struct to
reach another ("don't talk to strangers").

**Smell:** `order.customer.address.country` in business code — the caller is
now coupled to the preload graph and crashes with
`%Ecto.Association.NotLoaded{}` when someone forgets a preload.

### Bad

```elixir
def shipping_zone(order) do
  zone_for(order.customer.address.country)   # 3 hops, assumes 2 preloads
end
```

### Refactor

```elixir
defmodule Firmos.Orders do
  # Expose the answer, not the graph; the context owns the query shape.
  def shipping_country(%Order{id: id}) do
    from(o in Order, as: :order,
      join: c in assoc(o, :customer), as: :customer,
      join: a in assoc(c, :address), as: :address,
      where: o.id == ^id,
      select: a.country
    )
    |> Repo.one!()
  end
end

def shipping_zone(order), do: order |> Orders.shipping_country() |> zone_for()
```

**Elixir notes:** `get_in/2` and `Map.get/3` chains make train wrecks
*nil-safe* but not *decoupled*. When a template truly needs nested data, the
context function that loads it should preload explicitly
(`Repo.preload(order, customer: :address)`) so the graph shape is owned in
one place.

**Over-engineering when:** applied to config and plain nested data you own
and that are stable (`config[:endpoint][:url]`, a decoded JSON payload), or to
templates rendering preloads the LiveView loaded itself. Demeter targets
*behavioral* boundaries, not plain data.

---

## Composition over Inheritance

**Intent:** Build behavior by assembling explicit functions and modules rather
than inheriting it. Elixir has no inheritance, but `use` + `__using__` is the
same trap: it injects code (and `defoverridable` defaults) into your module,
creating hidden coupling to a "base" module.

**Smell:** `use Firmos.BaseService` that injects a dozen functions; modules
that `defoverridable` and then override to raise; you can't tell where a
function is defined without expanding macros.

### Bad

```elixir
defmodule Firmos.BaseImporter do
  defmacro __using__(_opts) do
    quote do
      def run(path), do: path |> read() |> parse() |> persist()
      def read(path), do: File.read!(path)
      def persist(rows), do: Firmos.Repo.insert_all(__MODULE__.Row, rows)
      defoverridable read: 1, persist: 1
    end
  end
end

defmodule Firmos.ApiImporter do
  use Firmos.BaseImporter
  def read(_path), do: raise("not a file importer")   # LSP violation
end
```

### Refactor

```elixir
defmodule Firmos.Importer do
  # Behavior injected as plain function arguments
  def run(source, parse, persist) do
    source |> parse.() |> persist.()
  end
end

Firmos.Importer.run(File.read!(path), &CsvParser.parse/1, &Imports.save_rows/1)
```

**Elixir notes:** Prefer explicit `alias`, `import ... only: [...]`, and
`defdelegate` over `use`. Higher-order functions, behaviours, and protocols
are the composition tools; the patterns that operationalize this — Strategy,
Decorator — are in `gof-patterns`. Keep any `__using__` you write tiny and
limited to `import`/`alias`/`@behaviour` setup.

**Over-engineering when:** replacing framework `use` (`use Ecto.Schema`,
`use Oban.Worker`, `use FirmosWeb, :live_view`) with manual wiring. Those are
well-documented, stable conventions; the trap is *your own* deep `use` stacks.

---

## Program to an Interface, not an Implementation

**Intent:** Depend on the *role* a collaborator plays (a contract), not a
concrete module, so implementations can be swapped (real ↔ Mox mock ↔
alternative) without touching consumers.

**Smell:** A context calls `ExAws.S3` or `Req.post!` directly; tests need
the network or `Bypass` for logic that isn't about HTTP.

### Bad

```elixir
defmodule Firmos.Reports do
  def publish(report) do
    ExAws.S3.put_object("reports", report.key, report.bytes) |> ExAws.request!()
  end
end
```

### Refactor

```elixir
defmodule Firmos.BlobStore do
  @callback put(key :: String.t(), body :: binary()) :: :ok | {:error, term()}

  def impl, do: Application.get_env(:firmos, :blob_store, Firmos.BlobStore.S3)
end

defmodule Firmos.Reports do
  def publish(report), do: Firmos.BlobStore.impl().put(report.key, report.bytes)
end

# config/test.exs: config :firmos, blob_store: Firmos.BlobStoreMock
# test_helper.exs: Mox.defmock(Firmos.BlobStoreMock, for: Firmos.BlobStore)
```

**Elixir notes:** The lightest "interface" is a function argument
(`publish(report, put_fun)`). Use a behaviour + config-selected module when
the seam is app-wide (external APIs), and Mox to enforce the contract in
tests. This is the practical sibling of DIP/ISP — see `solid-principles`
for dependency direction and segregation; the contribution here is "define
the seam as the *narrowest role*."

**Over-engineering when:** there is exactly one implementation, no test-double
need, and the dependency is trivial/stable (`Enum`, `Jason`, `Date`, a pure
helper). A behaviour with one impl and no mock is also a YAGNI violation.

---

## Command–Query Separation (CQS)

**Intent:** Every function is either a **command** (changes state) or a
**query** (returns data, no observable side effects) — never both. Queries
become safe to call freely, reorder, cache, and reason about.

**Smell:** A `get_*` function that inserts a row; an Ecto query helper that
also enqueues an Oban job; a "list" function that marks records as seen.

### Bad

```elixir
def get_settings(user) do
  case Repo.get_by(Settings, user_id: user.id) do
    nil -> Repo.insert!(%Settings{user_id: user.id})   # surprise write
    settings -> settings
  end
end
```

### Refactor

```elixir
# Query: pure read
def get_settings(user), do: Repo.get_by(Settings, user_id: user.id)

# Command: explicit write
def ensure_settings(user) do
  Repo.insert(%Settings{user_id: user.id}, on_conflict: :nothing, conflict_target: :user_id)
end
```

**Elixir notes:** Ecto separates the two naturally — a query (`from ...`) is
data with no side effects until handed to `Repo`. Name commands as verbs
(`create_*`, `update_*`, `archive_*`) and queries as `get_*`/`list_*`/`*?`.
Returning `{:ok, struct}` from `Repo.insert/update` is a **combined
command+query that Elixir accepts by convention** — it carries the result and
the error branch; don't fight it.

**Over-engineering when:** splitting idiomatic combined operations
(`Repo.insert` returning `{:ok, record}`, `Map.pop/2`, `Agent.get_and_update/2`,
`INSERT ... RETURNING`). CQS is a default to make side effects visible, not a
prohibition on every useful return value.

---

## Principle of Least Astonishment (POLA)

**Intent:** A function should behave the way its name, arity, and context
lead a reasonable caller to expect. Surprise is a defect even when "correct."

**Smell:** `get_user/1` that creates a user if missing; a `!` function that
returns `{:error, _}` instead of raising; a predicate without `?`; a boolean
positional argument that silently flips behavior.

### Bad

```elixir
def get_config, do: load_from_disk_and_put_env()   # surprising I/O + global mutation
def parse_date(string, strict \\ false), do: ...   # lenient by default?!
def fetch_user!(id), do: Repo.get(User, id)        # "!" but returns nil
```

### Refactor

```elixir
def load_config, do: ...                            # name signals work happens
def parse_date(string, opts \\ []), do: ...         # parse_date(s, strict: true)
def get_user!(id), do: Repo.get!(User, id)          # "!" raises, as convention says
```

**Elixir notes:** Follow the ecosystem's naming contract: `foo!/1` raises,
`foo/1` returns `{:ok, _} | {:error, _}` or `nil`; `fetch_*` returns
`{:ok, _} | :error`; predicates end in `?` (`is_*` is reserved for guards).
Replace boolean flags with keyword options or distinct functions.

**Over-engineering when:** chasing "zero surprise" with hyper-explicit APIs
nobody asked for, or breaking strong Elixir/Phoenix conventions in the name of
your own intuition. The baseline is the *ecosystem's* expectations, not a
personal one.

---

## Fail Fast

**Intent:** Detect invalid state/inputs at the earliest, outermost boundary and
stop loudly — close to the cause — instead of limping on with bad data. In
Elixir this pairs with "let it crash": write the happy path, match what you
expect, and let a supervisor restart the process on the unexpected.

**Smell:** Defensive `|| 0`, `Map.get(x, :y, %{})`, and catch-all `_ ->`
clauses smeared through deep layers; a `nil` that travels three modules
before an `ArithmeticError`.

### Bad

```elixir
def price_with_tax(order) do
  items = (order && order[:items]) || []
  sub = Enum.reduce(items, 0, fn i, acc -> acc + (i[:price] || 0) end)
  sub * (1 + (order[:tax_rate] || 0))     # silently returns 0, hiding the bug
end
```

### Refactor

```elixir
# Boundary: validate external params once with a changeset
def create_order(attrs) do
  %Order{} |> Order.changeset(attrs) |> Repo.insert()
end

# Core: match the shape you trust; anything else raises FunctionClauseError
def price_with_tax(%Order{items: [_ | _] = items, tax_rate: rate})
    when is_number(rate) and rate >= 0 do
  items |> Enum.map(& &1.price) |> Enum.sum() |> Kernel.*(1 + rate)
end
```

**Elixir notes:** Validate at every trust boundary (params, env vars via
`System.fetch_env!/1` in `runtime.exs`, decoded JSON, Oban args) with
changesets or pattern matches, then let internal code assume valid data.
Use `!` functions (`Repo.get!`, `Map.fetch!`) when absence is a bug, and
`{:ok, _}`-style matches in `with` when it's an expected outcome. Don't
`try/rescue` to keep a process alive — that's the supervisor's job.

**Over-engineering when:** re-validating already-validated structs at every
function (paranoia tax), or crashing a batch on *recoverable* per-item errors
that should be returned as `{:error, _}` and logged (Oban will retry the whole
job). Fail fast at *boundaries*; return errors for expected, recoverable
conditions.
