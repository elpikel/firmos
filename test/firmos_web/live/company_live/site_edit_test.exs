defmodule FirmosWeb.CompanyLive.SiteEditTest do
  use FirmosWeb.ConnCase, async: true

  import Firmos.CompaniesFixtures
  import Firmos.PlansFixtures
  import Firmos.SitesFixtures
  import Mox
  import Phoenix.LiveViewTest

  alias Firmos.Plans
  alias Firmos.Sites

  setup :verify_on_exit!
  setup :register_and_log_in_user

  setup %{conn: conn, scope: scope} do
    company = company_fixture(scope)
    expect_ai_reply({:ok, plan_json()})
    {:ok, _plan} = Plans.generate_plan(Plans.current_plan(scope, company).id)
    {:ok, site} = Sites.request_generation(scope, company)
    expect_ai_reply({:ok, site_json()})
    {:ok, _version} = Sites.generate_site(site.id, 1)
    {:ok, view, _html} = live(conn, ~p"/companies/#{company.id}/site/edit")

    %{company: company, view: view}
  end

  defp save_in_another_tab(scope, company, headline) do
    site = Sites.get_site(scope, company)
    {:ok, _site} = Sites.update_content(scope, site, %{"hero" => %{"headline" => headline}})
  end

  test "an unchanged site shows no stale notice", %{view: view} do
    refute has_element?(view, "#site-edit-stale")
  end

  test "a change elsewhere shows the stale notice and disables saving",
       %{view: view, scope: scope, company: company} do
    save_in_another_tab(scope, company, "Z innej karty")

    assert has_element?(view, "#site-edit-stale #site-edit-reload")
    assert has_element?(view, "#site-edit-save[disabled]")
  end

  test "a stale save doesn't overwrite the newer version",
       %{view: view, scope: scope, company: company} do
    save_in_another_tab(scope, company, "Z innej karty")

    view
    |> form("#site-content-form", content: %{hero: %{headline: "Ze starego edytora"}})
    |> render_submit()

    assert has_element?(view, "#flash-error", "Strona zmieniła się w międzyczasie")

    assert %{number: 2, content: %{hero: %{headline: "Z innej karty"}}} =
             Sites.get_site(scope, company).current_version
  end
end
