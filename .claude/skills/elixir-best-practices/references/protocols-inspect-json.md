# The `@derive` convention — `Inspect`, `Jason.Encoder`, `String.Chars`

**Rule: every struct that may be logged, rendered, or serialized declares
its external representation explicitly with `@derive`.** This is the
Elixir analogue of a "`toString()`/`toJSON()` on every class" rule.

## Why, and why mandatory

| | `Inspect` | `Jason.Encoder` | `String.Chars` |
|---|---|---|---|
| Audience | developers (logs, IEx, error reports, crash dumps) | machines (JSON APIs, PubSub payloads, external systems) | humans (`"#{x}"`, `to_string/1`) |
| Called by | `inspect/2`, Logger, crash reports, `IO.inspect` | `Jason.encode/1`, Phoenix `json/2` | interpolation, `to_string/1` |
| Default if absent | prints **every field**, including secrets | raises `Protocol.UndefinedError` (or, with a blanket derive, encodes every field) | raises `Protocol.UndefinedError` |

The deeper reason is **information hiding**. Fields are an implementation
detail. Without explicit rules, every consumer — logs, APIs, crash
reports — is coupled to the internal shape, so adding a field silently
changes the wire format or leaks a secret into a log aggregator. Deriving
with `only:`/`except:` makes the external representation an explicit,
reviewable contract.

## The contract

**`Inspect`**
- Derive `{Inspect, except: [...]}` (or `only:`) on any struct holding
  secrets: password hashes, tokens, API keys, full card numbers, PII.
  Hidden fields print as `#Firmos.Accounts.User<id: 1, email: ..., ...>`.
- Virtual fields like `:password` must be excluded too — they hold
  plaintext between `cast` and hashing.
- Ecto schemas: `@derive {Inspect, except: [...]}` goes **before**
  `schema "..."`. Ecto's `redact: true` field option does the same per
  field and is equally acceptable — pick one style per schema.

**`Jason.Encoder`**
- Always `only: [...]` — an allow-list. Never `@derive Jason.Encoder`
  bare and never `except:` (new fields would leak by default).
- Never include `__meta__`, unloaded associations, or secrets.
  `Ecto.Association.NotLoaded` will raise when encoded — that is a sign
  you need a preload or an explicit view.
- Treat the `only:` list as a public API: renames are breaking changes.
- For API responses prefer an explicit JSON view module
  (`FirmosWeb.OrderJSON.show/1`) that builds the map; derive
  `Jason.Encoder` for structs that cross boundaries on their own
  (PubSub, embedded JSON columns, logs in JSON format).

**`String.Chars`**
- Implement only for **value-like** structs with an obvious textual form
  (`Money`, `Email`, `Sku`). Short, single line, total — never raises.
- Do not implement it for entities just to make interpolation work —
  log `id`s via metadata instead (idioms.md §16).

## Copy-ready pattern

```elixir
defmodule Firmos.Accounts.User do
  use Ecto.Schema

  @derive {Inspect, except: [:password, :hashed_password, :api_token]}
  @derive {Jason.Encoder, only: [:id, :email, :name, :inserted_at]}
  schema "users" do
    field :email, :string
    field :name, :string
    field :password, :string, virtual: true
    field :hashed_password, :string
    field :api_token, :string
    timestamps(type: :utc_datetime)
  end
end
```

```elixir
defmodule Firmos.Money do
  @enforce_keys [:amount, :currency]
  @derive {Jason.Encoder, only: [:amount, :currency]}
  defstruct [:amount, :currency]

  @type t :: %__MODULE__{amount: integer(), currency: String.t()}

  defimpl String.Chars do
    def to_string(%{amount: a, currency: c}) do
      "#{div(a, 100)}.#{a |> rem(100) |> Integer.to_string() |> String.pad_leading(2, "0")} #{c}"
    end
  end
end
```

Custom `Inspect` (rare — prefer derive):

```elixir
defimpl Inspect, for: Firmos.Payments.Card do
  import Inspect.Algebra
  def inspect(card, opts), do: concat(["#Card<", to_doc("**** " <> card.last4, opts), ">"])
end
```

## Edge cases

- **Nested structs**: each struct needs its own derive; `only:` of the
  parent does not redact the child.
- **Dates**: `DateTime`/`Date` encode to ISO 8601 automatically.
- **Decimals**: `Decimal` encodes as a string — document it for clients.
- **Changesets**: `inspect(changeset)` shows `changes` and `params`;
  the schema's `Inspect` derive redacts the data struct but **params are
  raw** — never log a changeset from a password/token form.
- **Request params**: add secret keys to `config :phoenix,
  :filter_parameters` so Phoenix logs `[FILTERED]`.

## Testing the rule

One test per sensitive struct, in the schema's test file:

```elixir
test "inspect hides secrets" do
  user = %User{email: "a@b.c", hashed_password: "secret-hash"}
  refute inspect(user) =~ "secret-hash"
end

test "JSON exposes only public fields" do
  user = %User{id: 1, email: "a@b.c", hashed_password: "h"}
  assert user |> Jason.encode!() |> Jason.decode!() |> Map.keys() |> Enum.sort() ==
           ["email", "id", "inserted_at", "name"]
end
```
