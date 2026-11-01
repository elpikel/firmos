defmodule Firmos.Carts.Cart do
  @moduledoc """
  A shopping cart owned by a user.

  Template rules encoded here:
    * `@type t` for specs (idioms.md §5)
    * `@derive Inspect` hides secrets; `@derive Jason.Encoder` is an allow-list
      (protocols-inspect-json.md) — derives go BEFORE `schema`
    * changeset casts only user-editable fields; `user_id` is set by the context
    * every DB constraint has a matching `*_constraint/3`
    * one changeset per use case (`changeset/2`, `checkout_changeset/1`)
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Firmos.Carts.Item

  @statuses [:open, :ordered, :abandoned]

  @type status :: :open | :ordered | :abandoned
  @type t :: %__MODULE__{
          id: pos_integer() | nil,
          name: String.t() | nil,
          status: status(),
          share_token: String.t() | nil,
          user_id: pos_integer() | nil,
          items: [Item.t()] | Ecto.Association.NotLoaded.t(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @derive {Inspect, except: [:share_token]}
  @derive {Jason.Encoder, only: [:id, :name, :status, :inserted_at]}
  schema "carts" do
    field :name, :string
    field :status, Ecto.Enum, values: @statuses, default: :open
    # Secret: anyone holding it can view the cart. Never logged, never in JSON.
    field :share_token, :string
    field :user_id, :id

    has_many :items, Item

    timestamps(type: :utc_datetime)
  end

  @doc "User-editable fields only."
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(cart, attrs) do
    cart
    |> cast(attrs, [:name])
    |> validate_required([:name])
    |> validate_length(:name, min: 1, max: 80)
    |> foreign_key_constraint(:user_id)
    |> unique_constraint([:user_id, :name], error_key: :name)
  end

  @doc "State transition; no external input."
  @spec checkout_changeset(t()) :: Ecto.Changeset.t()
  def checkout_changeset(%__MODULE__{status: :open} = cart), do: change(cart, status: :ordered)

  def checkout_changeset(%__MODULE__{} = cart),
    do: cart |> change() |> add_error(:status, "is not open")
end
