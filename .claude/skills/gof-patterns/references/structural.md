# Structural Patterns

Patterns concerned with how pieces are composed to form larger structures. In
Elixir, composition happens through behaviours, protocols, recursive data,
function wrapping, and process boundaries — not object graphs.

---

## Adapter

Convert the interface of one module into the interface callers expect.

**Elixir shape**: define a behaviour for what *your* code needs, then write
one adapter module per vendor that translates to the vendor's API. Swoosh
mail adapters and Ecto database adapters are canonical examples. Wrap HTTP
clients built on `Req` behind a behaviour and mock it with Mox in tests.

**When to use**: integrating a third-party API/library whose shape doesn't
match your domain, or when you want to swap/mock the vendor.

**When not to**: you own both sides — just change the function signature.

```elixir
defmodule Firmos.Payments.Processor do
  @callback charge(amount_cents :: pos_integer(), customer_id :: String.t()) ::
              {:ok, String.t()} | {:error, term()}

  def impl, do: Application.get_env(:firmos, :payment_processor, Firmos.Payments.Stripe)
  def charge(amount_cents, customer_id), do: impl().charge(amount_cents, customer_id)
end

defmodule Firmos.Payments.Stripe do
  @behaviour Firmos.Payments.Processor

  # Adapts our cents-based contract to the vendor's HTTP API.
  @impl true
  def charge(amount_cents, customer_id) do
    [base_url: "https://api.stripe.com/v1", auth: {:bearer, api_key()}]
    |> Req.new()
    |> Req.post(url: "/charges", form: [amount: amount_cents, currency: "usd", customer: customer_id])
    |> case do
      {:ok, %Req.Response{status: 200, body: %{"id" => id}}} -> {:ok, id}
      {:ok, %Req.Response{body: body}} -> {:error, body}
      {:error, exception} -> {:error, exception}
    end
  end

  defp api_key, do: Application.fetch_env!(:firmos, :stripe_api_key)
end

# test/test_helper.exs
# Mox.defmock(Firmos.Payments.ProcessorMock, for: Firmos.Payments.Processor)
# test: expect(Firmos.Payments.ProcessorMock, :charge, 1, fn 2599, _ -> {:ok, "ch_1"} end)
```

---

## Bridge

Decouple an abstraction from its implementation so the two can vary
independently.

**Elixir shape**: the abstraction is a module (or protocol over your data)
that takes the implementation module as a parameter; the implementation side
is a behaviour. N abstractions × M implementations = N + M modules.

**When to use**: two orthogonal dimensions would otherwise explode into a
module-per-combination matrix (e.g. *report type* × *output format*).

**When not to**: only one dimension ever varies — a single behaviour is
enough.

```elixir
defmodule Firmos.Reports.Renderer do
  @callback heading(String.t()) :: iodata()
  @callback row([String.t()]) :: iodata()
end

defmodule Firmos.Reports.CSV do
  @behaviour Firmos.Reports.Renderer
  @impl true
  def heading(_title), do: []
  @impl true
  def row(cells), do: [Enum.join(cells, ","), "\n"]
end

defmodule Firmos.Reports.Markdown do
  @behaviour Firmos.Reports.Renderer
  @impl true
  def heading(title), do: ["# ", title, "\n\n"]
  @impl true
  def row(cells), do: ["| ", Enum.join(cells, " | "), " |\n"]
end

# Abstraction side: each report knows *what* to render, not *how*.
defmodule Firmos.Reports.SalesReport do
  def render(sales, renderer) do
    [renderer.heading("Sales") | Enum.map(sales, &renderer.row([&1.region, to_string(&1.total)]))]
  end
end

Firmos.Reports.SalesReport.render(sales, Firmos.Reports.Markdown)
```

---

## Composite

Compose items into tree structures and treat leaves and containers uniformly.

**Elixir shape**: recursive data (structs or tagged tuples nesting
themselves) plus recursive multi-clause functions. No shared base class
needed.

**When to use**: part-whole hierarchies where callers shouldn't care about
leaf vs. container (folders, org charts, nested menus, bill of materials).

**When not to**: the structure is flat, or leaf/container behavior diverges
sharply.

```elixir
defmodule Firmos.Files do
  # A node is either {:file, name, bytes} or {:dir, name, [node]}
  def size({:file, _name, bytes}), do: bytes
  def size({:dir, _name, children}), do: children |> Enum.map(&size/1) |> Enum.sum()

  def names({:file, name, _}), do: [name]
  def names({:dir, name, children}), do: [name | Enum.flat_map(children, &names/1)]
end

tree =
  {:dir, "root",
   [
     {:file, "a.txt", 100},
     {:dir, "sub", [{:file, "b.txt", 50}, {:file, "c.txt", 25}]}
   ]}

Firmos.Files.size(tree) # => 175
```

For hierarchical DB data, use a recursive CTE (`with_cte/3` +
`recursive_ctes(true)`) rather than N+1 recursive queries.

---

## Decorator

Attach additional behavior to a function without changing it.

