defmodule Firmos.Sites.Content.PriceItem do
  @moduledoc "One line of the pricing section: what, how much, and an optional note."
  use Ecto.Schema

  alias Firmos.Sites.Content.Text

  @limits %{name: 120, price: 60, note: 200}

  @type t :: %__MODULE__{name: String.t() | nil, price: String.t() | nil, note: String.t() | nil}

  @primary_key false
  embedded_schema do
    field :name, :string
    # Free text ("14 zł", "od 79 zł / tydzień"): shown, never computed with.
    field :price, :string
    field :note, :string
  end

  @doc "Validates one price line as decoded from JSON."
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(item, attrs), do: Text.cast_text(item, attrs, @limits, [:name, :price])
end
