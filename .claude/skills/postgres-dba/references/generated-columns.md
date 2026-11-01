# Generated Columns

A generated column is computed by the database from other columns in the
same row. Use it to make derived data *queryable and indexable* without a
trigger, without changeset code, and without drift.

The discipline: **don't store what you can compute for free; do store
what you filter, sort, join, or search on.**

## STORED, always

```elixir
create table(:order_items) do
  add :order_id, references(:orders, on_delete: :delete_all), null: false
  add :quantity, :integer, null: false
  add :unit_cents, :integer, null: false
  add :line_cents, :integer, generated: "ALWAYS AS (quantity * unit_cents) STORED"
end

create constraint(:order_items, :order_items_quantity_positive, check: "quantity > 0")
create constraint(:order_items, :order_items_unit_cents_nonneg, check: "unit_cents >= 0")
```

```sql
CREATE TABLE order_items (
  id         bigserial PRIMARY KEY,
  order_id   bigint  NOT NULL REFERENCES orders (id) ON DELETE CASCADE,
  quantity   integer NOT NULL,
  unit_cents integer NOT NULL,
  line_cents integer GENERATED ALWAYS AS (quantity * unit_cents) STORED
);
ALTER TABLE order_items ADD CONSTRAINT order_items_quantity_positive CHECK (quantity > 0);
```

Schema side — the DB owns the value, Ecto only reads it:

```elixir
field :line_cents, :integer, read_after_writes: true, writable: :never
```

- `writable: :never` (Ecto 3.12+) keeps it out of INSERT/UPDATE even if
  someone `put_change`s it; never list it in `cast/3`.
- `read_after_writes: true` adds it to `RETURNING`, so the struct from
  `Repo.insert/update` has the computed value without a reload.
- `line_cents` cannot disagree with `quantity * unit_cents` — there is no
  code path that could make it.

## The canonical use: full-text search

Do not maintain a `tsvector` with a trigger. Generate it.

```elixir
add :search, :tsvector,
  generated: """
  ALWAYS AS (
    setweight(to_tsvector('english', coalesce(title, '')), 'A') ||
    setweight(to_tsvector('english', coalesce(body, '')), 'B')
  ) STORED
  """

create index(:articles, [:search], using: :gin)
```

Ecto has no `tsvector` type; don't map the column in the schema at all
(or use `load_in_query: false` if you must). Query it with a parameterized
fragment:

```elixir
from(a in Article, as: :article)
|> where([article: a], fragment("? @@ websearch_to_tsquery('english', ?)", a.search, ^term))
```

## Good uses

- **Money/quantity math** you filter or aggregate on (`line_cents`).
- **Search vectors** (above).
- **Normalized lookup forms**: `lower(email)` as `email_normalized` with a
  `unique_index` → case-insensitive uniqueness enforced by the DB;
  `unique_constraint(:email, name: :users_email_normalized_index)` maps the
  error back onto `:email`. (Or use the `citext` extension.)
- **Extracted JSONB hot fields** — see `jsonb.md`.
- **Cheap immutable classification**: `total_cents >= 100000` is fine;
  `due_at < now()` is not (see below).

## Hard constraints (errors, not style)

- The expression must be **`IMMUTABLE`**: no `now()`, `current_user`, or
  non-immutable functions. "Overdue right now" is a query predicate.
- It **cannot reference another generated column** and has no `DEFAULT`.
- You **cannot write it** — `writable: :never` makes Ecto agree.
- Adding one to an existing table rewrites the table; on large hot tables
  plan the lock.

## Don't store what's free

A generated column you never filter/sort/index on is just a wider row —
compute it in the `select` or a virtual field instead. Test: *would you
index it or filter by it?* If no, it doesn't earn a column.

## Generated column vs alternatives

| Need | Use |
|---|---|
| Derived, filtered/indexed, immutable expr | **Generated column** |
| Derived, display only | `select` expr / `field ..., virtual: true` |
| Needs other rows or non-immutable input | Query / view / context function |
| "Keep two columns in sync on write" | **Generated column** (not a trigger, not changeset) |
| Multi-row side effects on write | Context + `Ecto.Multi`; trigger only as last resort |

## When to deviate

- An extremely wide, write-hot table where the stored bytes matter more
  than read convenience: compute at query time. Measure first.
