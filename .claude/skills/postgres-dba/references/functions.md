# Business Logic vs Integrity: Contexts, Constraints, and (Rarely) plpgsql

Split the problem in two:

- **Integrity invariants** — facts that must be true no matter who writes
  (a backfill, `psql`, an Oban job, another service): **the database owns
  them** as NOT NULL, FKs, UNIQUE, CHECK, and exclusion constraints.
- **Business logic** — workflows, orchestration, side effects, decisions:
  **a Phoenix context owns it**, composing writes with `Ecto.Multi` or
  `Repo.transact/2`.

`plpgsql` is the exception, not the home of business rules.

## Default: context + transaction, constraints as the walls

```elixir
# lib/firmos/sales.ex
def place_order(%Customer{} = customer, items) do
  Ecto.Multi.new()
  |> Ecto.Multi.insert(:order, Order.create_changeset(%Order{customer_id: customer.id}, %{}))
  |> Ecto.Multi.insert_all(:items, OrderItem, fn %{order: order} -> build_item_rows(order, items) end)
  |> Repo.transact()
end
```

The context is the *front door* (good errors, orchestration, PubSub, Oban
enqueues via `Oban.insert/3` in the same Multi). Constraints are the
*walls*: the changeset maps them to errors, and they still hold when
something skips the context.

```elixir
create constraint(:order_items, :order_items_quantity_positive, check: "quantity > 0")

# multi-row invariant a CHECK can't express: no overlapping bookings per room
execute("CREATE EXTENSION IF NOT EXISTS btree_gist", "")
create constraint(:bookings, :bookings_no_overlap,
  exclude: ~s|gist (room_id WITH =, tstzrange(starts_at, ends_at) WITH &&)|)
```

```elixir
|> check_constraint(:quantity, name: :order_items_quantity_positive)
|> exclusion_constraint(:starts_at, name: :bookings_no_overlap)
```

Changeset `validate_*` functions are UX, not integrity. Every rule that
matters exists in the DB; the changeset may *also* pre-validate it for
nicer messages.

## When a plpgsql function earns its place

Only when one of these is true — and say which in a comment:

- **Genuinely set-based work** that would otherwise round-trip many rows
  through the BEAM (bulk recalculation, ranking, a large `INSERT ...
  SELECT` with logic).
- **An invariant that must hold across all writers** and that no
  constraint can express (e.g. a trigger enforcing a cross-table rule,
  or a deep JSONB merge used by several services).
- **A reusable immutable expression** needed in generated columns or
  indexes.

Not a function: single-row CRUD, anything a CHECK/FK/EXCLUDE can express,
workflow that calls external systems (HTTP, email, Oban), presentation.

## House style (when you do write one)

`plpgsql` only — one language, real exceptions, no `language sql`
one-liners scattered around (measured hot-path deviation allowed, with a
comment).

```sql
CREATE OR REPLACE FUNCTION recalculate_order_totals(p_order_ids bigint[])
RETURNS integer
LANGUAGE plpgsql
VOLATILE                          -- it writes; say so
SECURITY INVOKER                  -- DEFINER only with a written reason
SET search_path = public, pg_temp -- pin it; never trust the caller's path
AS $$
DECLARE
  v_count integer;
BEGIN
  IF p_order_ids IS NULL OR cardinality(p_order_ids) = 0 THEN
    RAISE EXCEPTION 'recalculate_order_totals: order ids required'
      USING errcode = 'check_violation';
  END IF;

  UPDATE orders o                 -- one set-based statement, not a FOR loop
  SET    total_cents = s.total, updated_at = now()
  FROM  (SELECT order_id, sum(line_cents) AS total
         FROM order_items WHERE order_id = ANY (p_order_ids)
         GROUP BY order_id) s
  WHERE  o.id = s.order_id;

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;
```

- **`CREATE OR REPLACE`**, versioned only by migrations; never edited in
  place in production.
- **Honest volatility** (`IMMUTABLE`/`STABLE`/`VOLATILE`) — the planner
  trusts it.
- **`SET search_path`** always; **`SECURITY INVOKER`** by default.
- **Validate args first**, `RAISE EXCEPTION` with a specific message and
  `errcode`.
- **Set-based body.** A `FOR ... LOOP` of single-row writes is the classic
  anti-pattern.
- **Naming:** `verb_noun`, params `p_`, locals `v_` (avoids column
  shadowing). Types match Ecto's keys: `bigint`.

## Shipping it from Ecto

Create it in a migration with explicit up/down (a function body isn't
reversible by `change/0` inference):

```elixir
def up do
  execute("""
  CREATE OR REPLACE FUNCTION recalculate_order_totals(p_order_ids bigint[]) ...
  """)
end

def down do
  execute("DROP FUNCTION IF EXISTS recalculate_order_totals(bigint[])")
end
```

A later change is a new migration with the full new definition in `up`
and the previous definition in `down`.

Call it from the context, parameterized:

```elixir
%Postgrex.Result{rows: [[count]]} =
  Repo.query!("SELECT recalculate_order_totals($1)", [order_ids])
```

A raised `RAISE EXCEPTION` arrives as `%Postgrex.Error{postgres:
%{code: :check_violation, message: msg}}`; rescue it in the context and
return `{:error, reason}` — don't let it leak to the web layer.

## When to deviate

- Logic that must be shared by non-Elixir writers of the same database
  moves toward the DB (function or constraint) — document the other
  writers.
- A measured hot path where a `language sql` function inlines better:
  allowed with the measurement in a comment.
