---
name: postgres-dba
description: >-
  Opinionated PostgreSQL schema design for Elixir/Phoenix + Ecto: Ecto
  migrations (`create table`, `add`, `references`, `create constraint`,
  `unique_index`, `execute/2`) and Ecto schemas/changesets that map database
  errors back via `unique_constraint`/`foreign_key_constraint`/
  `check_constraint`. Conventions: snake_case naming, Ecto's default bigint
  `id`, compound primary keys for many-to-many junctions, NOT NULL foreign
  keys with explicit `on_delete` (nullable only with an override comment),
  Postgres enum types + `Ecto.Enum` instead of lookup tables, `text` + CHECK
  instead of varchar, `timestamptz`, STORED generated columns for derived or
  searchable data, JSONB as a document body on a relational spine (never
  EAV), and integrity invariants enforced by the database while business
  logic lives in Phoenix contexts. Use when writing or reviewing an Ecto
  migration or schema, designing tables, naming columns/indexes/constraints,
  choosing enum vs lookup table, modeling many-to-many, choosing JSONB vs
  columns, deciding whether something belongs in a plpgsql function, or
  querying JSONB with `fragment`. Ships copy-ready migration, schema, and
  JSONB-document templates.
---

# PostgreSQL DBA — Opinionated Schema Design for Ecto

The database is the system of record, not a dumb bucket behind Ecto.
Integrity lives in the schema (types, NOT NULL, FKs, CHECKs, UNIQUE,
exclusion constraints); Ecto changesets *surface* those rules as friendly
errors, they don't replace them. Business workflows live in Phoenix
contexts. These are defaults with teeth: deviate deliberately, with a
comment saying why.

## Why: Design for Change

A schema is the hardest thing in any system to change. Consistent naming,
surrogate keys, NOT NULL FKs, enums, and DB-enforced invariants keep
migrations mechanical: you add a column, you don't reshape the world. JSONB
next to a relational spine lets the document side evolve without a
migration. Every rule optimizes for the *next* migration being boring.

## How to use this skill

1. Match the task to a rule below or in the decision guide.
2. Open the matching `references/*.md` — each rule is shown as the Ecto
   migration DSL, the SQL it produces, and the schema/changeset side.
3. Copy the closest file from `templates/` — they already encode every
   convention.
4. Generate migrations with `mix ecto.gen.migration verb_noun` (never
   hand-name the file), then paste the body in.

## Ecto ground rules (apply everywhere)

- **Column types in migrations:** `:text` for strings (`:string` in a
  *migration* is `varchar(255)` — wrong). In the *schema* it is
  `field :x, :string`. Money is `:integer` cents or `:numeric`, never float.
- **Timestamps:** Ecto's `:utc_datetime`/`:naive_datetime` migration types
  map to `timestamp` **without** time zone. Always ask for `timestamptz`:
  migration `timestamps(type: :timestamptz, default: fragment("now()"))`,
  schema `timestamps(type: :utc_datetime_usec)`. Better: set
  `config :firmos, Firmos.Repo, migration_timestamps: [type: :timestamptz]`
  once. Ecto's `inserted_at` replaces `created_at` — don't fight it.
- **Every DB constraint gets a changeset twin** (`unique_constraint/3`,
  `foreign_key_constraint/3`, `check_constraint/3`,
  `exclusion_constraint/3`) so a violation becomes `{:error, changeset}`
  instead of a raised `Ecto.ConstraintError`.
- **Programmatic fields** (`customer_id` set by the context, generated
  columns) are never in `cast/3`.
- **Raw DDL** (`CREATE TYPE`, functions, extensions) goes through
  `execute(up_sql, down_sql)` so `change/0` stays reversible.

## The hard rules (non-negotiable defaults)

1. **Naming is `snake_case`, lowercase, unquoted.** Tables plural
   (`orders`), columns singular, schema modules singular
   (`Firmos.Sales.Order`). Index and FK names use Ecto's defaults
   (`orders_customer_id_index`, `orders_customer_id_fkey`) so changeset
   helpers find them without `name:`; CHECKs are always named
   `<table>_<rule>`. See `references/naming.md`.

2. **Every base table has Ecto's default `id` (`bigserial primary key`).**
   `create table(:orders)` already does it — don't override it, don't
   downgrade to `serial`. Natural keys get a `unique_index`, never the PK.
   UUID only with a written reason. See `references/keys.md`.

3. **Many-to-many uses a compound primary key, not a surrogate.**
   `create table(:groups_users, primary_key: false)` with both
   `references(...)` columns `primary_key: true`; schema
   `@primary_key false`, parents use `many_to_many ..., join_through:`.
   See `references/keys.md`.

