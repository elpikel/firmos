defmodule FirmosWeb.CompanyLive.ApprovalsTest do
  use FirmosWeb.ConnCase, async: true

  import Firmos.CompaniesFixtures
  import Firmos.PlansFixtures
  import Firmos.SitesFixtures
  import Mox
  import Phoenix.LiveViewTest

  alias Firmos.Approvals
  alias Firmos.Plans
  alias Firmos.Sites

  setup :verify_on_exit!
  setup :register_and_log_in_user

  # A company whose site has version 1 as its current draft, without a slug.
  setup %{scope: scope} do
    company = company_fixture(scope)
    expect_ai_reply({:ok, plan_json()})
    {:ok, _plan} = Plans.generate_plan(Plans.current_plan(scope, company).id)
    {:ok, site} = Sites.request_generation(scope, company)
    expect_ai_reply({:ok, site_json()})
    {:ok, _version} = Sites.generate_site(site.id, 1)
    %{company: company}
  end

  defp request!(scope, company) do
    {:ok, approval} =
      Approvals.request_publish(company, Sites.get_site(scope, company).current_version)

    approval
  end

  test "shows the empty states", %{conn: conn, company: company} do
    {:ok, view, _html} = live(conn, ~p"/companies/#{company.id}/approvals")

    assert has_element?(view, "#approvals-pending-empty")
    assert has_element?(view, "#approvals-history-empty")
  end

  test "shows a new request live", %{conn: conn, scope: scope, company: company} do
    {:ok, view, _html} = live(conn, ~p"/companies/#{company.id}/approvals")
    approval = request!(scope, company)
    :ok = Approvals.broadcast_updated(company.id)

    assert has_element?(view, "#approve-#{approval.id}")
  end

  test "moves a request to the history live when the owner edits the draft",
       %{conn: conn, scope: scope, company: company} do
    approval = request!(scope, company)
    {:ok, view, _html} = live(conn, ~p"/companies/#{company.id}/approvals")
    site = Sites.get_site(scope, company)
    {:ok, _site} = Sites.update_content(scope, site, %{"hero" => %{"headline" => "Zmiana"}})

    refute has_element?(view, "#approvals-pending #approvals-#{approval.id}")
    assert has_element?(view, ~s(#decided-#{approval.id} [data-status="superseded"]))
  end

  test "links to the site page when the site has no address yet",
       %{conn: conn, scope: scope, company: company} do
    approval = request!(scope, company)
    {:ok, view, _html} = live(conn, ~p"/companies/#{company.id}/approvals")
    view |> element("#approve-#{approval.id}") |> render_click()

    assert has_element?(view, ~s(#approvals-site-link[href="/companies/#{company.id}/site"]))
    assert has_element?(view, "#approve-#{approval.id}")
  end

  test "ignores a malformed or missing id", %{conn: conn, scope: scope, company: company} do
    approval = request!(scope, company)
    {:ok, view, _html} = live(conn, ~p"/companies/#{company.id}/approvals")
    render_hook(view, "approve", %{"id" => "not-an-id"})
    render_hook(view, "reject", %{})

    assert {:ok, %{status: :pending}} = Approvals.get_approval(scope, approval.id)
  end

  test "the dashboard badge follows the queue live",
       %{conn: conn, scope: scope, company: company} do
    {:ok, view, _html} = live(conn, ~p"/dashboard?company=#{company.id}")
    assert has_element?(view, ~s(#dashboard-approvals[data-count="0"]))

    request!(scope, company)
    :ok = Approvals.broadcast_updated(company.id)

    assert has_element?(view, ~s(#dashboard-approvals[data-count="1"]))
  end
end
