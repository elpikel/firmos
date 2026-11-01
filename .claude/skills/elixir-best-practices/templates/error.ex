defmodule Firmos.Error do
  @moduledoc """
  Domain error with a machine-readable `reason` and structured `details`.

  Conventions (idioms.md §1, §13):

    * Default to bare atoms: `{:error, :not_found}`.
    * Validation failures are `{:error, %Ecto.Changeset{}}`.
    * Use this struct only when the caller needs data beyond the atom:
      `{:error, %Firmos.Error{reason: :insufficient_stock, details: %{sku: "w-1", available: 2}}}`.
    * Never `{:error, "a string"}` — strings are not matchable.
    * Because it is a `defexception`, the bang variant of a function can
      `raise` the very same value: `raise Firmos.Error, reason: :not_found`.

  Callers match on `reason`, never on `message`:

      case Carts.reserve(cart) do
        {:ok, cart} -> ...
        {:error, %Firmos.Error{reason: :insufficient_stock, details: %{sku: sku}}} -> ...
      end
  """

  @type reason ::
          :not_found
          | :unauthorized
          | :conflict
          | :insufficient_stock
          | :upstream_unavailable

  @type t :: %__MODULE__{
          reason: reason(),
          details: map(),
          message: String.t() | nil
        }

  # `details` may carry user data — keep it out of crash reports/logs.
  @derive {Inspect, only: [:reason]}
  @derive {Jason.Encoder, only: [:reason, :message]}
  defexception [:reason, :message, details: %{}]

  @doc "Builds the error; use as `{:error, Firmos.Error.new(:conflict, %{id: id})}`."
  @spec new(reason(), map()) :: t()
  def new(reason, details \\ %{}) when is_atom(reason) and is_map(details) do
    %__MODULE__{reason: reason, details: details, message: default_message(reason)}
  end

  @impl Exception
  def exception(opts) do
    reason = Keyword.fetch!(opts, :reason)
    details = Keyword.get(opts, :details, %{})
    %{new(reason, details) | message: Keyword.get(opts, :message, default_message(reason))}
  end

  @impl Exception
  def message(%__MODULE__{message: message}), do: message

  @spec default_message(reason()) :: String.t()
  defp default_message(:not_found), do: "resource not found"
  defp default_message(:unauthorized), do: "not allowed"
  defp default_message(:conflict), do: "resource was changed concurrently"
  defp default_message(:insufficient_stock), do: "not enough stock"
  defp default_message(:upstream_unavailable), do: "external service unavailable"
end
