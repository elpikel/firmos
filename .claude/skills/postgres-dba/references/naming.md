# Naming Conventions

The goal: never quote an identifier in an everyday query. Postgres folds
unquoted identifiers to lowercase, so `snake_case` is the only style that
survives round-trips. Ecto atoms (`:shipped_at`) map 1:1 to these names.

## Rules

- **Case:** `snake_case`, all lowercase. No quoted mixed-case identifiers.
- **Tables:** plural nouns — `orders`, `order_items`. Ecto: `create
  table(:orders)`, `schema "orders"`.
- **Schema modules:** singular, inside a context — `Firmos.Sales.Order`.
  One module per file (`lib/firmos/sales/order.ex`).
- **Columns:** singular — `email`, `shipped_at`, `total_cents`.
- **Primary key:** always literally `id` (Ecto's default). Never `order_id`
  *in* `orders`, never `pk`/`uid`.
- **Foreign keys:** `<referenced_singular>_id` — `customer_id` →
  `customers(id)`; self-reference `parent_order_id`. This is also what
  `belongs_to :customer` expects.
- **Booleans:** a yes/no question — `is_active`, `has_shipped`. Never bare
  `active` or negatives like `is_not_deleted`. (The column name is fine;
  Elixir *functions* still drop the `is_` and end in `?`.)
- **Timestamps:** past-tense event + `_at`, type `timestamptz` —
  `inserted_at` (Ecto's name, not `created_at`), `updated_at`,
  `confirmed_at`. Durations are `interval`; money is `amount_cents`
  integer or `numeric`, never float.
- **Junction tables:** both table names, alphabetical: `groups_users`. If
  the relationship is a domain noun with its own data (`memberships`),
  name it that and treat it as an entity.
- **Indexes / unique / FKs: use Ecto's default names.** Then
  `unique_constraint(:email)` and `foreign_key_constraint(:customer_id)`
  match with no `name:` option.

  | Object | Ecto DSL | Resulting name |
  |---|---|---|
  | btree index | `create index(:orders, [:customer_id])` | `orders_customer_id_index` |
  | unique index | `create unique_index(:customers, [:email])` | `customers_email_index` |
  | GIN index | `create index(:products, [:attributes], using: :gin)` | `products_attributes_index` |
  | foreign key | `references(:customers, ...)` | `orders_customer_id_fkey` |
  | primary key | `create table(:groups_users, primary_key: false)` + PK cols | `groups_users_pkey` |
  | CHECK | `create constraint(:order_items, :order_items_quantity_positive, check: "...")` | always explicit: `<table>_<rule>` |

  CHECK and exclusion constraints have no Ecto default — always name them,
  and pass the same name to `check_constraint/3`.
- **Enum types:** singular domain noun — `order_status`, `user_role`.
- **Functions:** `verb_noun` — `recalculate_cart_total`.
- **No reserved words** (`user`, `order`, `group`); plural tables sidestep
  the trap.
- **No abbreviations** unless universal (`url`, `id`, `sku`). Spell out
  `quantity`, `description`, `address`.

## Wrong

```elixir
create table(:Order) do                # mixed case, singular, reserved word
  add :OrderID, :serial                # CamelCase, redundant
  add :customer, :integer              # no _id, no FK, nullable by omission
  add :active, :boolean                # ambiguous boolean
  add :note, :string                   # varchar(255)
  timestamps()                         # timestamp WITHOUT time zone
end
```

## Right

```elixir
create table(:orders) do               # id bigserial primary key (default)
  add :customer_id, references(:customers, on_delete: :restrict), null: false
  add :is_active, :boolean, null: false, default: true
  add :note, :text
  timestamps(type: :timestamptz, default: fragment("now()"))
end

create index(:orders, [:customer_id])
```

```sql
CREATE TABLE orders (
  id          bigserial PRIMARY KEY,
  customer_id bigint NOT NULL
    CONSTRAINT orders_customer_id_fkey REFERENCES customers (id) ON DELETE RESTRICT,
  is_active   boolean NOT NULL DEFAULT true,
  note        text,
  inserted_at timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX orders_customer_id_index ON orders (customer_id);
```

## When to deviate

- A name dictated by an external system you don't control: isolate it
  (own Postgres schema / `@schema_prefix`), map it with
  `field :name, :string, source: :"LegacyName"`, and keep the rest clean.
- That is the entire list.
