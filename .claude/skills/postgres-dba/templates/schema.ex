# Ecto schemas + changesets matching templates/migration.exs.
# Each module goes in its OWN file (lib/firmos/sales/order.ex, ...); they are
# shown together here only for reference. Product, Coupon, and Group follow
# the Customer pattern.
#
# Conventions encoded:
# - `field :x, :string` for text columns; Ecto.Enum on a Postgres enum type.
# - timestamps(type: :utc_datetime_usec) <-> timestamptz columns.
# - Every DB constraint has a changeset twin so violations become
#   {:error, changeset} instead of raising Ecto.ConstraintError.
# - Programmatic fields (parent ids, generated columns) are never cast.

defmodule Firmos.Sales.Customer do
  use Ecto.Schema
  import Ecto.Changeset

  # id :id (bigserial) is Ecto's default — no @primary_key needed.
  schema "customers" do
    field :email, :string
    field :full_name, :string

    has_many :orders, Firmos.Sales.Order
    many_to_many :groups, Firmos.Sales.Group, join_through: Firmos.Sales.CustomerGroup

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(customer, attrs) do
    customer
    |> cast(attrs, [:email, :full_name])
    |> validate_required([:email, :full_name])
    # UX pre-check; the DB CHECK below is the actual rule.
    |> validate_format(:email, ~r/^[^@\s]+@/)
    |> check_constraint(:email, name: :customers_email_shape)
    |> unique_constraint(:email)
  end

  # Turns ON DELETE RESTRICT from orders into a changeset error on delete.
  def delete_changeset(customer) do
    customer
    |> change()
    |> no_assoc_constraint(:orders)
  end
end

defmodule Firmos.Sales.Order do
  use Ecto.Schema
  import Ecto.Changeset

  schema "orders" do
    # Must match `CREATE TYPE order_status` exactly; keep both in one PR.
    field :status, Ecto.Enum,
      values: [:pending, :paid, :shipped, :delivered, :cancelled],
      default: :pending

    belongs_to :customer, Firmos.Sales.Customer
    # nullable-fk: coupon is optional (see migration).
    belongs_to :coupon, Firmos.Sales.Coupon
    has_many :items, Firmos.Sales.OrderItem

    timestamps(type: :utc_datetime_usec)
  end

  # customer_id is set by the context (%Order{customer_id: customer.id}),
  # never cast from user params.
  def create_changeset(order, attrs) do
    order
    |> cast(attrs, [:coupon_id])
    |> validate_required([:customer_id])
    |> foreign_key_constraint(:customer_id)
    |> foreign_key_constraint(:coupon_id)
  end

  def status_changeset(order, attrs) do
    order
    |> cast(attrs, [:status])
    |> validate_required([:status])
  end
end

defmodule Firmos.Sales.OrderItem do
  use Ecto.Schema
  import Ecto.Changeset

  schema "order_items" do
    field :quantity, :integer
    field :unit_cents, :integer
    # STORED generated column: DB computes it, RETURNING loads it, Ecto never writes it.
    field :line_cents, :integer, read_after_writes: true, writable: :never

    belongs_to :order, Firmos.Sales.Order
    belongs_to :product, Firmos.Sales.Product
  end

  # order_id comes from Ecto.build_assoc(order, :items) or the Multi.
  def changeset(item, attrs) do
    item
    |> cast(attrs, [:product_id, :quantity, :unit_cents])
    |> validate_required([:order_id, :product_id, :quantity, :unit_cents])
    |> validate_number(:quantity, greater_than: 0)
    |> check_constraint(:quantity, name: :order_items_quantity_positive)
    |> check_constraint(:unit_cents, name: :order_items_unit_cents_nonneg)
    |> unique_constraint([:order_id, :product_id])
    |> foreign_key_constraint(:order_id)
    |> foreign_key_constraint(:product_id)
  end
end

defmodule Firmos.Sales.CustomerGroup do
  use Ecto.Schema
  import Ecto.Changeset

  # Rule 3: compound-PK junction, no surrogate id.
  @primary_key false
  schema "customers_groups" do
    belongs_to :customer, Firmos.Sales.Customer, primary_key: true
    belongs_to :group, Firmos.Sales.Group, primary_key: true
    # DB default now(); loaded back via RETURNING.
    field :added_at, :utc_datetime_usec, read_after_writes: true
  end

  # Both ids are set by the context, not cast from user params.
  def changeset(customer_group) do
    customer_group
    |> change()
    |> unique_constraint([:customer_id, :group_id], name: :customers_groups_pkey)
    |> foreign_key_constraint(:customer_id)
    |> foreign_key_constraint(:group_id)
  end
end

# Querying (in the context): named bindings, params pinned, never interpolated.
#
#   import Ecto.Query
#
#   from(o in Order, as: :order)
#   |> join(:inner, [order: o], c in assoc(o, :customer), as: :customer)
#   |> where([order: o], o.status in [:paid, :shipped])
#   |> where([customer: c], c.email == ^email)
#   |> preload([customer: c], customer: c)
#   |> Repo.all()
