defmodule Firmos.AI do
  @moduledoc """
  The one door to AI text generation. Callers depend on this module, never
  on a provider.

  The adapter is read from config at call time, so tests swap it for
  `Firmos.AI.Mock`:

      config :firmos, Firmos.AI, adapter: Firmos.AI.Claude

  Options accepted by every adapter:

    * `:system` - a system prompt sent alongside the user prompt

  Adapters may accept more (see `Firmos.AI.Claude`). Failures are returned
  as `{:error, reason}`, never raised.
  """

  @type completion :: {:ok, String.t()} | {:error, term()}

  @callback complete(prompt :: String.t(), opts :: keyword()) :: completion()

  @doc "Asks the configured adapter to complete `prompt`."
  @spec complete(String.t(), keyword()) :: completion()
  def complete(prompt, opts \\ []) when is_binary(prompt) and is_list(opts) do
    adapter().complete(prompt, opts)
  end

  defp adapter do
    :firmos
    |> Application.fetch_env!(__MODULE__)
    |> Keyword.fetch!(:adapter)
  end
end
