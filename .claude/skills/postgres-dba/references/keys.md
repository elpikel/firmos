# Keys & Foreign Keys

Identity, relationships, and referential integrity belong to the database.
The application never enforces a relationship "by convention" and never
deletes a parent and hopes. Changesets translate FK/unique violations into
errors; they are not the enforcement.

## Primary keys: Ecto's default `id`

```elixir
create table(:customers) do            # adds id bigserial primary key
  add :email, :text, null: false
  timestamps(type: :timestamptz, default: fragment("now()"))
end

create unique_index(:customers, [:email])
```

```sql
CREATE TABLE customers (id bigserial PRIMARY KEY, email text NOT NULL, ...);
CREATE UNIQUE INDEX customers_email_index ON customers (email);
```

```elixir
schema "customers" do                  # @primary_key {:id, :id, autogenerate: true} is implicit
  field :email, :string
  timestamps(type: :utc_datetime_usec)
end

def changeset(customer, attrs) do
  customer
  |> cast(attrs, [:email])
  |> validate_required([:email])
  |> unique_constraint(:email)         # customers_email_index -> changeset error
end
```

- The surrogate key is identity; it carries no business meaning, so
  business changes never cascade into PK changes.
- **`bigserial` is the default — don't fight Ecto.** `references/2`
  defaults to `bigint`, so every FK lines up. Never `primary_key: false` +
  a hand-rolled `:serial` id.
- **Natural keys get a `unique_index`, never the PK.** Email, SKU, slug.
- **UUID** only when IDs must be minted outside the DB (offline clients,
  public opaque IDs). Set `@primary_key {:id, :binary_id, autogenerate:
  true}` + `@foreign_key_type :binary_id` and comment the reason.

## Many-to-many: compound primary key, no surrogate

```elixir
create table(:groups_users, primary_key: false) do
  add :group_id, references(:groups, on_delete: :delete_all), primary_key: true, null: false
  add :user_id, references(:users, on_delete: :delete_all), primary_key: true, null: false
  add :added_at, :timestamptz, null: false, default: fragment("now()")
end

create index(:groups_users, [:user_id])  # PK covers group_id-first lookups only
```

```sql
CREATE TABLE groups_users (
  group_id bigint NOT NULL REFERENCES groups (id) ON DELETE CASCADE,
  user_id  bigint NOT NULL REFERENCES users  (id) ON DELETE CASCADE,
  added_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT groups_users_pkey PRIMARY KEY (group_id, user_id)
);
```

```elixir
# Firmos.Accounts.GroupUser
@primary_key false
schema "groups_users" do
  belongs_to :group, Group, primary_key: true
  belongs_to :user, User, primary_key: true
  field :added_at, :utc_datetime_usec, read_after_writes: true
end

def changeset(group_user, attrs) do
  group_user
  |> cast(attrs, [:group_id, :user_id])
  |> unique_constraint([:group_id, :user_id], name: :groups_users_pkey)
  |> foreign_key_constraint(:group_id)
  |> foreign_key_constraint(:user_id)
end

# Firmos.Accounts.Group
many_to_many :users, User, join_through: GroupUser   # or "groups_users" for a bare junction
```

- The compound PK *is* the uniqueness rule; duplicates are impossible by
  construction.
- `on_delete: :delete_all` on a pure junction: removing either parent
  removes the membership.
- Once the junction grows a lifecycle (status, role, paid_at) it is an
  entity: name it (`memberships`), give it the default `id`, keep
  `create unique_index(:memberships, [:group_id, :user_id])`, and use
  `has_many ... through:`.

## Foreign keys: `null: false` by default, `on_delete` always explicit

```elixir
create table(:order_items) do
  add :order_id, references(:orders, on_delete: :delete_all), null: false
  add :product_id, references(:products, on_delete: :restrict), null: false
  add :quantity, :integer, null: false
end
```

| Ecto `on_delete` | SQL | Use when |
|---|---|---|
| `:delete_all` | `ON DELETE CASCADE` | child can't outlive parent |
| `:restrict` | `ON DELETE RESTRICT` | parent must not vanish while referenced |
| `:nilify_all` | `ON DELETE SET NULL` | only on a documented nullable FK |
| `:nothing` (default) | `NO ACTION` | never by omission — state intent |

Schema side: `belongs_to :order, Order` and, in the changeset,
`foreign_key_constraint(:product_id)`. Set parent ids programmatically
(`%OrderItem{order_id: order.id}` or `Ecto.build_assoc/3`), not via
`cast`. On the parent, `no_assoc_constraint(:order_items)` turns a
RESTRICT violation on delete into a changeset error.

### The nullable-FK override

```elixir
# nullable-fk: coupon is genuinely optional; cleared if the coupon is deleted
add :coupon_id, references(:coupons, on_delete: :nilify_all)
```

**A nullable FK without a `# nullable-fk: <reason>` comment is a defect.**
No comment → add `null: false`. `:nilify_all` is only valid on such a
column.

## When to deviate

- **Sharded / cross-database:** UUID PKs; document where integrity is
  enforced since the DB can't.
- **Offline/distributed ID generation:** UUID; everything else stays.
- Never deviate on "FKs are NOT NULL" silently — the comment exists so
  deviation is visible.
