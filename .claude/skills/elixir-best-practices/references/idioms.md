# Elixir Idioms — full reference

Each section: **intent**, a **bad** example, the **idiomatic** version,
**notes**, and **when it is over-engineering**. Phoenix/LiveView/HEEx
specifics are in `AGENTS.md`; OTP in `otp.md`; derives in
`protocols-inspect-json.md`.

---

## §1 Tagged tuples are the Result type

**Intent:** an expected failure (not found, invalid input, API down) is a
value, not an exception. `{:ok, value} | {:error, reason}` forces the
caller to decide, and composes with `with` and `case`.

```elixir
# ❌ bad — nil is ambiguous, false loses the reason, raise is for bugs
def find_coupon(code), do: Repo.get_by(Coupon, code: code)
def apply_coupon(cart, code) do
  coupon = find_coupon(code)
  if coupon.expired?, do: raise("expired"), else: ...
end
```

```elixir
# ✅ idiomatic
@spec fetch_coupon(String.t()) :: {:ok, Coupon.t()} | {:error, :not_found}
def fetch_coupon(code) do
  case Repo.get_by(Coupon, code: code) do
    nil -> {:error, :not_found}
    coupon -> {:ok, coupon}
  end
end
```

**Notes:** reasons are atoms (`:not_found`, `:expired`), an
`%Ecto.Changeset{}`, or a domain error struct (`templates/error.ex`) when
the caller needs data. Use `fetch_*` for `{:ok, _}|{:error, _}`, `get_*`
for `value | nil`, `get_*!` for raise — the stdlib naming convention
(`Map.fetch/2`, `Map.get/2`, `Map.fetch!/2`). Functions that cannot fail
return the bare value — don't wrap in `{:ok, _}` for ceremony.

**Over-engineering:** wrapping pure, total functions in `{:ok, _}`.

---

## §2 `with` for chaining fallible steps

**Intent:** flatten a sequence of dependent fallible calls; the first
non-match short-circuits and is returned as-is.

```elixir
# ❌ bad — case pyramid
case Accounts.fetch_user(id) do
  {:ok, user} ->
    case Carts.fetch_cart(user) do
      {:ok, cart} -> case Orders.place(cart) do ... end
      error -> error
    end
  error -> error
end
```

```elixir
# ✅ idiomatic
with {:ok, user} <- Accounts.fetch_user(id),
     {:ok, cart} <- Carts.fetch_cart(user),
     {:ok, order} <- Orders.place(cart) do
  {:ok, order}
end
```

**Notes:** keep `else` clauses rare — prefer each step returning a
meaningful `{:error, reason}` so `else` isn't needed. If you need `else`
to tell steps apart, tag them (`{:user, {:ok, user}} <- {:user, ...}`) or
better, return distinct reasons. Bare boolean guards work too:
`true <- cart.items != [] || {:error, :empty_cart}`.

**Over-engineering:** `with` for a single step — use `case`.

---

## §3 Bang functions only where crashing is right

**Intent:** `!` means "I expect this to succeed; if not, it is a bug or
a request that should 404/500". Let it crash only where a crash is the
correct user-visible outcome.

```elixir
# ❌ bad — user input reaches a bang; a typo is a 500 with stacktrace
def handle_event("apply", %{"code" => code}, socket) do
  coupon = Repo.get_by!(Coupon, code: code)
  ...
```

```elixir
# ✅ idiomatic
def handle_event("apply", %{"code" => code}, socket) do
  case Carts.apply_coupon(socket.assigns.cart, code) do
    {:ok, cart} -> {:noreply, assign(socket, cart: cart)}
    {:error, :not_found} -> {:noreply, put_flash(socket, :error, "Unknown code")}
  end
end
```

**Where bang is right:** `get_order!(id)` from a route param (Phoenix maps
`Ecto.NoResultsError` to 404), seeds, migrations, tests, and code paths
where failure means a broken invariant. Provide both variants from a
context when both are useful.

---

## §4 Pattern matching in function heads + guards

**Intent:** branch on shape in the head, not with `if`/`cond` in the
body. Each clause documents one case; the compiler warns on unreachable
clauses.

