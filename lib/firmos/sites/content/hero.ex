defmodule Firmos.Sites.Content.Hero do
  @moduledoc "The landing page's opening section: headline, subheadline and call-to-action label."
  use Ecto.Schema

  alias Firmos.Sites.Content.Text

  @limits %{headline: 120, subheadline: 300, cta_label: 40}

  @type t :: %__MODULE__{
          headline: String.t() | nil,
          subheadline: String.t() | nil,
          cta_label: String.t() | nil
        }

  @primary_key false
  embedded_schema do
    field :headline, :string
    field :subheadline, :string
    field :cta_label, :string
  end

  @doc "Validates the hero as decoded from JSON."
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(hero, attrs), do: Text.cast_text(hero, attrs, @limits, Map.keys(@limits))
end
