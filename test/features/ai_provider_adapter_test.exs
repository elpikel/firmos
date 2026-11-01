# STORY-003 — AI provider adapter
#
# Entry point: `Firmos.AI.complete/2` (the public facade). AC1/AC2 drive the
# real `Firmos.AI.Claude` adapter with `Req.Test` stubs in place of the
# Anthropic API; AC3 proves the facade goes to the Mox mock in test.
defmodule Firmos.Features.AiProviderAdapterTest do
  @moduledoc "Feature: AI content comes from one reliable provider integration"
  use ExUnit.Case, async: true

  alias Firmos.AI.Claude

  setup do
    Mox.verify_on_exit!()
  end

  defp stub_messages_api(status, response_body) do
    test_pid = self()

    Req.Test.stub(Claude, fn conn ->
      {:ok, raw, conn} = Plug.Conn.read_body(conn)
      send(test_pid, {:anthropic_request, conn, Jason.decode!(raw)})

      conn
      |> Plug.Conn.put_status(status)
      |> Req.Test.json(response_body)
    end)
  end

  defp completion_body(texts) do
    %{
      "type" => "message",
      "role" => "assistant",
      "content" =>
        Enum.map(texts, &%{"type" => "text", "text" => &1}) ++
          [%{"type" => "tool_use", "id" => "toolu_1", "name" => "noop", "input" => %{}}]
    }
  end

  # ---------------------------------------------------------------------
  # HAPPY PATH
  # ---------------------------------------------------------------------

  describe "Scenario: AC1 — the app requests a completion with a configured key" do
    setup do
      stub_messages_api(200, completion_body(["Plan dla ", "piekarni"]))
      result = Claude.complete("Napisz plan", system: "Jesteś doradcą")
      assert_received {:anthropic_request, conn, body}

      %{result: result, conn: conn, body: body}
    end

    test "returns the joined text blocks", %{result: result} do
      assert result == {:ok, "Plan dla piekarni"}
    end

    test "posts to the Messages API", %{conn: conn} do
      assert {conn.method, conn.request_path} == {"POST", "/v1/messages"}
    end

    test "authenticates with the configured key", %{conn: conn} do
      assert Plug.Conn.get_req_header(conn, "x-api-key") == ["test-anthropic-key"]
    end

    test "pins the API version", %{conn: conn} do
      assert Plug.Conn.get_req_header(conn, "anthropic-version") == ["2023-06-01"]
    end

    test "sends JSON", %{conn: conn} do
      assert ["application/json" <> _] = Plug.Conn.get_req_header(conn, "content-type")
    end

    test "sends the prompt as the user message", %{body: body} do
      assert body["messages"] == [%{"role" => "user", "content" => "Napisz plan"}]
    end

    test "sends the configured model", %{body: body} do
      assert body["model"] == "claude-sonnet-5-5"
    end

    test "sends the configured max_tokens", %{body: body} do
      assert is_integer(body["max_tokens"])
    end

    test "sends the system prompt", %{body: body} do
      assert body["system"] == "Jesteś doradcą"
    end
  end

  describe "Scenario: AC1 — a completion without a system prompt" do
    setup do
      stub_messages_api(200, completion_body(["ok"]))
      {:ok, _text} = Claude.complete("Napisz plan", [])
      assert_received {:anthropic_request, _conn, body}

      %{body: body}
    end

    test "omits the system field", %{body: body} do
      refute Map.has_key?(body, "system")
    end
  end

  describe "Scenario: AC3 — a feature generates AI content in the test environment" do
    setup do
      Mox.expect(Firmos.AI.Mock, :complete, fn "Napisz plan", [system: "s"] ->
        {:ok, "z mocka"}
      end)

      %{result: Firmos.AI.complete("Napisz plan", system: "s")}
    end

    test "the configured adapter is the Mox mock" do
      assert Application.fetch_env!(:firmos, Firmos.AI)[:adapter] == Firmos.AI.Mock
    end

    test "Firmos.AI.complete/2 answers from the mock", %{result: result} do
      assert result == {:ok, "z mocka"}
    end
  end

  # ---------------------------------------------------------------------
  # SAD PATH
  # ---------------------------------------------------------------------

  describe "Scenario: AC2 — rejecting a completion when the provider returns a 5xx" do
    setup do
      stub_messages_api(500, %{
        "type" => "error",
        "error" => %{"type" => "api_error", "message" => "Internal server error"}
      })

      %{result: Claude.complete("Napisz plan", [])}
    end

    test "returns the HTTP status as the error reason", %{result: result} do
      assert {:error, {:http_status, 500, _summary}} = result
    end
  end

  describe "Scenario: AC2 — rejecting a completion when the provider times out" do
    setup do
      Req.Test.stub(Claude, &Req.Test.transport_error(&1, :timeout))

      %{result: Claude.complete("Napisz plan", [])}
    end

    test "returns the timeout as the error reason", %{result: result} do
      assert result == {:error, :timeout}
    end
  end

  describe "Scenario: AC2 — rejecting a completion when no API key is configured" do
    setup do
      stub_messages_api(200, completion_body(["never"]))

      %{result: Claude.complete("Napisz plan", api_key: nil)}
    end

    test "returns :missing_api_key", %{result: result} do
      assert result == {:error, :missing_api_key}
    end

    test "never calls the provider" do
      refute_received {:anthropic_request, _conn, _body}
    end
  end
end
