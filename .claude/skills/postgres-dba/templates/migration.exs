# Ecto migration skeleton — encodes every postgres-dba rule.
# Generate the file first: `mix ecto.gen.migration create_orders`, then paste
# the body. Produces exactly templates/schema.sql. Every deviation gets a
# comment saying why.
#
# Tip: set once in config/config.exs so plain `timestamps()` is timestamptz:
#   config :firmos, Firmos.Repo, migration_timestamps: [type: :timestamptz]
defmodule Firmos.Repo.Migrations.CreateOrders do
  use Ecto.Migration

  # `change/0` is reversible as long as raw SQL goes through execute(up, down).
  # Use `up/0` + `down/0` instead for data backfills or function bodies whose
  # rollback is not a mechanical inverse.
  def change do
    # Rule 5: small, stable, code-driven set -> Postgres enum type.
    # Must precede the table that uses it (rollback runs in reverse order).
    # Schema side: field :status, Ecto.Enum, values: [...same list...]
    execute(
      "CREATE TYPE order_status AS ENUM ('pending', 'paid', 'shipped', 'delivered', 'cancelled')",
      "DROP TYPE order_status"
    )

    # Rule 1/2: plural table, Ecto's default `id bigserial primary key`.
    # Strings are :text (":string" here would be varchar(255)).
    create table(:customers) do
      add :email, :text, null: false
      add :full_name, :text, null: false
      timestamps(type: :timestamptz, default: fragment("now()"))
    end

    # Natural key -> unique index, never the PK. Default name
    # customers_email_index matches unique_constraint(:email).
    create unique_index(:customers, [:email])
    # CHECKs are always named explicitly: <table>_<rule>.
    create constraint(:customers, :customers_email_shape, check: "position('@' in email) > 1")

    create table(:products) do
      add :sku, :text, null: false
      add :name, :text, null: false
      add :price_cents, :integer, null: false
      timestamps(type: :timestamptz, default: fragment("now()"))
    end

    create unique_index(:products, [:sku])
    create constraint(:products, :products_price_cents_nonneg, check: "price_cents >= 0")

    create table(:coupons) do
      add :code, :text, null: false
      timestamps(type: :timestamptz, default: fragment("now()"))
    end

    create unique_index(:coupons, [:code])

    create table(:orders) do
      # Rule 4: FK is null: false, on_delete explicit (:restrict — never delete
      # a customer with order history). `null:` belongs on `add`, not references.
      add :customer_id, references(:customers, on_delete: :restrict), null: false
      # Rule 4 override: a nullable FK MUST carry this comment or it is a defect.
      # nullable-fk: a coupon is genuinely optional; cleared if the coupon is deleted.
      add :coupon_id, references(:coupons, on_delete: :nilify_all)
      add :status, :order_status, null: false, default: "pending"
      timestamps(type: :timestamptz, default: fragment("now()"))
    end

    # Postgres does not index FK columns for you.
    create index(:orders, [:customer_id])
    create index(:orders, [:coupon_id])
    create index(:orders, [:status])

    create table(:order_items) do
      add :order_id, references(:orders, on_delete: :delete_all), null: false  # child dies with parent
      add :product_id, references(:products, on_delete: :restrict), null: false  # can't delete a sold product
      add :quantity, :integer, null: false
      add :unit_cents, :integer, null: false
      # Rule 6: derived value we aggregate on -> STORED generated column.
      # Schema side: read_after_writes: true, writable: :never.
      add :line_cents, :integer, generated: "ALWAYS AS (quantity * unit_cents) STORED"
    end

    create unique_index(:order_items, [:order_id, :product_id])
    create index(:order_items, [:product_id])
    create constraint(:order_items, :order_items_quantity_positive, check: "quantity > 0")
    create constraint(:order_items, :order_items_unit_cents_nonneg, check: "unit_cents >= 0")

    create table(:groups) do
      add :name, :text, null: false
      timestamps(type: :timestamptz, default: fragment("now()"))
    end

    create unique_index(:groups, [:name])

    # Rule 3: pure many-to-many -> compound PK, NO surrogate id, both sides
    # NOT NULL FKs with :delete_all so a membership never orphans.
    # Table name: both tables, alphabetical.
    create table(:customers_groups, primary_key: false) do
      add :customer_id, references(:customers, on_delete: :delete_all), primary_key: true, null: false
      add :group_id, references(:groups, on_delete: :delete_all), primary_key: true, null: false
      add :added_at, :timestamptz, null: false, default: fragment("now()")
    end

    # PK (customer_id, group_id) serves customer-first lookups; index the other side.
    create index(:customers_groups, [:group_id])

    # Rule 7 (rare): a plpgsql function, only for set-based work or a
    # cross-writer invariant no constraint can express. Full definition up,
    # DROP down. A later change is a NEW migration (new body up, old body down).
    # execute(
    #   """
    #   CREATE OR REPLACE FUNCTION recalculate_order_totals(p_order_ids bigint[])
    #   RETURNS integer LANGUAGE plpgsql VOLATILE SECURITY INVOKER
    #   SET search_path = public, pg_temp AS $$ ... $$;
    #   """,
    #   "DROP FUNCTION IF EXISTS recalculate_order_totals(bigint[])"
    # )
  end
end

# Adding an enum value later: its own migration, never combined with code
# that uses the value in the same transaction.
#
#   def up, do: execute("ALTER TYPE order_status ADD VALUE IF NOT EXISTS 'returned' AFTER 'delivered'")
#   def down, do: :ok  # no DROP VALUE in Postgres; see references/enums.md
#
# Backfills: `up/0` with one set-based `execute("UPDATE ... WHERE ...")` or
# `repo().update_all/2` — never Repo.all |> Enum.each(&Repo.update/1), and
# never call app schema modules (they change; the migration must not).
