defmodule Firmos.AI.Prompt do
  @moduledoc """
  Helpers for putting untrusted text (owner input, earlier AI output) into a
  prompt. Such text is fenced in tags (e.g. `<opis>`) so the model treats it
  as data, not instructions.
  """

  @doc """
  Replaces angle brackets with look-alike guillemets, so `text` can't close
  its fence or open another tag.
  """
  @spec neutralize_tags(String.t()) :: String.t()
  def neutralize_tags(text) when is_binary(text) do
    text |> String.replace("<", "‹") |> String.replace(">", "›")
  end
end
