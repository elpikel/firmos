# STORY-011 — Company dashboard
#
# Entry point: `live "/dashboard"` (FirmosWeb.DashboardLive) behind
# `:require_authenticated_user`; the selected company is the `?company=<id>`
# query param, set by the `#company-switcher` form. Plans and sites are
# generated through the Oban `ai` queue with the AI behind its Mox mock.
defmodule FirmosWeb.Features.CompanyDashboardTest do
  @moduledoc "Feature: an owner sees the state of their business on one dashboard"
  use FirmosWeb.ConnCase, async: true

  import Firmos.AccountsFixtures
  import Firmos.CompaniesFixtures
  import Firmos.PlansFixtures
  import Firmos.SitesFixtures
  import Mox
  import Phoenix.LiveViewTest

  alias Firmos.Activity
  alias Firmos.Companies
  alias Firmos.Plans
  alias Firmos.Sites
  alias FirmosWeb.SiteDomain

  setup :verify_on_exit!

  defp run_ai_jobs, do: Oban.drain_queue(queue: :ai, with_safety: false)

  defp named_company(scope, name) do
    {:ok, company} = Companies.update_company(scope, company_fixture(scope), %{name: name})
    company
  end

  # A ready plan and a published site: 4 log entries (created, plan, site,
  # published), plus 2 profile edits = 6, one more than the dashboard shows.
  defp published_company(scope, slug) do
    company = company_fixture(scope)
    expect_ai_reply({:ok, plan_json()})
    %{success: 1} = run_ai_jobs()
    {:ok, _site} = Sites.request_generation(scope, company)
    expect_ai_reply({:ok, site_json()})
    %{success: 1} = run_ai_jobs()
    {:ok, site} = Sites.set_slug(scope, Sites.get_site(scope, company), slug)
    {:ok, _site} = Sites.publish(scope, site)
    {:ok, company} = Companies.update_company(scope, company, %{city: "Kraków"})
    {:ok, company} = Companies.update_company(scope, company, %{industry: "Piekarnictwo"})
    company
  end

  defp generate_plan(scope, company, reply) do
    expect_ai_reply(reply)
    scope |> Plans.current_plan(company) |> Map.fetch!(:id) |> Plans.generate_plan()
  end

  defp switch_to(view, company) do
    view |> form("#company-switcher", switcher: %{company: company.id}) |> render_change()
  end

  defp count(view, selector) do
    view |> render() |> LazyHTML.from_fragment() |> LazyHTML.query(selector) |> Enum.count()
  end

  # ---------------------------------------------------------------------
  # HAPPY PATH
  # ---------------------------------------------------------------------

  describe "Scenario: AC1 — the owner opens the dashboard of a company with a plan and a published site" do
    setup :register_and_log_in_user

    setup %{conn: conn, scope: scope} do
      company = published_company(scope, "piekarnia")
      entries = Activity.list_for_company(scope, company)
      {:ok, view, _html} = live(conn, ~p"/dashboard")

      %{
        view: view,
        company: company,
        newest_entry: List.first(entries),
        oldest_entry: List.last(entries),
        public_url: SiteDomain.public_url("piekarnia")
      }
    end

    test "shows the plan as ready", %{view: view} do
      assert has_element?(view, "#dashboard-plan #plan-status #plan-ready")
    end

    test "summarizes the plan's offer", %{view: view} do
      assert has_element?(view, "#dashboard-plan-offer", plan_attrs()["offer"])
    end

    test "summarizes the plan's target customer", %{view: view} do
      assert has_element?(
               view,
               "#dashboard-plan-target-customer",
               plan_attrs()["target_customer"]
             )
    end

    test "shows the plan's rating state", %{view: view} do
      assert has_element?(view, "#dashboard-plan-rating[data-rating=none]")
    end

    test "links to the plan", %{view: view, company: company} do
      assert has_element?(view, ~s(#company-plan-link[href="/companies/#{company.id}/plan"]))
    end

    test "shows the site as published", %{view: view} do
      assert has_element?(view, "#dashboard-site-status[data-status=published]")
    end

    test "links to the public site", %{view: view, public_url: public_url} do
      assert has_element?(view, ~s(#dashboard-site-link[href="#{public_url}"]))
    end

    test "shows the 5 latest activities", %{view: view} do
      assert count(view, "#dashboard-activity-entries > article") == 5
    end

    test "shows the newest activity", %{view: view, newest_entry: entry} do
      assert has_element?(view, "#dashboard-activity-#{entry.id}")
    end

    test "leaves out the oldest activity", %{view: view, oldest_entry: entry} do
      refute has_element?(view, "#dashboard-activity-#{entry.id}")
    end

    test "links to the full activity log", %{view: view, company: company} do
      assert has_element?(
               view,
               ~s(#company-activity-link[href="/companies/#{company.id}/activity"])
             )
    end
  end

  describe "Scenario: AC2 — an owner with two companies opens the dashboard" do
    setup :register_and_log_in_user

    setup %{conn: conn, scope: scope} do
      older = named_company(scope, "Piekarnia Zakwas")
      _newest = named_company(scope, "Kwiaciarnia Bukiet")
      {:ok, view, _html} = live(conn, ~p"/dashboard")
      %{view: view, older: older}
    end

    test "shows the newest company", %{view: view} do
      assert has_element?(view, "#current-company-name", "Kwiaciarnia Bukiet")
    end

    test "offers the other company in the switcher", %{view: view, older: older} do
      assert has_element?(view, ~s(#company-switcher option[value="#{older.id}"]))
    end
  end

  describe "Scenario: AC2 — the owner selects the other company" do
    setup :register_and_log_in_user

    setup %{conn: conn, scope: scope} do
      older = named_company(scope, "Piekarnia Zakwas")
      _newest = named_company(scope, "Kwiaciarnia Bukiet")
      older_entry = scope |> Activity.list_for_company(older) |> List.first()
      {:ok, view, _html} = live(conn, ~p"/dashboard")
      switch_to(view, older)
      %{view: view, older: older, older_entry: older_entry}
    end

    test "puts the company in the address", %{view: view, older: older} do
      assert_patch(view, ~p"/dashboard?company=#{older.id}")
    end

    test "shows that company", %{view: view} do
      assert has_element?(view, "#current-company-name", "Piekarnia Zakwas")
    end

    test "shows that company's activity", %{view: view, older_entry: entry} do
      assert has_element?(view, "#dashboard-activity-#{entry.id}")
    end

    test "links to that company's plan", %{view: view, older: older} do
      assert has_element?(view, ~s(#company-plan-link[href="/companies/#{older.id}/plan"]))
    end
  end

  describe "Scenario: AC2 — the owner opens a company's dashboard by its address" do
    setup :register_and_log_in_user

    setup %{conn: conn, scope: scope} do
      older = named_company(scope, "Piekarnia Zakwas")
      _newest = named_company(scope, "Kwiaciarnia Bukiet")
      {:ok, view, _html} = live(conn, ~p"/dashboard?company=#{older.id}")
      %{view: view}
    end

    test "shows that company", %{view: view} do
      assert has_element?(view, "#current-company-name", "Piekarnia Zakwas")
    end
  end

  describe "Scenario: AC2 — the selected company's plan finishes after a switch" do
    setup :register_and_log_in_user

    setup %{conn: conn, scope: scope} do
      older = named_company(scope, "Piekarnia Zakwas")
      _newest = named_company(scope, "Kwiaciarnia Bukiet")
      {:ok, view, _html} = live(conn, ~p"/dashboard")
      switch_to(view, older)
      {:ok, _plan} = generate_plan(scope, older, {:ok, plan_json()})
      %{view: view}
    end

    test "shows the plan as ready without a reload", %{view: view} do
      assert has_element?(view, "#dashboard-plan #plan-ready")
    end
  end

  describe "Scenario: AC2 — the previously shown company's plan finishes after a switch" do
    setup :register_and_log_in_user

    setup %{conn: conn, scope: scope} do
      older = named_company(scope, "Piekarnia Zakwas")
      newest = named_company(scope, "Kwiaciarnia Bukiet")
      {:ok, view, _html} = live(conn, ~p"/dashboard")
      switch_to(view, older)
      {:ok, _plan} = generate_plan(scope, newest, {:ok, plan_json()})
      %{view: view}
    end

    test "keeps showing the selected company's plan in progress", %{view: view} do
      assert has_element?(view, "#dashboard-plan #plan-progress")
    end
  end

  # ---------------------------------------------------------------------
  # SAD PATH
  # ---------------------------------------------------------------------

  describe "Scenario: AC3 — an owner with no companies opens the dashboard" do
    setup :register_and_log_in_user

    setup %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard")
      %{view: view}
    end

    test "shows the empty state", %{view: view} do
      assert has_element?(view, "#dashboard-empty")
    end

    test "prompts to describe a business idea", %{view: view} do
      assert has_element?(view, ~s(#dashboard-new-idea[href="/"]))
    end

    test "shows no company switcher", %{view: view} do
      refute has_element?(view, "#company-switcher")
    end
  end

  describe "Scenario: AC2 — rejecting another owner's company in the address" do
    setup :register_and_log_in_user

    setup %{scope: scope} do
      _own = company_fixture(scope)
      %{other_company: company_fixture(user_scope_fixture())}
    end

    test "responds with not found", %{conn: conn, other_company: other_company} do
      assert_raise Ecto.NoResultsError, fn ->
        live(conn, ~p"/dashboard?company=#{other_company.id}")
      end
    end
  end

  describe "Scenario: AC2 — rejecting a malformed company in the address" do
    setup :register_and_log_in_user

    setup %{scope: scope} do
      %{own: company_fixture(scope)}
    end

    test "responds with not found", %{conn: conn} do
      assert_raise Ecto.NoResultsError, fn -> live(conn, ~p"/dashboard?company=abc") end
    end
  end

  describe "Scenario: AC2 — rejecting a forged switch to another owner's company" do
    setup :register_and_log_in_user

    setup %{conn: conn, scope: scope} do
      _own = named_company(scope, "Piekarnia Zakwas")
      other_company = company_fixture(user_scope_fixture())
      {:ok, view, _html} = live(conn, ~p"/dashboard")

      render_hook(view, "switch_company", %{
        "switcher" => %{"company" => to_string(other_company.id)}
      })

      %{view: view}
    end

    test "keeps showing the owner's company", %{view: view} do
      assert has_element?(view, "#current-company-name", "Piekarnia Zakwas")
    end
  end
end