```elixir
# ❌ bad
def price(item) do
  if item.kind == :digital do
    item.base
  else
    if item.weight > 10, do: item.base + 15, else: item.base + 5
  end
end
```

```elixir
# ✅ idiomatic
def price(%Item{kind: :digital, base: base}), do: base
def price(%Item{weight: w, base: base}) when w > 10, do: base + 15
def price(%Item{base: base}), do: base + 5
```

**Notes:** match on structs (`%Item{}`) not bare maps, so wrong types
fail fast with `FunctionClauseError`. Use `defguard` for reusable guards.
Guard predicates are `is_*`; regular predicates end in `?` (AGENTS.md).

**Over-engineering:** splitting a two-line function into five clauses
when a single `case` reads better.

---

## §5 Structs with `@enforce_keys` and `@type t`

**Intent:** a struct is a named, checked shape. `@enforce_keys` makes
missing required fields a construction-time error; `@type t` lets
`@spec`s and Dialyzer talk about it.

```elixir
# ❌ bad — anonymous map, any key may be missing or misspelled
%{sku: "w-1", qty: 2, unit_price: 500}
```

```elixir
# ✅ idiomatic
defmodule Firmos.Carts.LineItem do
  @moduledoc "A SKU with quantity and unit price in cents."
  @enforce_keys [:sku, :quantity, :unit_price]
  defstruct [:sku, :quantity, :unit_price, note: nil]

  @type t :: %__MODULE__{
          sku: String.t(),
          quantity: pos_integer(),
          unit_price: non_neg_integer(),
          note: String.t() | nil
        }

  @spec new(String.t(), pos_integer(), non_neg_integer()) :: {:ok, t()} | {:error, :invalid}
  def new(sku, qty, price) when is_binary(sku) and qty > 0 and price >= 0,
    do: {:ok, %__MODULE__{sku: sku, quantity: qty, unit_price: price}}

  def new(_, _, _), do: {:error, :invalid}
end
```

**Notes:** Ecto schemas are structs too — still declare `@type t`. Access
struct fields with `struct.field`, never `struct[:field]` (AGENTS.md).
Money is integer cents or `Decimal`, never float.

---

## §6 `@spec` on public functions, Dialyzer-friendly

**Intent:** specs are machine-checked documentation and the cheapest
change-detector Elixir has.

```elixir
# ❌ bad
def list_orders(user, opts \\ []), do: ...
```

```elixir
# ✅ idiomatic
@spec list_orders(User.t(), keyword()) :: [Order.t()]
def list_orders(%User{} = user, opts \\ []), do: ...
```

**Notes:** prefer precise types (`pos_integer()`, `Order.t()`,
`:pending | :paid`) over `any()`/`term()`. Spec the error reasons:
`{:error, :not_found | Ecto.Changeset.t()}`. Define `@type`s for unions
used in several specs. Private functions don't need specs unless tricky.
Elixir's gradual set-theoretic type checker uses patterns/guards; specs
still matter for docs and Dialyzer.

**Over-engineering:** specs on test helpers and one-line private funs.

---

## §7 Never `String.to_atom/1` on input

**Intent:** atoms are never garbage-collected; converting user input
leaks memory until the VM dies.

```elixir
# ❌ bad
order_by = String.to_atom(params["sort"])
```

```elixir
# ✅ idiomatic — explicit whitelist
@sortable %{"name" => :name, "price" => :price, "inserted_at" => :inserted_at}
def parse_sort(param), do: Map.get(@sortable, param, :inserted_at)
```

**Notes:** `String.to_existing_atom/1` is acceptable only when the set is
already bounded (it raises on unknown input — wrap it). Ecto's
`Ecto.Enum` handles atom-backed columns safely. Same rule for
`Jason.decode(keys: :atoms)` — use `keys: :atoms!` or string keys.

---

## §8 Contexts are the boundary — web never calls Repo

**Intent:** a context (`Firmos.Carts`) is the public API of a domain.
Controllers and LiveViews call it; only contexts touch `Repo` and
schemas' internals. This is the seam that lets storage, rules and UI
change independently.

