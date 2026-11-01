defmodule Firmos.AI.Claude do
  @moduledoc """
  `Firmos.AI` adapter for the Anthropic Messages API, built on Req.

  Settings come from `config :firmos, Firmos.AI.Claude` (the key is set in
  `config/runtime.exs`); any of them can be overridden per call through
  `opts`:

    * `:api_key` - Anthropic API key; blank means `{:error, :missing_api_key}`
    * `:model`, `:max_tokens` - sent in the request body
    * `:system` - optional system prompt
    * `:retry` - `true` retries 429, 5xx and timeouts up to `:max_retries` times
    * `:base_url`, `:receive_timeout`, `:max_retries` - Req transport
    * `:req_options` - extra Req options merged last, key by key (tests use `plug:`)

  Errors are values, never raised:

    * `{:http_status, status, summary}` - non-2xx response
    * `{:refusal, details}` - `stop_reason: "refusal"`; `details` holds any
      partial `:text` and the API's `:stop_details`
    * `{:truncated, text}` - the token budget ran out (`stop_reason:
      "max_tokens"` or `"model_context_window_exceeded"`); `text` is partial.
      Thinking counts toward `:max_tokens`, so keep it generous
    * `:empty_response` - a finished turn with no text
    * `{:unexpected_body, summary}` - 2xx without a `content` list, or a body
      that could not be decoded
    * transport reason, e.g. `:timeout` or `:econnrefused`
    * `:missing_api_key`
    * `{:missing_config, keys}` - required settings absent (names only)

  ## Blocking time

  A call blocks its caller until the provider answers. Worst case is about
  `receive_timeout × (max_retries + 1)` plus Req's exponential backoff
  (1s, 2s, …) — with the defaults (600s, 2 retries) that is ~30 minutes.
  Run it in a `Task` or an Oban job, never directly inside a LiveView
  callback.
  """

  @behaviour Firmos.AI

  @messages_path "/v1/messages"
  @api_version "2023-06-01"
  @summary_limit 500
  @required_settings [:base_url, :model, :max_tokens, :receive_timeout]
  @truncation_reasons ["max_tokens", "model_context_window_exceeded"]

  @impl Firmos.AI
  @spec complete(String.t(), keyword()) :: Firmos.AI.completion()
  def complete(prompt, opts) when is_binary(prompt) and is_list(opts) do
    # The key is popped first so no later error (e.g. a KeyError) can print it.
    {api_key, settings} =
      Application.get_env(:firmos, __MODULE__, [])
      |> merge_config(opts)
      |> Keyword.pop(:api_key)

    with {:ok, api_key} <- validate_api_key(api_key),
         :ok <- validate_settings(settings),
         {:ok, response} <- post(prompt, api_key, settings) do
      to_completion(response)
    end
  end

  # Per-call opts win, but `:req_options` is merged key-by-key so a caller
  # adding e.g. `retry_delay:` keeps the configured ones (the test `plug:`).
  defp merge_config(app_config, opts) do
    {call_req_options, opts} = Keyword.pop(opts, :req_options, [])

    app_config
    |> Keyword.merge(opts)
    |> Keyword.update(:req_options, call_req_options, &Keyword.merge(&1, call_req_options))
  end

  defp validate_api_key(key) when is_binary(key) and key != "", do: {:ok, key}
  defp validate_api_key(_blank), do: {:error, :missing_api_key}

  defp validate_settings(settings) do
    case Enum.filter(@required_settings, &is_nil(settings[&1])) do
      [] -> :ok
      missing -> {:error, {:missing_config, missing}}
    end
  end

  # WARNING: the built `Req.Request` carries the key in its `x-api-key`
  # header and `inspect/1` shows it. Never log, inspect or return the
  # request; only mapped reasons leave this module.
  defp post(prompt, api_key, config) do
    [
      method: :post,
      base_url: Keyword.fetch!(config, :base_url),
      url: @messages_path,
      headers: [{"x-api-key", api_key}, {"anthropic-version", @api_version}],
      json: request_body(prompt, config),
      receive_timeout: Keyword.fetch!(config, :receive_timeout),
      retry: if(Keyword.get(config, :retry, true), do: &transient?/2, else: false),
      max_retries: Keyword.get(config, :max_retries, 2)
    ]
    |> Keyword.merge(Keyword.get(config, :req_options, []))
    |> Req.request()
    |> case do
      {:ok, response} -> {:ok, response}
      {:error, %Req.TransportError{reason: reason}} -> {:error, reason}
      {:error, exception} -> {:error, {:unexpected_body, summarize(Exception.message(exception))}}
    end
  end

  # Like Req's `:transient`, but for any method (we POST) and every 5xx,
  # including Anthropic's 529 "overloaded".
  defp transient?(_request, %Req.Response{status: status}),
    do: status == 429 or status in 500..599

  defp transient?(_request, %Req.TransportError{reason: reason}),
    do: reason in [:timeout, :econnrefused, :closed]

  defp transient?(_request, _exception), do: false

  defp request_body(prompt, config) do
    body = %{
      model: Keyword.fetch!(config, :model),
      max_tokens: Keyword.fetch!(config, :max_tokens),
      messages: [%{role: "user", content: prompt}]
    }

    case Keyword.get(config, :system) do
      nil -> body
      system -> Map.put(body, :system, system)
    end
  end

  defp to_completion(%Req.Response{status: status, body: %{"content" => content} = body})
       when status in 200..299 and is_list(content) do
    text = for %{"type" => "text", "text" => text} <- content, into: "", do: text

    case {body["stop_reason"], text} do
      {"refusal", text} -> {:error, {:refusal, %{text: text, stop_details: body["stop_details"]}}}
      {reason, text} when reason in @truncation_reasons -> {:error, {:truncated, text}}
      {_finished, ""} -> {:error, :empty_response}
      {_finished, text} -> {:ok, text}
    end
  end

  defp to_completion(%Req.Response{status: status, body: body}) when status in 200..299 do
    {:error, {:unexpected_body, summarize(body)}}
  end

  defp to_completion(%Req.Response{status: status, body: body}) do
    {:error, {:http_status, status, summarize(body)}}
  end

  defp summarize(%{"error" => %{"type" => type, "message" => message}}),
    do: truncate("#{type}: #{message}")

  defp summarize(body) when is_binary(body), do: truncate(body)
  defp summarize(body), do: body |> inspect() |> truncate()

  defp truncate(text), do: String.slice(text, 0, @summary_limit)
end