4. **Foreign keys are `null: false` by default, `on_delete` always
   explicit** (`:delete_all`, `:restrict`, `:nilify_all`; never the
   implicit `:nothing`). A nullable FK carries a
   `# nullable-fk: <reason>` comment in the migration. No comment, no
   nullable FK. See `references/keys.md`.

5. **Prefer a Postgres enum type over a lookup table** for small, stable,
   code-driven sets: `execute("CREATE TYPE ...", "DROP TYPE ...")` in the
   migration + `field :status, Ecto.Enum, values: [...]` in the schema.
   Lookup tables only when values carry data, are user-edited, or churn.
   See `references/enums.md`.

6. **Derived data you filter, sort, or search on is a STORED generated
   column** — `add :x, :type, generated: "ALWAYS AS (...) STORED"` — not a
   trigger and not changeset code. Schema field is
   `read_after_writes: true, writable: :never`. See
   `references/generated-columns.md`.

7. **Business logic lives in Phoenix contexts (`Ecto.Multi` /
   `Repo.transact`); integrity invariants live in the database.**
   Constraints that must hold for every writer are CHECK/FK/UNIQUE/EXCLUDE.
   `plpgsql` functions are reserved for genuinely set-based operations or
   cross-writer invariants a constraint can't express, created via
   `execute/2` with up/down. See `references/functions.md`.

8. **JSONB is a document body on a relational spine, used on purpose.**
   Keys, FKs, and hot fields are real (or generated) columns; the open
   remainder is `:map` (`jsonb`), GIN-indexed and CHECK-validated, typed in
   Elixir with `embeds_one`/`embedded_schema` when the shape is known.
   Query with `fragment("? @> ?", ...)` — `?` params, never interpolation.
   No EAV. See `references/jsonb.md`.

## Querying

Use named bindings and pass every value as a parameter:

```elixir
from(o in Order, as: :order)
|> join(:inner, [order: o], c in assoc(o, :customer), as: :customer)
|> where([order: o], o.status == :paid)
|> where([customer: c], fragment("? @> ?", c.preferences, ^%{"newsletter" => true}))
```

`fragment` strings are literal SQL with `?` placeholders; never build them
with string interpolation.

## Decision guide

| Situation | Rule | Reference |
|---|---|---|
| Naming a table, column, index, constraint, schema module | 1 | `references/naming.md` |
| Primary key / natural key | 2 | `references/keys.md` |
| Many-to-many | 3 | `references/keys.md` |
| FK nullability and `on_delete` | 4 | `references/keys.md` |
| Status / role / kind column | 5 | `references/enums.md` |
| Adding/removing an enum value | 5 | `references/enums.md` |
| Derived column, full-text search | 6 | `references/generated-columns.md` |
| Multi-row/multi-table write | 7 (context + `Ecto.Multi`) | `references/functions.md` |
| Rule that must hold for every writer | 7 (constraint first) | `references/functions.md` |
| Open-ended attributes, querying/updating JSONB | 8 | `references/jsonb.md` |
| EAV / "custom fields" temptation | 8 (JSONB, not EAV) | `references/jsonb.md` |

## Templates

- `templates/migration.exs` — Ecto migration skeleton: enum type via
  `execute/2`, table with NOT NULL FKs + explicit `on_delete`, annotated
  nullable FK, named CHECKs, generated column, compound-PK junction,
  `timestamptz` timestamps, and an optional plpgsql function with up/down.
- `templates/schema.ex` — the matching Ecto schemas + changesets
  (`Ecto.Enum`, generated field, junction, every constraint mapped).
- `templates/schema.sql` — the SQL that migration produces; reference for
  reviewing DDL and `psql` sessions.
- `templates/function.sql` — plpgsql house style for the rare function
  that earns its place (see Rule 7).
- `templates/jsonb-document.sql` / `templates/jsonb-document.exs` — the
  hybrid spine + document pattern in SQL, and its Ecto migration, schema
  (embedded schema), and query/update idioms.

## What this skill will not do

- Bless `:string` in a migration (`varchar(255)`) — use `:text`, plus a
  CHECK if length matters.
- Bless `timestamp` without time zone — use `timestamptz`.
- Bless changeset-only validation as integrity — `validate_*` is UX; the
  database constraint is the rule.
- Bless `on_delete: :nothing` by omission, soft FKs "by convention", or
  app-side cascades.
- Bless triggers where a generated column or CHECK does the job.
- Bless EAV tables, or string-interpolated `fragment` SQL.
