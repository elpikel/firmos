defmodule FirmosWeb.HomeLiveTest do
  use FirmosWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Firmos.Ideas

  @valid_idea "Studio jogi online dla zapracowanych rodziców z małych miast."

  describe "signed-in owner submits an idea" do
    setup :register_and_log_in_user

    test "attaches it to the owner and goes to the dashboard", %{conn: conn, scope: scope} do
      {:ok, view, _html} = live(conn, ~p"/")

      assert {:error, {:live_redirect, %{to: "/dashboard"}}} =
               view
               |> form("#idea-form", idea: %{text: @valid_idea})
               |> render_submit()

      assert Ideas.latest_unclaimed_for_user(scope).text == @valid_idea
    end
  end

  describe "validation" do
    test "shows the length error on change", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      view
      |> form("#idea-form", idea: %{text: "za krótko"})
      |> render_change()

      assert has_element?(view, "#idea-form", "podaj więcej szczegółów")
    end

    test "rejects a NUL byte on submit with a Polish error", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      view
      |> form("#idea-form", idea: %{text: @valid_idea <> <<0>>})
      |> render_submit()

      assert has_element?(view, "#idea-form", "zawiera niedozwolone znaki")
    end
  end
end
