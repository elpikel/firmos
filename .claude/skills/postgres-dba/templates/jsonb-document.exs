# Ecto side of the hybrid document pattern (Rule 8) — produces and uses
# templates/jsonb-document.sql. Three parts, each in its OWN file when copied:
#   1. migration   priv/repo/migrations/<ts>_create_products.exs
#   2. schemas     lib/firmos/catalog/product.ex, product_attributes.ex
#   3. queries     lib/firmos/catalog.ex (the context)

# ---------------------------------------------------------------------------
# 1. Migration
# ---------------------------------------------------------------------------
defmodule Firmos.Repo.Migrations.CreateProducts do
  use Ecto.Migration

  def change do
    create table(:products) do
      # ---- relational spine ----
      add :sku, :text, null: false
      add :category_id, references(:categories, on_delete: :restrict), null: false

      # ---- open-ended body: :map is jsonb on Postgres ----
      add :attributes, :map, null: false, default: %{}

      # ---- hot fields promoted OUT of the document (generated, STORED) ----
      add :price_cents, :integer,
        generated: "ALWAYS AS ((attributes->>'price_cents')::integer) STORED"

      add :brand, :text, generated: "ALWAYS AS (attributes->>'brand') STORED"

      timestamps(type: :timestamptz, default: fragment("now()"))
    end

    create unique_index(:products, [:sku])
    create index(:products, [:category_id])

    # Raw expression column -> name it explicitly.
    create index(:products, ["attributes jsonb_path_ops"],
             using: :gin,
             name: :products_attributes_index
           )

    create index(:products, [:price_cents])
    create index(:products, [:brand])

    # A document is not an excuse to abandon validation.
    create constraint(:products, :products_attributes_object,
             check: "jsonb_typeof(attributes) = 'object'"
           )

    create constraint(:products, :products_price_present, check: "attributes ? 'price_cents'")

    create constraint(:products, :products_price_nonneg,
             check: "(attributes->>'price_cents')::integer >= 0"
           )
  end
end

# ---------------------------------------------------------------------------
# 2. Schemas — known shape typed with an embedded_schema, stored as jsonb.
#    Use `field :attributes, :map` instead when the shape is open-ended or
#    you must preserve keys you don't model (embeds drop unknown keys on load).
# ---------------------------------------------------------------------------
defmodule Firmos.Catalog.ProductAttributes do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    field :price_cents, :integer
    field :brand, :string
    field :waterproof, :boolean, default: false
    field :dimensions, :map
  end

  def changeset(attributes, attrs) do
    attributes
    |> cast(attrs, [:price_cents, :brand, :waterproof, :dimensions])
    |> validate_required([:price_cents])
    |> validate_number(:price_cents, greater_than_or_equal_to: 0)
  end
end

defmodule Firmos.Catalog.Product do
  use Ecto.Schema
  import Ecto.Changeset

  schema "products" do
    field :sku, :string
    embeds_one :attributes, Firmos.Catalog.ProductAttributes, on_replace: :update

    # Generated from the document: DB computes, RETURNING loads, never written.
    field :price_cents, :integer, read_after_writes: true, writable: :never
    field :brand, :string, read_after_writes: true, writable: :never

    belongs_to :category, Firmos.Catalog.Category

    timestamps(type: :utc_datetime_usec)
  end

  # category_id is set by the context, not cast.
  def changeset(product, attrs) do
    product
    |> cast(attrs, [:sku])
    |> cast_embed(:attributes, required: true)
    |> validate_required([:sku, :category_id])
    |> unique_constraint(:sku)
    |> foreign_key_constraint(:category_id)
    |> check_constraint(:attributes, name: :products_attributes_object)
    |> check_constraint(:attributes, name: :products_price_present)
    |> check_constraint(:attributes, name: :products_price_nonneg)
  end
end

# ---------------------------------------------------------------------------
# 3. Query + mutation idioms (context functions). Named bindings; every value
#    is a pinned param behind a `?` — NEVER interpolate into fragment strings.
# ---------------------------------------------------------------------------
defmodule Firmos.Catalog do
  import Ecto.Query

  alias Firmos.Catalog.Product
  alias Firmos.Repo

  # Containment — uses the GIN index. Postgrex encodes the map as jsonb.
  def list_by_attributes(%{} = filter) do
    from(p in Product, as: :product)
    |> where([product: p], fragment("? @> ?", p.attributes, ^filter))
    |> Repo.all()
  end

  # JSONPath with the path as a parameter.
  def list_by_jsonpath(path) when is_binary(path) do
    from(p in Product, as: :product)
    |> where([product: p], fragment("? @? ?::jsonpath", p.attributes, ^path))
    |> Repo.all()
  end

  # Range / order: hit the generated column, never the raw path.
  def list_in_price_range(min, max) do
    from(p in Product, as: :product)
    |> join(:inner, [product: p], c in assoc(p, :category), as: :category)
    |> where([product: p], p.price_cents >= ^min and p.price_cents <= ^max)
    |> order_by([product: p], p.price_cents)
    |> preload([category: c], category: c)
    |> Repo.all()
  end

  # Dynamic key lookup: the key is a param too.
  def list_with_value(key, value) do
    from(p in Product, as: :product)
    |> where([product: p], fragment("?->>? = ?", p.attributes, ^key, ^value))
    |> Repo.all()
  end

  # Concurrent-safe mutations: change the document in SQL, never round-trip
  # and overwrite the whole blob.
  def merge_attributes(product_id, %{} = patch) do
    from(p in Product, where: p.id == ^product_id)
    |> update([p], set: [attributes: fragment("? || ?", p.attributes, ^patch), updated_at: fragment("now()")])
    |> Repo.update_all([])
  end

  def remove_attribute_path(product_id, path) when is_list(path) do
    from(p in Product, where: p.id == ^product_id)
    |> update([p], set: [attributes: fragment("? #- ?", p.attributes, ^path), updated_at: fragment("now()")])
    |> Repo.update_all([])
  end
end
