defmodule FirmosWeb.DashboardLiveTest do
  use FirmosWeb.ConnCase, async: true

  import Firmos.CompaniesFixtures
  import Phoenix.LiveViewTest

  setup :register_and_log_in_user

  test "shows the empty state when the owner has no company or idea", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/dashboard")

    assert has_element?(view, "#dashboard-empty")
    refute has_element?(view, "#current-company")
  end

  test "escapes the idea text in the description", %{conn: conn, scope: scope} do
    company_fixture(scope, "<script>alert('x')</script> piekarnia w Krakowie")

    {:ok, _view, html} = live(conn, ~p"/dashboard")

    refute html =~ "<script>alert"
  end
end
