defmodule Firmos.Sites.Content.Pricing do
  @moduledoc "The pricing section: a title and the price lines."
  use Ecto.Schema

  import Ecto.Changeset

  alias Firmos.Sites.Content.PriceItem
  alias Firmos.Sites.Content.Text

  @max_items 12

  @type t :: %__MODULE__{title: String.t() | nil, items: [PriceItem.t()]}

  @primary_key false
  embedded_schema do
    field :title, :string
    embeds_many :items, PriceItem, on_replace: :delete
  end

  @doc "Validates the pricing section as decoded from JSON."
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(pricing, attrs) do
    pricing
    |> Text.cast_text(attrs, %{title: 80}, [:title])
    |> cast_embed(:items, required: true, with: &PriceItem.changeset/2)
    |> validate_length(:items, min: 1, max: @max_items)
  end
end
