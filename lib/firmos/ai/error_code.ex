defmodule Firmos.AI.ErrorCode do
  @moduledoc """
  Turns the reason an AI generation failed into a short, safe code to store
  and log (e.g. `"http_status:500"`, `"timeout"`, `"invalid_shape"`).

  Only codes leave a generation: provider bodies, partial text and refusal
  details can hold anything, so none of it is stored or shown.
  """

  @plain_reasons [
    :invalid_json,
    :invalid_shape,
    :empty_response,
    :missing_api_key,
    :timeout,
    :econnrefused,
    :closed
  ]

  @doc "The safe code for a `Firmos.AI.complete/2` or content-parsing error reason."
  @spec from_reason(term()) :: String.t()
  def from_reason({:http_status, status, _summary}) when is_integer(status),
    do: "http_status:#{status}"

  def from_reason({:refusal, _details}), do: "refusal"
  def from_reason({:truncated, _text}), do: "truncated"
  def from_reason({:unexpected_body, _summary}), do: "unexpected_body"
  def from_reason({:missing_config, _keys}), do: "missing_config"
  def from_reason(reason) when reason in @plain_reasons, do: Atom.to_string(reason)
  def from_reason(_other), do: "provider_error"
end