**Elixir shape**: higher-order functions that take a function and return a
wrapped one; Plug pipelines (each plug decorates the conn handling);
`:telemetry.span/3` around a call. Not the same as attribute-based
"decorator" libraries, which are macros — avoid them for this.

**When to use**: cross-cutting concerns (timing, logging, retries, caching,
auth) that combine in different ways around many calls.

**When not to**: one fixed concern on one function — just write it inline.

```elixir
defmodule Firmos.Wrap do
  require Logger

  def with_retry(fun, attempts \\ 3) do
    fn args ->
      Enum.reduce_while(1..attempts, nil, fn n, _acc ->
        case fun.(args) do
          {:ok, _} = ok -> {:halt, ok}
          {:error, _} = err when n == attempts -> {:halt, err}
          {:error, _} -> {:cont, nil}
        end
      end)
    end
  end

  def with_timing(fun, label) do
    fn args ->
      :telemetry.span([:firmos, label], %{}, fn -> {fun.(args), %{}} end)
    end
  end
end

fetch = (&Firmos.Payments.charge_once/1) |> Firmos.Wrap.with_retry() |> Firmos.Wrap.with_timing(:charge)
fetch.(%{amount: 2599})
```

Plugs are stacked decorators around the endpoint:

```elixir
pipeline :api do
  plug :accepts, ["json"]
  plug FirmosWeb.Plugs.RequireApiKey
end
```

---

## Facade

Provide a unified, simple interface to a set of interfaces in a subsystem.

**Elixir shape**: a **Phoenix context**. `Firmos.Accounts` hides schemas,
queries, `Repo`, changesets, mailers, and Oban jobs behind
`register_user/1`. Controllers and LiveViews call only the context.

**When to use**: give callers (web layer, workers) one entry point and keep
the moving parts private to the context.

**When not to**: don't build a facade over a facade, and don't make contexts
pass-through wrappers that just rename `Repo` calls.

```elixir
defmodule Firmos.Accounts do
  alias Ecto.Multi
  alias Firmos.Accounts.User
  alias Firmos.Repo

  def register_user(attrs) do
    Multi.new()
    |> Multi.insert(:user, User.registration_changeset(%User{}, attrs))
    |> Oban.insert(:welcome_email, fn %{user: user} ->
      Firmos.Workers.WelcomeEmail.new(%{user_id: user.id})
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{user: user}} -> {:ok, user}
      {:error, _step, reason, _changes} -> {:error, reason}
    end
  end
end

# FirmosWeb.UserRegistrationLive just calls Accounts.register_user(params).
```

---

## Flyweight

Share fine-grained values to support large numbers of them efficiently.

**Elixir shape**: much is built in. Atoms are interned once per node;
binaries > 64 bytes are reference-counted and shared between processes;
immutable terms are structurally shared. For explicit sharing, put large
read-mostly data in `:persistent_term` (zero-copy reads) or ETS.

**When to use**: many processes need the same large lookup data (country
tables, compiled regexes, config maps), or millions of records repeat the
same small values.

**When not to**: few values — the runtime already shares what it can. Never
create atoms from user input (`String.to_atom/1`) to "intern" strings: atoms
are never garbage collected.

```elixir
defmodule Firmos.Geo do
  @key {__MODULE__, :countries}

  # Call once at boot (e.g. from Application.start/2).
  def load! do
    countries = :firmos |> Application.app_dir("priv/countries.json") |> File.read!() |> Jason.decode!()
    :persistent_term.put(@key, Map.new(countries, &{&1["code"], &1}))
  end

  # Every process reads the same shared term — no copy into the caller's heap.
  def country(code), do: :persistent_term.get(@key) |> Map.get(code)
end
```

Extrinsic state (the per-use part) stays in the caller: `%{country_code:
"PL", amount: 10}` references the shared intrinsic data by key.

---

## Proxy

Provide a surrogate that controls access to another resource.

**Elixir shape**: a GenServer fronting a resource (serializing access,
caching, holding a connection); `Stream` for lazy evaluation; Ecto
associations, which are `%Ecto.Association.NotLoaded{}` placeholders until
you `preload` them explicitly.

**When to use**: lazy loading, caching, access control, or a remote/expensive
resource that needs a single owner.

**When not to**: no access concern exists — call the function directly. Don't
put a GenServer in front of pure computation; it only adds a bottleneck.

```elixir
# Caching proxy in front of a slow external API.
defmodule Firmos.ExchangeRates do
  use GenServer

  def start_link(_), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  def rate(pair), do: GenServer.call(__MODULE__, {:rate, pair})

  @impl true
  def init(cache), do: {:ok, cache}

  @impl true
  def handle_call({:rate, pair}, _from, cache) do
    case cache do
      %{^pair => rate} ->
        {:reply, rate, cache}

      _ ->
        rate = Firmos.ExchangeRates.Client.fetch!(pair)
        {:reply, rate, Map.put(cache, pair, rate)}
    end
  end
end

# Virtual proxy built into Ecto: associations load only on request.
post = Repo.get!(Post, id)
post.comments # => %Ecto.Association.NotLoaded{} — access is guarded
post = Repo.preload(post, :comments)
```
