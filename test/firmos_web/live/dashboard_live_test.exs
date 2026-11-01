defmodule FirmosWeb.DashboardLiveTest do
  use FirmosWeb.ConnCase, async: true

  import Firmos.CompaniesFixtures
  import Firmos.PlansFixtures
  import Firmos.SitesFixtures
  import Phoenix.LiveViewTest

  alias Firmos.Plans
  alias Firmos.Sites

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

  test "shows a failed plan with a hint to try again", %{conn: conn, scope: scope} do
    company = company_fixture(scope)
    expect_ai_reply({:error, :timeout})
    {:error, _} = scope |> Plans.current_plan(company) |> Map.fetch!(:id) |> Plans.generate_plan()

    {:ok, view, _html} = live(conn, ~p"/dashboard")

    assert has_element?(view, "#plan-status #plan-failed")
  end

  describe "the website card" do
    setup %{conn: conn, scope: scope} do
      company = company_fixture(scope)
      expect_ai_reply({:ok, plan_json()})
      %{success: 1} = Oban.drain_queue(queue: :ai, with_safety: false)
      {:ok, view, _html} = live(conn, ~p"/dashboard")
      {:ok, _site} = Sites.request_generation(scope, company)
      %{view: view}
    end

    test "shows the website as generating without a reload", %{view: view} do
      assert has_element?(view, "#dashboard-site-status[data-status=generating]")
    end

    test "shows the generated draft without a reload", %{view: view} do
      expect_ai_reply({:ok, site_json()})
      %{success: 1} = Oban.drain_queue(queue: :ai, with_safety: false)

      assert has_element?(view, "#dashboard-site-status[data-status=draft]")
    end
  end

  test "moves its subscriptions to the selected company", %{conn: conn, scope: scope} do
    older = company_fixture(scope)
    newest = company_fixture(scope)
    {:ok, view, _html} = live(conn, ~p"/dashboard")

    view
    |> form("#company-switcher", switcher: %{company: older.id})
    |> render_change()

    assert Enum.sort(Registry.keys(Firmos.PubSub, view.pid)) ==
             Enum.sort(["company:#{older.id}:plans", "company:#{older.id}:site"])

    refute "company:#{newest.id}:plans" in Registry.keys(Firmos.PubSub, view.pid)
  end
end
