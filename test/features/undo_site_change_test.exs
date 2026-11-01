# STORY-010 — Undo a change
#
# Entry point: `live "/companies/:id/activity"` (FirmosWeb.CompanyLive.Activity)
# behind `:require_authenticated_user`; the owner clicks `#undo-entry-<id>`.
# The result is observed on the public page a customer gets from
# `<slug>.localhost` (FirmosWeb.Plugs.SiteHost, driven by `conn.host`) and
# through the `Firmos.Sites` and `Firmos.Activity` public APIs.
defmodule FirmosWeb.Features.UndoSiteChangeTest do
  @moduledoc "Feature: an owner undoes the latest change of their website"
  use FirmosWeb.ConnCase, async: true

  import Firmos.CompaniesFixtures
  import Firmos.PlansFixtures
  import Firmos.SitesFixtures
  import Mox
  import Phoenix.LiveViewTest

  alias Firmos.Activity
  alias Firmos.Sites

  setup :verify_on_exit!

  defp run_ai_jobs, do: Oban.drain_queue(queue: :ai, with_safety: false)

  defp company_with_draft(scope) do
    company = company_fixture(scope)
    expect_ai_reply({:ok, plan_json()})
    %{success: 1} = run_ai_jobs()
    {:ok, _site} = Sites.request_generation(scope, company)
    expect_ai_reply({:ok, site_json()})
    %{success: 1} = run_ai_jobs()
    company
  end

  # Version 1 (generated) published, then version 2 (edited) published.
  defp published_with_two_versions(scope, slug) do
    company = company_with_draft(scope)
    {:ok, site} = Sites.set_slug(scope, Sites.get_site(scope, company), slug)
    {:ok, site} = Sites.publish(scope, site)

    {:ok, site} =
      Sites.update_content(scope, site, %{"hero" => %{"headline" => "Nowy nagłówek"}})

    {:ok, _site} = Sites.publish(scope, site)
    company
  end

  defp latest_entry(scope, company, action) do
    scope |> Activity.list_for_company(company) |> Enum.find(&(&1.action == action))
  end

  defp click_undo(view, entry) do
    view |> element("#undo-entry-#{entry.id}") |> render_click()
    render(view)
  end

  # A customer: a fresh connection without the owner's session.
  defp visit(host) do
    build_conn()
    |> Map.put(:host, host)
    |> get("/")
  end

  defp headline(conn) do
    conn.resp_body
    |> LazyHTML.from_document()
    |> LazyHTML.query("#site-hero h1")
    |> LazyHTML.text()
  end

  # ---------------------------------------------------------------------
  # HAPPY PATH
  # ---------------------------------------------------------------------

  describe "Scenario: AC1 — undo is offered on the latest change" do
    @describetag :skip
    setup :register_and_log_in_user

    setup %{conn: conn, scope: scope} do
      company = published_with_two_versions(scope, "piekarnia")
      {:ok, view, _html} = live(conn, ~p"/companies/#{company.id}/activity")

      %{
        view: view,
        latest: latest_entry(scope, company, :site_published),
        older: latest_entry(scope, company, :site_updated)
      }
    end

    test "offers undo on the latest change", %{view: view, latest: latest} do
      assert has_element?(view, "#undo-entry-#{latest.id}")
    end

    test "offers no undo on an older change", %{view: view, older: older} do
      refute has_element?(view, "#undo-entry-#{older.id}")
    end
  end

  describe "Scenario: AC1 — the owner undoes the latest change of a published site" do
    @describetag :skip
    setup :register_and_log_in_user

    setup %{conn: conn, scope: scope} do
      company = published_with_two_versions(scope, "piekarnia")
      {:ok, view, _html} = live(conn, ~p"/companies/#{company.id}/activity")
      click_undo(view, latest_entry(scope, company, :site_published))

      %{site: Sites.get_site(scope, company), public: visit("piekarnia.localhost")}
    end

    test "the public page shows the previous headline again", %{public: public} do
      assert headline(public) =~ site_attrs()["hero"]["headline"]
    end

    test "stores the restored content as a new undo version", %{site: site} do
      assert %{number: 3, source: :undo} = site.current_version
    end

    test "restores the previous version's content", %{site: site} do
      assert site.current_version.content.hero.headline == site_attrs()["hero"]["headline"]
    end

    test "makes the restored version the live one", %{site: site} do
      assert site.published_version_id == site.current_version_id
    end
  end

  describe "Scenario: AC2 — the owner opens the activity log after undoing" do
    @describetag :skip
    setup :register_and_log_in_user

    setup %{conn: conn, scope: scope} do
      company = published_with_two_versions(scope, "piekarnia")
      original = latest_entry(scope, company, :site_published)
      {:ok, view, _html} = live(conn, ~p"/companies/#{company.id}/activity")
      click_undo(view, original)
      {:ok, view, _html} = live(conn, ~p"/companies/#{company.id}/activity")

      %{view: view, original: original, undo: latest_entry(scope, company, :site_undone)}
    end

    test "lists the undo entry", %{view: view, undo: undo} do
      assert has_element?(view, "#activities-#{undo.id}")
    end

    test "records which change was undone", %{undo: undo, original: original} do
      assert undo.metadata["reverts_entry_id"] == original.id
    end

    test "links the undo entry to the original change",
         %{view: view, undo: undo, original: original} do
      assert has_element?(
               view,
               ~s(#activities-#{undo.id}-reverts[href="#activities-#{original.id}"])
             )
    end

    test "offers no undo of the undo", %{view: view} do
      refute has_element?(view, "[id^=undo-entry-]")
    end
  end

  # ---------------------------------------------------------------------
  # SAD PATH
  # ---------------------------------------------------------------------

  describe "Scenario: AC3 — rejecting undo on a site with a single version" do
    @describetag :skip
    setup :register_and_log_in_user

    setup %{conn: conn, scope: scope} do
      company = company_with_draft(scope)
      {:ok, view, _html} = live(conn, ~p"/companies/#{company.id}/activity")

      %{view: view}
    end

    test "offers no undo action", %{view: view} do
      refute has_element?(view, "[id^=undo-entry-]")
    end
  end
end
