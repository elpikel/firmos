defmodule FirmosWeb.CompanyLive.SiteTest do
  use FirmosWeb.ConnCase, async: true
  use Oban.Testing, repo: Firmos.Repo

  import Firmos.CompaniesFixtures
  import Firmos.PlansFixtures
  import Firmos.SitesFixtures
  import Mox
  import Phoenix.LiveViewTest

  alias Firmos.Plans
  alias Firmos.Sites
  alias Firmos.Sites.GenerateWorker

  setup :verify_on_exit!
  setup :register_and_log_in_user

  defp ready_plan(scope, company) do
    expect_ai_reply({:ok, plan_json()})
    {:ok, _plan} = Plans.generate_plan(Plans.current_plan(scope, company).id)
  end

  test "a forged generate without a ready plan is refused", %{conn: conn, scope: scope} do
    company = company_fixture(scope)
    {:ok, view, _html} = live(conn, ~p"/companies/#{company.id}/site")

    render_hook(view, "generate", %{})
    assert has_element?(view, "#flash-error")
    assert Sites.get_site(scope, company) == nil
    refute_enqueued(worker: GenerateWorker)
  end

  test "an unknown event changes nothing", %{conn: conn, scope: scope} do
    company = company_fixture(scope)
    {:ok, view, _html} = live(conn, ~p"/companies/#{company.id}/site")

    render_hook(view, "delete_everything", %{"id" => "1"})
    assert has_element?(view, "#site-needs-plan")
  end

  test "a draft offers to regenerate, keeping the older version", %{conn: conn, scope: scope} do
    company = company_fixture(scope)
    ready_plan(scope, company)
    {:ok, site} = Sites.request_generation(scope, company)
    expect_ai_reply({:ok, site_json()})
    {:ok, _version} = Sites.generate_site(site.id, 1)

    {:ok, view, _html} = live(conn, ~p"/companies/#{company.id}/site")
    assert has_element?(view, "#site-create[data-confirm]")

    view |> element("#site-create") |> render_click()
    assert has_element?(view, "#site-progress")
    assert has_element?(view, "#site-draft")
  end

  test "a plan becoming ready enables create website live", %{conn: conn, scope: scope} do
    company = company_fixture(scope)
    {:ok, view, _html} = live(conn, ~p"/companies/#{company.id}/site")
    assert has_element?(view, "#site-create[disabled]")

    ready_plan(scope, company)

    refute has_element?(view, "#site-create[disabled]")
  end
end
