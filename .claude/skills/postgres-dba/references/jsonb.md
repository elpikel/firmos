# JSONB as a Document Store

Postgres is a good document database — *when used as one on purpose*. The
failure modes are the two extremes: forcing open-ended data into 40 sparse
columns or an EAV table, or dumping the entity into one untyped blob and
losing every guarantee. The discipline is the **hybrid pattern**.

## Always `jsonb`, never `json`

`json` stores text verbatim and reparses on every access; `jsonb` is
decomposed binary with GIN indexing and containment/path operators. Ecto's
`:map` migration type on Postgres is already `jsonb`. Never `add :x, :json`.

## The hybrid pattern (this is the rule)

A relational **spine** carries identity, relationships, and fields you
filter/join on; a `jsonb` **body** carries the open-ended remainder.

```elixir
create table(:products) do
  add :sku, :text, null: false
  add :category_id, references(:categories, on_delete: :restrict), null: false
  add :attributes, :map, null: false, default: %{}          # jsonb NOT NULL DEFAULT '{}'
  # hot fields promoted OUT of the document
  add :price_cents, :integer, generated: "ALWAYS AS ((attributes->>'price_cents')::integer) STORED"
  add :brand, :text, generated: "ALWAYS AS (attributes->>'brand') STORED"
  timestamps(type: :timestamptz, default: fragment("now()"))
end

create unique_index(:products, [:sku])
create constraint(:products, :products_attributes_object, check: "jsonb_typeof(attributes) = 'object'")
create constraint(:products, :products_price_present, check: "attributes ? 'price_cents'")
create index(:products, ["attributes jsonb_path_ops"], using: :gin, name: :products_attributes_index)
create index(:products, [:price_cents])
```

```sql
CREATE TABLE products (
  id          bigserial PRIMARY KEY,
  sku         text   NOT NULL,
  category_id bigint NOT NULL REFERENCES categories (id) ON DELETE RESTRICT,
  attributes  jsonb  NOT NULL DEFAULT '{}',
  price_cents integer GENERATED ALWAYS AS ((attributes->>'price_cents')::integer) STORED,
  brand       text    GENERATED ALWAYS AS (attributes->>'brand') STORED,
  ...
);
CREATE INDEX products_attributes_index ON products USING gin (attributes jsonb_path_ops);
```

- **Spine columns**: real keys, real FKs. Relationships never live in JSONB.
- **`NOT NULL DEFAULT '{}'`**: code never branches on `nil` vs `%{}`.
- **Generated columns**: b-tree range scans on document fields without a
  second source of truth (`generated-columns.md`).
- **CHECKs**: shape, required keys, value rules — mapped back with
  `check_constraint(:attributes, name: :products_price_present)`.
- **GIN `jsonb_path_ops`**: smaller/faster for `@>`; default `jsonb_ops`
  if you also need `?`, `?|`, `?&` indexed.

## Schema side: `:map` or `embeds_one`

- **Shape unknown / external payload** (webhooks, third-party docs):
  `field :payload, :map`. Keys come back as strings.
- **Shape known, evolving**: `embeds_one :attributes, Attributes,
  on_replace: :update` with `Attributes` an `embedded_schema` in its own
  file — you get casting, validation, and atoms while storage stays
  `jsonb`. Unknown keys in stored documents are dropped on load, so use
  `:map` when you must preserve keys you don't model.
- Generated columns from the document: `read_after_writes: true,
  writable: :never`.

## Querying — operators that matter

| Operator | Meaning | GIN-indexable |
|---|---|---|
| `->` / `->>` | field as jsonb / text | via generated column |
| `#>` / `#>>` | by path | — |
| `@>` | contains | **yes** (the workhorse) |
| `?` / `?|` / `?&` | key(s) exist | `jsonb_ops` only |
| `@?` / `@@` | JSONPath | yes |

Ecto has no JSONB operators: use `fragment` with `?` placeholders and
pinned params. **Never interpolate** into the fragment string.

```elixir
# containment — uses the GIN index; Postgrex encodes the map as jsonb
from(p in Product, as: :product)
|> where([product: p], fragment("? @> ?", p.attributes, ^%{"brand" => "Acme", "waterproof" => true}))

# JSONPath with a parameterized variable
|> where([product: p], fragment("? @? ?::jsonpath", p.attributes, ^"$.dimensions.width_mm ? (@ > 100)"))

# ranges/order: the generated column, not the path
|> where([product: p], p.price_cents >= ^min and p.price_cents <= ^max)
|> order_by([product: p], p.price_cents)
```

## Updating — don't clobber the document

Changesets replace the whole `:map` value — fine for single-writer
records. For concurrent writers, mutate in SQL so keys aren't lost:

```elixir
from(p in Product, where: p.id == ^id)
|> update([p], set: [attributes: fragment("? || ?", p.attributes, ^%{"waterproof" => true})])  # shallow merge
|> Repo.update_all([])

# remove a nested path
|> update([p], set: [attributes: fragment("? #- ?", p.attributes, ^["dimensions", "depth_mm"])])
```

`||` is shallow. Deep merge is a candidate for a plpgsql function only if
many writers need it; otherwise merge in Elixir inside a transaction with
a row lock (`lock("FOR UPDATE")`).

## When JSONB, when columns

JSONB body: genuinely open-ended or polymorphic attributes, shape varies
per row, external documents you don't own.
Real column: you filter/join/sort/aggregate on it, it is a FK or in a
constraint (**always** a column), or every row shares a stable shape
(that's a table).

## Anti-patterns this rule kills

- **EAV** tables — JSONB is the replacement. Do not build EAV.
- **The God blob** — ids and FKs inside the document.
- **`->>` in hot `where`/`order_by`** instead of a generated column.
- **`json` instead of `jsonb`.**
- **No CHECK on the document** — required fields silently go missing.
- **`fragment("attributes->>'#{key}'")`** — SQL injection. Pass the key
  as a param: `fragment("?->>?", p.attributes, ^key)`.

## When to deviate

- **Opaque payload store** never queried into: `(id, payload jsonb,
  inserted_at)` is fine — promote fields the moment you filter by them.
- **Append-only audit/event JSON**: skip generated columns until a query
  needs one.