```elixir
# ❌ bad — LiveView knows about Repo, queries and preloads
def mount(_, _, socket) do
  items = Repo.all(from i in Item, where: i.cart_id == ^id) |> Repo.preload(:product)
  ...
```

```elixir
# ✅ idiomatic
def mount(_, _, socket) do
  cart = Carts.get_cart!(socket.assigns.current_scope, id)
  {:ok, stream(socket, :items, cart.items)}
end
```

**Notes:** context functions take the caller's scope/user explicitly
(Phoenix 1.8 `current_scope`) for authorization. Contexts may call each
other's public functions, never each other's schemas' `Repo` queries.
Keep the context file thin by delegating to internal modules
(`Firmos.Carts.Pricing`) — the context stays the entry point.

**Over-engineering:** a context per table. Group by domain capability.

---

## §9 Changesets are boundary validation

**Intent:** untrusted params enter the domain only via `cast` +
`validate_*` + constraints. The changeset is both validation and the
error value returned to the web layer (forms render it via `to_form/1`).

```elixir
# ❌ bad — hand validation in the controller, programmatic fields cast
def create(conn, %{"item" => p}) do
  if p["quantity"] && String.to_integer(p["quantity"]) > 0 do
    Repo.insert!(%Item{} |> cast(p, [:sku, :quantity, :cart_id]))
```

```elixir
# ✅ idiomatic — in the schema module
def changeset(item, attrs) do
  item
  |> cast(attrs, [:sku, :quantity])
  |> validate_required([:sku, :quantity])
  |> validate_number(:quantity, greater_than: 0)
  |> unique_constraint([:cart_id, :sku])
end

# in the context — programmatic fields set explicitly, not cast
def add_item(%Cart{} = cart, attrs) do
  %Item{cart_id: cart.id} |> Item.changeset(attrs) |> Repo.insert()
end
```

**Notes:** pair every DB constraint with a `*_constraint/3` so violations
become changeset errors, not exceptions. Use `Ecto.Changeset.get_field/2`
to read; separate changesets per use case (`registration_changeset`,
`password_changeset`). For non-persisted input use an embedded/schemaless
changeset.

---

## §10 Named bindings in queries

**Intent:** positional bindings break when a join is added or reordered.
Named bindings make composable query fragments robust.

```elixir
# ❌ bad
from o in Order, join: c in assoc(o, :customer), where: c.active and o.total > 0
```

```elixir
# ✅ idiomatic
def base_query, do: from(o in Order, as: :order)

def with_active_customer(query) do
  query
  |> join(:inner, [order: o], c in assoc(o, :customer), as: :customer)
  |> where([customer: c], c.active)
end

def paid(query), do: where(query, [order: o], o.status == :paid)
```

**Notes:** use `has_named_binding?/2` to make joins idempotent. Use a
subquery when you need to limit before aggregating. Always pin (`^`)
interpolated values — never build fragments from strings.

---

## §11 Avoid N+1 with preloads

**Intent:** accessing an unloaded association raises
`Ecto.Association.NotLoaded` in templates, and preloading per row is a
query per row. Preload once, in the context.

```elixir
# ❌ bad — one query per order
for order <- Repo.all(Order), do: Repo.preload(order, :items)
```

```elixir
# ✅ idiomatic — separate preload query (2 queries total)
Order |> Repo.all() |> Repo.preload(items: :product)

# or join-preload when you also filter on the association (1 query)
from(o in Order, as: :order,
  join: i in assoc(o, :items), as: :item,
  where: i.sku == ^sku,
  preload: [items: i]
)
```

**Notes:** expose preloads via the context (`get_cart!(id, preload:
[:items])` or a dedicated function), not from the LiveView. Use
`Repo.aggregate`/`select` for counts instead of loading rows.

---

## §12 `Ecto.Multi` for all-or-nothing writes

**Intent:** multiple writes that must succeed together run in one
transaction, with named steps you can pattern-match on failure.

