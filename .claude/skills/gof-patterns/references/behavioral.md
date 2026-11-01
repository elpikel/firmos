# Behavioral Patterns

Patterns concerned with algorithms and the assignment of responsibilities. In
Elixir, responsibility moves between functions, modules (behaviours), data
types (protocols), and processes (messages) — and several patterns become a
single standard-library construct.

---

## Chain of Responsibility

Pass a request along a chain of handlers until one handles it.

**Elixir shape**: a Plug pipeline (each plug may `halt/1`); `with` for a
chain of steps that short-circuits on the first non-match; `Enum.reduce_while`
over a list of handler functions.

**When to use**: several handlers may deal with a request and the order or
membership varies (auth/validation pipelines, pricing rules, escalation).

**When not to**: exactly one known handler — call it directly.

```elixir
defmodule Firmos.Support.Router do
  @handlers [&__MODULE__.bot/1, &__MODULE__.agent/1, &__MODULE__.manager/1]

  def route(ticket) do
    Enum.reduce_while(@handlers, :unhandled, fn handler, acc ->
      case handler.(ticket) do
        :pass -> {:cont, acc}
        {:handled, _} = result -> {:halt, result}
      end
    end)
  end

  def bot(%{severity: s}) when s < 10, do: {:handled, :bot}
  def bot(_), do: :pass
  def agent(%{severity: s}) when s < 100, do: {:handled, :agent}
  def agent(_), do: :pass
  def manager(_), do: :pass
end

Firmos.Support.Router.route(%{severity: 50})  # => {:handled, :agent}
Firmos.Support.Router.route(%{severity: 999}) # => :unhandled
```

A Plug that halts is the same pattern in the web layer:

```elixir
def call(conn, _opts) do
  if conn.assigns[:current_scope], do: conn, else: conn |> send_resp(401, "") |> halt()
end
```

---

## Command

Encapsulate a request as a value, enabling queuing, logging, and undo.

**Elixir shape**: commands are plain data — a tuple or struct — interpreted
by a function. Oban jobs are serialized commands (args persisted in Postgres,
executed later, retried). `Ecto.Multi` is a list of commands executed
atomically.

**When to use**: you need to queue, persist, retry, audit, or undo work, or
decouple who requests from who executes.

**When not to**: a direct function call suffices and you don't need deferral,
history, or undo.

```elixir
defmodule Firmos.Lights do
  # Commands are data; execute/undo are functions over (state, command).
  def execute(state, {:turn_on, id}), do: Map.put(state, id, :on)
  def execute(state, {:turn_off, id}), do: Map.put(state, id, :off)

  def undo(state, {:turn_on, id}), do: Map.put(state, id, :off)
  def undo(state, {:turn_off, id}), do: Map.put(state, id, :on)
end

history = [{:turn_on, :kitchen}, {:turn_off, :hall}]
state = Enum.reduce(history, %{}, &Firmos.Lights.execute(&2, &1))
state = Firmos.Lights.undo(state, hd(history))
```

Durable command with Oban (workers live in `lib/firmos/workers/`):

```elixir
defmodule Firmos.Workers.SendInvoice do
  use Oban.Worker, queue: :billing, max_attempts: 5

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"invoice_id" => id}}) do
    Firmos.Billing.send_invoice(id)
  end
end

%{invoice_id: invoice.id} |> Firmos.Workers.SendInvoice.new() |> Oban.insert()
```

---

## Interpreter

Define a grammar and an interpreter that evaluates sentences in it.

**Elixir shape**: represent the expression as nested tuples (an AST) and
evaluate it with recursive, pattern-matched function clauses. Elixir's own
`quote`/macros are an interpreter over Elixir AST — powerful, but compile-time
and hard to debug; use them only for true DSLs.

**When to use**: a small, stable grammar evaluated often (filter rules,
pricing formulas, feature-flag conditions stored as JSON).

**When not to**: complex/evolving grammars — use a parser library
(`NimbleParsec`). Never `Code.eval_string/1` user input.

```elixir
defmodule Firmos.Rules do
  # expr :: {:num, n} | {:var, name} | {:add, a, b} | {:mul, a, b} | {:gt, a, b}
  def eval({:num, n}, _env), do: n
  def eval({:var, name}, env), do: Map.fetch!(env, name)
  def eval({:add, a, b}, env), do: eval(a, env) + eval(b, env)
  def eval({:mul, a, b}, env), do: eval(a, env) * eval(b, env)
  def eval({:gt, a, b}, env), do: eval(a, env) > eval(b, env)
end

rule = {:gt, {:mul, {:var, "qty"}, {:num, 10}}, {:num, 100}}
Firmos.Rules.eval(rule, %{"qty" => 12}) # => true
```

---

## Iterator

Access elements of a collection sequentially without exposing its structure.

**Elixir shape**: implement the `Enumerable` protocol for your type and every
`Enum`/`Stream` function works on it. `Stream` gives lazy iteration;
`Repo.stream/2` iterates large result sets inside a transaction without
loading them all.

