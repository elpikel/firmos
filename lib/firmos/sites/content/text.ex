defmodule Firmos.Sites.Content.Text do
  @moduledoc """
  Shared validation for the text fields of a landing page's content:
  required fields must be non-blank, and every field has a codepoint limit.
  """
  import Ecto.Changeset

  @doc """
  Casts `limits` (`field => max codepoints`) from `attrs`, requires
  `required` and checks each limit.
  """
  @spec cast_text(Ecto.Changeset.t() | struct(), map(), %{atom() => pos_integer()}, [atom()]) ::
          Ecto.Changeset.t()
  def cast_text(data, attrs, limits, required) do
    changeset = cast(data, attrs, Map.keys(limits))

    limits
    |> Enum.reduce(changeset, fn {field, max}, acc ->
      validate_length(acc, field, max: max, count: :codepoints)
    end)
    |> validate_required(required)
  end
end
