# STORY-005 — Describe the business idea
#
# Entry point: `live "/"` (FirmosWeb.HomeLive) in the `:current_user`
# live_session, then `live "/users/register"` (UserLive.Registration) with the
# `?idea=<token>` the home page redirects to. Persistence is observed through
# the `Firmos.Ideas` public API.
defmodule FirmosWeb.Features.IdeaPromptTest do
  @moduledoc "Feature: a visitor describes their business idea in a single prompt"
  use FirmosWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Firmos.Accounts
  alias Firmos.Accounts.Scope
  alias Firmos.Ideas
  alias Firmos.Repo

  @moduletag :skip

  @valid_idea "Piekarnia rzemieślnicza w Krakowie z dostawą pieczywa na zamówienie."

  defp submit_idea(conn, text) do
    {:ok, view, _html} = live(conn, ~p"/")

    result =
      view
      |> form("#idea-form", idea: %{text: text})
      |> render_submit()

    %{view: view, result: result}
  end

  defp token_from({:error, {:live_redirect, %{to: to}}}) do
    %URI{query: query} = URI.parse(to)
    query |> URI.decode_query() |> Map.fetch!("idea")
  end

  # ---------------------------------------------------------------------
  # HAPPY PATH
  # ---------------------------------------------------------------------

  describe "Scenario: AC1 — a visitor opens the home page" do
    setup %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/")
      %{view: view, document: LazyHTML.from_document(html)}
    end

    test "shows the idea input", %{view: view} do
      assert has_element?(view, "#idea-form textarea#idea-input")
    end

    test "shows the submit button", %{view: view} do
      assert has_element?(view, "#idea-form #idea-submit")
    end

    test "the form has a single input", %{document: document} do
      fields =
        LazyHTML.query(document, "#idea-form textarea, #idea-form input:not([type=hidden])")

      assert Enum.count(fields) == 1
    end
  end

  describe "Scenario: AC2 — a visitor submits an idea of 20–2000 characters" do
    setup %{conn: conn} do
      %{result: result} = submit_idea(conn, @valid_idea)
      token = token_from(result)
      {:ok, register_view, _html} = live(conn, ~p"/users/register?idea=#{token}")

      %{result: result, token: token, register_view: register_view}
    end

    test "takes the visitor to the sign-up step", %{result: result} do
      assert {:error, {:live_redirect, %{to: "/users/register?idea=" <> _}}} = result
    end

    test "keeps the idea as a draft", %{token: token} do
      assert %{text: @valid_idea} = Ideas.get_draft_by_token(token)
    end

    test "shows the preserved idea on the sign-up step", %{register_view: register_view} do
      assert has_element?(register_view, "#preserved-idea", @valid_idea)
    end
  end

  describe "Scenario: AC2 — the visitor completes sign-up with the preserved idea" do
    setup %{conn: conn} do
      %{result: result} = submit_idea(conn, @valid_idea)
      token = token_from(result)
      email = "owner-#{System.unique_integer([:positive])}@example.com"

      {:ok, register_view, _html} = live(conn, ~p"/users/register?idea=#{token}")

      register_view
      |> form("#registration_form", user: %{email: email})
      |> render_submit()

      %{user: Accounts.get_user_by_email(email), token: token}
    end

    test "attaches the idea to the new owner", %{user: user} do
      assert %{text: @valid_idea} = Ideas.latest_unclaimed_for_user(Scope.for_user(user))
    end

    test "spends the draft token", %{token: token} do
      refute Ideas.get_draft_by_token(token)
    end
  end

  # ---------------------------------------------------------------------
  # SAD PATH
  # ---------------------------------------------------------------------

  describe "Scenario: AC3 — a visitor submits an idea shorter than 20 characters" do
    setup %{conn: conn} do
      submit_idea(conn, "Mała piekarnia")
    end

    test "asks for more detail", %{view: view} do
      assert has_element?(view, "#idea-form", "podaj więcej szczegółów")
    end

    test "stays on the home page", %{result: result} do
      assert is_binary(result)
    end

    test "does not save a draft" do
      assert Repo.aggregate("ideas", :count) == 0
    end
  end

  describe "Scenario: AC4 — a visitor submits an idea longer than 2000 characters" do
    setup %{conn: conn} do
      submit_idea(conn, String.duplicate("ż", 2001))
    end

    test "states the limit", %{view: view} do
      assert has_element?(view, "#idea-form", "maksymalnie 2000 znaków")
    end

    test "stays on the home page", %{result: result} do
      assert is_binary(result)
    end

    test "does not save a draft" do
      assert Repo.aggregate("ideas", :count) == 0
    end
  end
end
