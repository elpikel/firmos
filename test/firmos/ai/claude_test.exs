defmodule Firmos.AI.ClaudeTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias Firmos.AI.Claude

  @test_key Application.compile_env!(:firmos, [Firmos.AI.Claude, :api_key])

  defp stub_responses(responses) do
    {:ok, agent} = Agent.start_link(fn -> responses end)

    Req.Test.stub(Claude, fn conn ->
      {status, body} = Agent.get_and_update(agent, fn [next | rest] -> {next, rest} end)

      conn
      |> Plug.Conn.put_status(status)
      |> Req.Test.json(body)
    end)
  end

  defp text_body(text, stop_reason \\ "end_turn") do
    %{"stop_reason" => stop_reason, "content" => [%{"type" => "text", "text" => text}]}
  end

  describe "complete/2 stop reasons" do
    test "a refusal is an error carrying the partial text and stop details" do
      stub_responses([
        {200, Map.put(text_body("", "refusal"), "stop_details", %{"type" => "refusal"})}
      ])

      assert Claude.complete("x", []) ==
               {:error, {:refusal, %{text: "", stop_details: %{"type" => "refusal"}}}}
    end

    test "running out of max_tokens is an error carrying the partial text" do
      stub_responses([{200, text_body("Plan dla pie", "max_tokens")}])

      assert Claude.complete("x", []) == {:error, {:truncated, "Plan dla pie"}}
    end

    test "exceeding the context window is a truncation" do
      stub_responses([{200, text_body("Plan", "model_context_window_exceeded")}])

      assert Claude.complete("x", []) == {:error, {:truncated, "Plan"}}
    end

    test "a finished turn with no text is an empty response" do
      stub_responses([{200, %{"stop_reason" => "end_turn", "content" => []}}])

      assert Claude.complete("x", []) == {:error, :empty_response}
    end

    test "a stop sequence still returns the text" do
      stub_responses([{200, text_body("Plan", "stop_sequence")}])

      assert Claude.complete("x", []) == {:ok, "Plan"}
    end
  end

  describe "complete/2 retries" do
    test "recovers from a transient 503 when retries are enabled" do
      stub_responses([{503, %{}}, {200, text_body("po ponowieniu")}])

      assert Claude.complete("x",
               retry: true,
               req_options: [retry_delay: 0, retry_log_level: false]
             ) ==
               {:ok, "po ponowieniu"}
    end

    test "surfaces the last 5xx once retries are exhausted" do
      stub_responses([{529, %{}}, {500, %{}}, {500, %{}}])

      assert {:error, {:http_status, 500, _}} =
               Claude.complete("x",
                 retry: true,
                 max_retries: 1,
                 req_options: [retry_delay: 0, retry_log_level: false]
               )
    end

    test "does not retry a 4xx" do
      stub_responses([{400, %{}}, {200, text_body("never")}])

      assert {:error, {:http_status, 400, _}} =
               Claude.complete("x",
                 retry: true,
                 req_options: [retry_delay: 0, retry_log_level: false]
               )
    end
  end

  describe "complete/2 error summaries" do
    test "summarizes an Anthropic error body as type and message" do
      stub_responses([
        {401,
         %{
           "type" => "error",
           "error" => %{"type" => "authentication_error", "message" => "invalid x-api-key"}
         }}
      ])

      assert Claude.complete("x", []) ==
               {:error, {:http_status, 401, "authentication_error: invalid x-api-key"}}
    end

    test "truncates a long non-standard error body" do
      stub_responses([{502, %{"detail" => String.duplicate("a", 2_000)}}])

      assert {:error, {:http_status, 502, summary}} = Claude.complete("x", [])
      assert String.length(summary) == 500
    end

    test "rejects a 2xx body without a content list" do
      stub_responses([{200, %{"unexpected" => true}}])

      assert {:error, {:unexpected_body, _}} = Claude.complete("x", [])
    end

    test "maps an undecodable body to :unexpected_body" do
      Req.Test.stub(Claude, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(200, "{not json")
      end)

      assert {:error, {:unexpected_body, _summary}} = Claude.complete("x", [])
    end

    test "names missing settings without leaking the key" do
      assert Claude.complete("x", model: nil, base_url: nil) ==
               {:error, {:missing_config, [:base_url, :model]}}
    end

    test "treats a blank key as missing" do
      assert Claude.complete("x", api_key: "") == {:error, :missing_api_key}
    end
  end

  describe "complete/2 options" do
    test "a per-call model overrides the configured one" do
      test_pid = self()

      Req.Test.stub(Claude, fn conn ->
        {:ok, raw, conn} = Plug.Conn.read_body(conn)
        send(test_pid, {:model, Jason.decode!(raw)["model"]})
        Req.Test.json(conn, text_body("ok"))
      end)

      {:ok, _} = Claude.complete("x", model: "claude-haiku-5-5")

      assert_received {:model, "claude-haiku-5-5"}
    end

    test "the API key never appears in logs or error tuples" do
      {results, log} =
        with_log(fn ->
          fast_retry = [retry: true, max_retries: 1, req_options: [retry_delay: 0]]

          stub_responses([{500, %{}}, {500, %{}}])
          on_500 = Claude.complete("x", fast_retry)

          Req.Test.stub(Claude, &Req.Test.transport_error(&1, :timeout))
          on_timeout = Claude.complete("x", fast_retry)

          Req.Test.stub(Claude, fn conn ->
            conn
            |> Plug.Conn.put_resp_content_type("application/json")
            |> Plug.Conn.send_resp(200, "{not json")
          end)

          on_bad_body = Claude.complete("x", [])

          [on_500, on_timeout, on_bad_body]
        end)

      refute log <> inspect(results) =~ @test_key
    end
  end
end