**When to use**: a custom data structure should work with `Enum`, or you
need lazy/unbounded/paged traversal (API pagination, huge tables).

**When not to**: it's already a list or map — just use `Enum`.

```elixir
# Lazy pagination over an external API.
def all_customers(client) do
  Stream.resource(
    fn -> 1 end,
    fn
      nil -> {:halt, nil}
      page ->
        %{"data" => rows, "next_page" => next} = client.list_customers(page)
        {rows, next}
    end,
    fn _ -> :ok end
  )
end

all_customers(client) |> Stream.filter(& &1["active"]) |> Enum.take(50)

# Large table iteration (must run inside a transaction).
Repo.transaction(fn ->
  from(u in User, as: :user)
  |> where([user: u], u.inserted_at < ^cutoff)
  |> Repo.stream(max_rows: 500)
  |> Stream.each(&Firmos.Accounts.archive/1)
  |> Stream.run()
end)
```

---

## Mediator

Define an object that encapsulates how a set of objects interact.

**Elixir shape**: participants don't hold references to each other; they
talk through Phoenix.PubSub topics, a `Registry`, or a coordinating GenServer
that owns the interaction rules.

**When to use**: many-to-many communication between processes/LiveViews
(chat rooms, collaborative editing, multi-step workflows across services).

**When not to**: few participants — direct function calls are simpler than a
god-process that every message funnels through.

```elixir
defmodule Firmos.Rooms do
  def join(room_id), do: Phoenix.PubSub.subscribe(Firmos.PubSub, topic(room_id))

  def say(room_id, user, text) do
    Phoenix.PubSub.broadcast(Firmos.PubSub, topic(room_id), {:message, user, text})
  end

  defp topic(room_id), do: "room:#{room_id}"
end

# In a LiveView:
def mount(%{"id" => id}, _session, socket) do
  if connected?(socket), do: Firmos.Rooms.join(id)
  {:ok, stream(socket, :messages, [])}
end

def handle_info({:message, user, text}, socket) do
  {:noreply, stream_insert(socket, :messages, %{id: System.unique_integer([:positive]), user: user, text: text})}
end
```

---

## Memento

Capture and externalize an object's internal state so it can be restored.

**Elixir shape**: immutable values *are* snapshots — keep the previous value.
A GenServer can hold a history list in its state. At the persistence level,
event sourcing (store events, rebuild state by folding them) or an audit
table is the durable memento.

**When to use**: undo/redo, checkpoints, rollback of in-memory edits (e.g. a
LiveView editor).

**When not to**: state is large and changes often — store diffs/commands
instead, or rely on DB transactions for rollback.

```elixir
defmodule Firmos.Editor do
  defstruct content: "", history: []

  def write(%__MODULE__{} = ed, text) do
    %{ed | content: ed.content <> text, history: [ed.content | ed.history]}
  end

  def undo(%__MODULE__{history: []} = ed), do: ed
  def undo(%__MODULE__{history: [prev | rest]} = ed), do: %{ed | content: prev, history: rest}
end

%Firmos.Editor{}
|> Firmos.Editor.write("Hello")
|> Firmos.Editor.write(", world")
|> Firmos.Editor.undo()
# => content: "Hello"
```

---

## Observer

Define a one-to-many dependency so dependents are notified when state changes.

**Elixir shape**: Phoenix.PubSub for app events (cluster-wide), `:telemetry`
for metrics/instrumentation events, `Registry` with `dispatch/3` for local
process fan-out. Subscribers are processes receiving messages.

**When to use**: decoupled notifications — LiveViews refreshing on data
change, metrics, audit logging, cache invalidation.

**When not to**: a single known dependent — call it directly. Don't use
PubSub for work that must not be lost; enqueue an Oban job instead.

```elixir
defmodule Firmos.Orders do
  @topic "orders"

  def subscribe, do: Phoenix.PubSub.subscribe(Firmos.PubSub, @topic)

  def update_order(order, attrs) do
    with {:ok, order} <- order |> Order.changeset(attrs) |> Repo.update() do
      Phoenix.PubSub.broadcast(Firmos.PubSub, @topic, {:order_updated, order})
      :telemetry.execute([:firmos, :order, :updated], %{count: 1}, %{status: order.status})
      {:ok, order}
    end
  end
end

# Telemetry observer (attach once at boot):
:telemetry.attach("log-orders", [:firmos, :order, :updated], &MyHandler.handle_event/4, nil)
```

---

## State

Let an object alter its behavior when its internal state changes.

**Elixir shape**: for persisted entities, a status field plus multi-clause
functions that pattern match on it (illegal transitions simply have no
clause). For long-lived processes, `:gen_statem`, or a GenServer whose
callbacks match on a state tag.

**When to use**: behavior depends on state with many state-dependent branches
(order lifecycle, connection handling, approval workflows).

**When not to**: two states / trivial logic — a boolean is fine.

