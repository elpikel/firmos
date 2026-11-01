# Creational Patterns

Patterns that abstract the instantiation process so a system is independent of
how its values are created, composed, and represented. In Elixir there are no
constructors or classes — "creating an object" means building a struct or
choosing which module will handle the work. Most of these patterns collapse
into plain functions plus behaviours.

---

## Factory Method

Define an interface for creating a value, but let a variant decide which
concrete thing to create.

**Elixir shape**: a function that returns a struct (`new/1`), or a function
that picks an implementation module from data or config. No subclassing.

**When to use**: the caller shouldn't know which concrete struct/module it
gets; the choice depends on input or config.

**When not to**: there is only one product type — just build the struct
(`%Truck{}`) or call `Truck.new/1`.

```elixir
defmodule Firmos.Logistics.Transport do
  @callback deliver(map()) :: String.t()

  # The factory method: data in, implementation module out.
  @spec for_route(:road | :sea) :: module()
  def for_route(:road), do: Firmos.Logistics.Truck
  def for_route(:sea), do: Firmos.Logistics.Ship
end

defmodule Firmos.Logistics.Truck do
  @behaviour Firmos.Logistics.Transport
  @impl true
  def deliver(_shipment), do: "Delivered by land in a box."
end

defmodule Firmos.Logistics.Ship do
  @behaviour Firmos.Logistics.Transport
  @impl true
  def deliver(_shipment), do: "Delivered by sea in a container."
end

# Each module lives in its own file (see AGENTS.md: never nest modules).
transport = Firmos.Logistics.Transport.for_route(:sea)
transport.deliver(%{id: 1})
# => "Delivered by sea in a container."
```

**Tests**: ExMachina factories (`insert(:user)`, `build(:order, status:
:paid)` from `test/support/factory.ex`) are the everyday Factory Method in
an Elixir codebase — a named function that hides how a valid struct is made.

---

## Abstract Factory

Provide an interface for creating *families* of related values without
specifying their concrete implementations.

**Elixir shape**: a behaviour whose callbacks create/operate on each member of
the family; one implementation module per family, selected via application
config. This is how Swoosh adapters and Ecto adapters work.

**When to use**: the system must be configured with one of several families
(e.g. cloud providers, storage backends) and members of one family must be
used together.

**When not to**: products rarely change as a set — a single behaviour or a
plain function is enough.

```elixir
defmodule Firmos.Storage do
  @moduledoc "Family: blob store + signed URL generator for one provider."
  @callback put(key :: String.t(), binary()) :: :ok | {:error, term()}
  @callback signed_url(key :: String.t(), ttl :: pos_integer()) :: String.t()

  # The "factory": config chooses the family once.
  defp impl, do: Application.get_env(:firmos, :storage, Firmos.Storage.Local)

  def put(key, data), do: impl().put(key, data)
  def signed_url(key, ttl \\ 300), do: impl().signed_url(key, ttl)
end

defmodule Firmos.Storage.S3 do
  @behaviour Firmos.Storage
  @impl true
  def put(key, data), do: Firmos.Storage.S3Client.put_object(key, data)
  @impl true
  def signed_url(key, ttl), do: Firmos.Storage.S3Client.presign(key, ttl)
end

# config/runtime.exs
# config :firmos, :storage, Firmos.Storage.S3
# config/test.exs
# config :firmos, :storage, Firmos.StorageMock   # Mox.defmock(..., for: Firmos.Storage)
```

---

## Builder

Separate the construction of a complex value from its representation so the
same process can produce different results.

**Elixir shape**: a pipeline of functions that each take and return the value
being built. You already use real builders daily: `Ecto.Changeset`,
`Ecto.Multi`, `Ecto.Query` composition, and `Plug.Conn`.

**When to use**: many optional parts, multi-step or conditional assembly, or
you want to compose fragments (query filters, multi-step transactions).

**When not to**: the value is simple — a struct literal or keyword list is
clearer.

```elixir
defmodule Firmos.Blog.PostQuery do
  import Ecto.Query
  alias Firmos.Blog.Post

  def base, do: from(p in Post, as: :post)

  def published(query), do: where(query, [post: p], not is_nil(p.published_at))

  def by_author(query, nil), do: query
  def by_author(query, author_id), do: where(query, [post: p], p.author_id == ^author_id)

  def newest_first(query), do: order_by(query, [post: p], desc: p.published_at)
end

# Building step by step; each step returns a new query.
import Firmos.Blog.PostQuery

base()
|> published()
|> by_author(params["author_id"])
|> newest_first()
|> Firmos.Repo.all()
```

`Ecto.Multi` is the builder for transactions:

```elixir
Ecto.Multi.new()
|> Ecto.Multi.insert(:order, Order.changeset(%Order{}, attrs))
|> Ecto.Multi.update(:stock, fn %{order: order} -> Stock.decrement(order) end)
|> Firmos.Repo.transaction()
```

---

## Prototype

Create new objects by cloning an existing instance.

**Elixir shape**: essentially free. Data is immutable, so "cloning" is just
updating a copy with the struct update syntax; unchanged fields are shared
structurally, not deep-copied.

**When to use**: you have a well-configured default/template value and want
variants of it (default settings, a base changeset, a test fixture).

**When not to**: never needs ceremony — there is no `clone/1` to write. Note
that PIDs, refs, and ETS tables inside a struct are shared handles, not
copied resources.

```elixir
defmodule Firmos.Shapes.Shape do
  defstruct x: 0, y: 0, color: "black"
end

alias Firmos.Shapes.Shape

original = %Shape{x: 10, y: 20, color: "red"}
copy = %{original | color: "blue"}

original.color # => "red" — the original can't be mutated
copy.color     # => "blue"

# A registry of prototypes is just a map of values:
presets = %{small: %Shape{x: 1, y: 1}, large: %Shape{x: 100, y: 100}}
shape = %{Map.fetch!(presets, :large) | color: "green"}
```

---

## Singleton

Ensure there is only one instance and provide a global access point.

**Elixir shape**: modules are already global and stateless. If you need one
shared *stateful* thing, it's a named process (GenServer/Agent) under the
supervision tree, `:persistent_term` for read-mostly global data, or
Application env for configuration.

**When to use (rarely)**: exactly one coordinating process must exist (a rate
limiter, a cache owner, a connection pool) or a read-hot constant computed at
boot.

**When not to**: most cases. A pure module needs no instance at all. A named
GenServer serializes every call through one mailbox — on a hot path it is a
bottleneck and a single point of failure. Prefer ETS (read concurrency) or
`:persistent_term` for read-heavy data; prefer passing config as arguments
for testability.

```elixir
# 1) Stateful singleton: a named process, started once by the supervisor.
defmodule Firmos.RateLimiter do
  use GenServer

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  def hit(key), do: GenServer.call(__MODULE__, {:hit, key})

  @impl true
  def init(_opts), do: {:ok, %{}}

  @impl true
  def handle_call({:hit, key}, _from, counts) do
    counts = Map.update(counts, key, 1, &(&1 + 1))
    {:reply, Map.fetch!(counts, key), counts}
  end
end

# lib/firmos/application.ex children: [Firmos.RateLimiter, ...]

# 2) Read-hot global data: :persistent_term (writes are expensive — boot-time only).
:persistent_term.put({Firmos, :feature_flags}, load_flags())
:persistent_term.get({Firmos, :feature_flags})

# 3) Configuration: Application env.
Application.fetch_env!(:firmos, :base_url)
```

In tests, start such processes with `start_supervised!/1`, and avoid
depending on a globally named process when you can pass a `:name` option.