```elixir
# ✅ idiomatic
Ecto.Multi.new()
|> Ecto.Multi.insert(:order, Order.changeset(%Order{}, attrs))
|> Ecto.Multi.update_all(:clear_cart, fn _ -> clear_cart_query(cart) end, [])
|> Repo.transact()
|> case do
  {:ok, %{order: order}} -> {:ok, order}
  {:error, :order, changeset, _changes} -> {:error, changeset}
end
```

**Notes:** for simple cases `Repo.transact(fn -> with ... end)` reads
better (Ecto 3.13+; `Repo.transaction/1` on older versions). Never call
external HTTP APIs inside a transaction — do it before or enqueue after.

---

## §13 Domain errors: atoms first, structs when you need data

**Intent:** error reasons should be pattern-matchable and carry exactly
the data the caller needs.

- `{:error, :not_found}` — the default; cheap and matchable.
- `{:error, %Ecto.Changeset{}}` — validation failures (forms render it).
- `{:error, %Firmos.Error{reason: :insufficient_stock, details: %{...}}}`
  — when the caller needs structured data. Use `defexception` so the same
  struct can be raised from a bang variant (`templates/error.ex`).

**Notes:** never return `{:error, "some string"}` — strings aren't
matchable and get localized/reworded. Don't `rescue` to control flow;
rescue only at boundaries wrapping third-party code that raises.

---

## §14 External services: behaviour + Req + Mox

**Intent:** the domain depends on a behaviour (a contract), not on HTTP.
Production uses a `Req` implementation; tests use a Mox mock of the same
behaviour. Changing the vendor touches one module.

```elixir
# ❌ bad — HTTP in the context, untestable without the network
def charge(order), do: HTTPoison.post!("https://api.pay/...", ...)
```

```elixir
# ✅ idiomatic — see templates/behaviour_adapter.ex
defp gateway, do: Application.fetch_env!(:firmos, :payment_gateway)
def charge(order), do: gateway().charge(order.total, order.currency)
```

**Notes:** Req only (AGENTS.md) — no HTTPoison/Tesla/httpc. Translate
HTTP status/transport errors to domain reasons inside the adapter; never
let `%Req.Response{}` escape. Set `retry`/`receive_timeout` explicitly.
Add `{:mox, "~> 1.2", only: :test}` when the first behaviour is added.

---

## §15 Configuration at runtime

**Intent:** releases compile once and run in many environments.
Environment-specific values and secrets are read at boot, not compile time.

```elixir
# ❌ bad — baked in at compile time; secret committed to config.exs
@api_key Application.get_env(:firmos, :api_key)
```

```elixir
# ✅ idiomatic — config/runtime.exs
if config_env() == :prod do
  config :firmos, Firmos.Payments.Stripe,
    api_key: System.fetch_env!("STRIPE_API_KEY")
end

# in code — read at call time
defp api_key, do: Application.fetch_env!(:firmos, Firmos.Payments.Stripe)[:api_key]
```

**Notes:** `config/config.exs` + `dev/test/prod.exs` hold compile-time
and static settings (adapter module choice, feature defaults).
`Application.compile_env/3` is the explicit form when compile time is
really intended. `fetch_env!` fails at boot rather than at first use.

---

## §16 Logger with metadata, never struct dumps

**Intent:** structured, greppable logs that cannot leak secrets.

```elixir
# ❌ bad — dumps the whole struct (tokens, PII) into a string
Logger.info("checkout failed for #{inspect(user)}: #{inspect(error)}")
```

```elixir
# ✅ idiomatic
Logger.metadata(user_id: user.id, cart_id: cart.id)
Logger.warning("checkout failed", reason: reason)
```

**Notes:** set request-wide metadata once (plug / `on_mount`) and add
keys to the formatter's `metadata:` list in config. Use levels
deliberately (`debug` noisy, `info` lifecycle, `warning` recoverable,
`error` needs attention). Pass functions for expensive messages:
`Logger.debug(fn -> ... end)`. If a struct does get inspected, its
`@derive Inspect` rule is the safety net (`protocols-inspect-json.md`);
also keep secrets in `:filter_parameters`.