```elixir
defmodule Firmos.Orders.Lifecycle do
  alias Firmos.Orders.Order

  def transition(%Order{status: :draft} = o, :submit), do: {:ok, %{o | status: :pending}}
  def transition(%Order{status: :pending} = o, :pay), do: {:ok, %{o | status: :paid}}
  def transition(%Order{status: :pending} = o, :cancel), do: {:ok, %{o | status: :cancelled}}
  def transition(%Order{status: :paid} = o, :ship), do: {:ok, %{o | status: :shipped}}
  def transition(%Order{status: status}, event), do: {:error, {:invalid_transition, status, event}}
end
```

Persist with `Ecto.Enum` (`field :status, Ecto.Enum, values: [:draft,
:pending, :paid, :shipped, :cancelled]`) and apply via a changeset. Reach for
`:gen_statem` when the *process* has states with timeouts (e.g. a reconnect
loop with backoff).

---

## Strategy

Define a family of algorithms, encapsulate each, and make them
interchangeable.

**Elixir shape**: pass a function (`&Module.fun/1`) or a module implementing
a behaviour. Functions are values, so the pattern is often a single argument.

**When to use**: multiple ways to do one thing chosen at runtime or by
config (pricing, ranking, export formats, notification channels).

**When not to**: one algorithm that never changes. A behaviour is overkill
when a function argument suffices; use a behaviour when the strategy has
several callbacks or must be selected via config/mocked with Mox.

```elixir
defmodule Firmos.Pricing do
  @callback price(cents :: integer()) :: integer()

  def checkout(items, strategy \\ Firmos.Pricing.Regular) do
    items |> Enum.map(& &1.cents) |> Enum.sum() |> strategy.price()
  end
end

defmodule Firmos.Pricing.Regular do
  @behaviour Firmos.Pricing
  @impl true
  def price(cents), do: cents
end

defmodule Firmos.Pricing.BlackFriday do
  @behaviour Firmos.Pricing
  @impl true
  def price(cents), do: div(cents * 70, 100)
end

# Function-value strategy — often all you need:
Enum.sort_by(players, & &1.score, :desc)
```

---

## Template Method

Define the skeleton of an algorithm, deferring some steps to variants.

**Elixir shape**: a behaviour declares the steps as `@callback`s; a public
function in the behaviour module runs the skeleton and calls into the
implementation. Optionally `__using__` injects default step implementations
marked `defoverridable`.

**When to use**: several flows share structure but differ in specific steps
(CSV/JSON/API importers, report generators).

**When not to**: steps vary wildly — prefer Strategy. Be wary of the
`__using__` + `defoverridable` form: it injects code into the caller at
compile time, creating hidden coupling and recompilation chains. Prefer the
explicit skeleton function below; add `__using__` only for genuine defaults.

```elixir
defmodule Firmos.Importer do
  @callback parse(binary()) :: [map()]
  @callback validate(map()) :: {:ok, map()} | {:error, term()}
  @optional_callbacks validate: 1

  # The template: fixed skeleton, variable steps.
  def run(impl, raw) do
    raw
    |> impl.parse()
    |> Enum.map(&validate(impl, &1))
    |> Enum.split_with(&match?({:ok, _}, &1))
  end

  defp validate(impl, row) do
    if function_exported?(impl, :validate, 1), do: impl.validate(row), else: {:ok, row}
  end
end

defmodule Firmos.Importer.CSV do
  @behaviour Firmos.Importer
  @impl true
  def parse(raw), do: raw |> String.split("\n", trim: true) |> Enum.map(&%{line: &1})
end

{ok, errors} = Firmos.Importer.run(Firmos.Importer.CSV, File.read!("users.csv"))
```

---

## Visitor

Add new operations over a set of types without changing those types.

**Elixir shape**: a protocol — define a new protocol and `defimpl` it for
existing structs without touching them. For a closed set of variants, a
multi-clause function over tagged tuples/structs is the lighter idiom.

**When to use**: many unrelated operations over a stable set of types (AST
passes, document export, serialization, pricing per item type).

**When not to**: the set of types changes often and operations are few —
then each new type means updating every protocol/function. Protocol dispatch
is also open-ended; if the set is closed, multi-clause functions give you
clearer errors.

```elixir
defprotocol Firmos.Export.CSVRow do
  @spec to_row(t) :: [String.t()]
  def to_row(item)
end

defimpl Firmos.Export.CSVRow, for: Firmos.Accounts.User do
  def to_row(user), do: [to_string(user.id), user.email]
end

defimpl Firmos.Export.CSVRow, for: Firmos.Orders.Order do
  def to_row(order), do: [to_string(order.id), to_string(order.total_cents)]
end

Enum.map(records, &Firmos.Export.CSVRow.to_row/1)

# Closed set: a multi-clause function is the whole pattern.
def area({:circle, r}), do: :math.pi() * r * r
def area({:rect, w, h}), do: w * h
```
