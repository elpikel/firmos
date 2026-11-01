# Enums vs Lookup Tables

Most lookup tables are a join, an extra migration, and an integrity gap
(nothing stops a typo'd `status_id`) bought to model a list that changes
once a year. For small, stable, code-driven sets, use an enum.

## Ecto.Enum vs a Postgres enum type

`Ecto.Enum` is an Elixir-side type: it casts strings to atoms and rejects
unknown values *in the changeset*. It can sit on top of either column type:

| Column | DB rejects `'shppd'`? | Ordering | Changing values |
|---|---|---|---|
| `text` + `Ecto.Enum` | **no** — any writer (psql, backfill, `update_all`, Oban) can insert garbage | alphabetical | edit the atom list only |
| `text` + CHECK + `Ecto.Enum` | yes | alphabetical | edit list + replace CHECK |
| **Postgres enum type + `Ecto.Enum`** | **yes** | declaration order | `ALTER TYPE` migration + list |

**Default: Postgres enum type + `Ecto.Enum`.** The database owns the
allowed set (integrity holds for every writer); `Ecto.Enum` gives atoms and
changeset errors. The cost is a migration per new value, which is the
right amount of ceremony for a code-driven set.

## Default: Postgres enum + Ecto.Enum

```elixir
def change do
  execute(
    "CREATE TYPE order_status AS ENUM ('pending', 'paid', 'shipped', 'delivered', 'cancelled')",
    "DROP TYPE order_status"
  )

  create table(:orders) do
    add :status, :order_status, null: false, default: "pending"
  end
end
```

```sql
CREATE TYPE order_status AS ENUM ('pending', 'paid', 'shipped', 'delivered', 'cancelled');
CREATE TABLE orders (id bigserial PRIMARY KEY, status order_status NOT NULL DEFAULT 'pending');
```

```elixir
schema "orders" do
  field :status, Ecto.Enum,
    values: [:pending, :paid, :shipped, :delivered, :cancelled],  # must match the type
    default: :pending
end
```

`execute/2` must come before `create table` in `change/0` (rollback runs
in reverse: table dropped first, then type). Keep the `values:` list and
the type in sync in the same PR; `Ecto.Enum.values(Order, :status)` is the
app-side source for selects/forms.

Why an enum beats `orders.status_id -> order_statuses(id)`: integrity for
free, readable in every query (`WHERE status = 'shipped'`), sorts in
declaration order, one source of truth.

## When a lookup table is correct

Use a table (default `id`, standard conventions) when **any** holds:

- **The value carries data** — label, color, sort weight, feature flag.
- **End users edit the set at runtime** — admin-managed categories, plans.
- **The set is large or churns** every sprint.
- **You need soft-retirement** (`is_active`) while keeping history; enum
  values can't be removed while referenced.

Otherwise it's an enum.

## Changing an enum safely

- **Add a value.** Since PG12 `ADD VALUE` runs in a transaction, but the
  new value can't be *used* in the same transaction — put it in its own
  migration, separate from any backfill using it:

  ```elixir
  def up, do: execute("ALTER TYPE order_status ADD VALUE IF NOT EXISTS 'returned' AFTER 'delivered'")
  def down, do: :ok  # Postgres has no DROP VALUE; see "Remove" below
  ```

  Then add `:returned` to the `Ecto.Enum` values.
- **Rename:** `execute("ALTER TYPE order_status RENAME VALUE 'cancelled' TO 'voided'", "ALTER TYPE order_status RENAME VALUE 'voided' TO 'cancelled'")`.
- **Remove:** no `DROP VALUE`. Recurring removals mean it should have been
  a lookup table. The escape hatch (in `up/0`, table briefly locked):

  ```elixir
  execute("CREATE TYPE order_status_new AS ENUM ('pending','paid','shipped','delivered')")
  execute("ALTER TABLE orders ALTER COLUMN status DROP DEFAULT")
  execute("ALTER TABLE orders ALTER COLUMN status TYPE order_status_new USING status::text::order_status_new")
  execute("ALTER TABLE orders ALTER COLUMN status SET DEFAULT 'pending'")
  execute("DROP TYPE order_status")
  execute("ALTER TYPE order_status_new RENAME TO order_status")
  ```

## Anti-pattern: `Ecto.Enum` on a bare `:text` column

It validates in changesets only; `Repo.update_all`, `Repo.insert_all`,
SQL backfills, and other services bypass it. If you truly can't use a type
(see below), at minimum add
`create constraint(:orders, :orders_status_valid, check: "status IN (...)")`.

## When to deviate

- **Set shared with an independently deployed service:** a lookup table
  can be safer than coordinating `ALTER TYPE` timing. Document the trade.
- **Downstream BI tool can't read enum types:** forced lookup table or
  `text` + CHECK; name the tool in a comment.
