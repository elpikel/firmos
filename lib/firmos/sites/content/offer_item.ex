defmodule Firmos.Sites.Content.OfferItem do
  @moduledoc "One product or service in the offer section."
  use Ecto.Schema

  alias Firmos.Sites.Content.Text

  @limits %{name: 120, description: 600}

  @type t :: %__MODULE__{name: String.t() | nil, description: String.t() | nil}

  @primary_key false
  embedded_schema do
    field :name, :string
    field :description, :string
  end

  @doc "Validates one offer item as decoded from JSON."
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(item, attrs), do: Text.cast_text(item, attrs, @limits, Map.keys(@limits))
end
