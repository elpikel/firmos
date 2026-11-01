defmodule Firmos.Sites.Content.Offer do
  @moduledoc "The offer section: a title and the products or services."
  use Ecto.Schema

  import Ecto.Changeset

  alias Firmos.Sites.Content.OfferItem
  alias Firmos.Sites.Content.Text

  @max_items 12

  @type t :: %__MODULE__{title: String.t() | nil, items: [OfferItem.t()]}

  @primary_key false
  embedded_schema do
    field :title, :string
    embeds_many :items, OfferItem, on_replace: :delete
  end

  @doc "Validates the offer section as decoded from JSON."
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(offer, attrs) do
    offer
    |> Text.cast_text(attrs, %{title: 80}, [:title])
    |> cast_embed(:items, required: true, with: &OfferItem.changeset/2)
    |> validate_length(:items, min: 1, max: @max_items)
  end
end
