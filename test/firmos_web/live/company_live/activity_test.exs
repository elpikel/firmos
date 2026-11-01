defmodule FirmosWeb.CompanyLive.ActivityTest do
  use FirmosWeb.ConnCase, async: true

  import Firmos.CompaniesFixtures
  import Firmos.PlansFixtures
  import Firmos.SitesFixtures
  import Mox
  import Phoenix.LiveViewTest

  alias Firmos.Activity
  alias Firmos.Activity.Entry
  alias Firmos.Companies
  alias Firmos.Plans
  alias Firmos.Repo
  alias Firmos.Sites

  setup :register_and_log_in_user

  setup %{scope: scope} do
    %{company: company_fixture(scope)}
  end

  defp newest_row(scope, company) do
    [newest | _] = Activity.list_for_company(scope, company)
    "#activities-#{newest.id}"
  end

  test "renders an owner's profile change in Polish, old to new", %{
    conn: conn,
    scope: scope,
    company: company
  } do
    {:ok, _} = Companies.update_company(scope, company, %{city: "Kraków"})
    {:ok, view, _html} = live(conn, ~p"/companies/#{company.id}/activity")
    row = newest_row(scope, company)

    assert has_element?(view, "#{row} [data-role=action]", "Zaktualizowano profil")
    assert has_element?(view, "#{row} [data-role=actor]", "Właściciel")
    assert has_element?(view, "#{row} [data-role=summary]", "Miasto")
    assert has_element?(view, "#{row} [data-role=summary]", "(puste)")
    assert has_element?(view, "#{row} time", "UTC")
  end

  test "renders the company creation with its name", %{conn: conn, scope: scope, company: company} do
    {:ok, view, _html} = live(conn, ~p"/companies/#{company.id}/activity")

    assert has_element?(
             view,
             "#{newest_row(scope, company)} [data-role=summary]",
             "Utworzono firmę „Moja firma”."
           )
  end

  test "renders an agent's action as the AI agent", %{conn: conn, scope: scope, company: company} do
    {:ok, _} = Activity.record(company, :agent, :company_updated)
    {:ok, view, _html} = live(conn, ~p"/companies/#{company.id}/activity")
    row = newest_row(scope, company)

    assert has_element?(view, "#{row} [data-role=actor]", "Agent AI")
    assert has_element?(view, "#{row} [data-role=summary]", "Zaktualizowano profil firmy.")
  end

  test "escapes owner-supplied values", %{conn: conn, scope: scope, company: company} do
    {:ok, _} = Companies.update_company(scope, company, %{name: "<script>alert(1)</script>"})
    {:ok, view, _html} = live(conn, ~p"/companies/#{company.id}/activity")

    refute has_element?(view, "#activities script")
  end

  test "shows the empty state without entries", %{conn: conn, company: company} do
    Repo.delete_all(Entry)
    {:ok, view, _html} = live(conn, ~p"/companies/#{company.id}/activity")

    assert has_element?(view, "#activities-empty")
    refute has_element?(view, "#activities > article")
  end

  describe "paging" do
    setup %{scope: scope, company: company} do
      # 51 agent entries + the company_created entry = 52, one page is 50.
      for _ <- 1..51, do: {:ok, _} = Activity.record(company, :agent, :company_updated)
      [_ | _] = entries = Activity.list_for_company(scope, company, limit: 100)
      %{entries: entries}
    end

    defp row_ids(view) do
      view
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("#activities > article")
      |> LazyHTML.attribute("id")
    end

    defp dom_ids(entries), do: Enum.map(entries, &"activities-#{&1.id}")

    test "shows the newest page with a load-more button", %{
      conn: conn,
      company: company,
      entries: entries
    } do
      {:ok, view, _html} = live(conn, ~p"/companies/#{company.id}/activity")

      assert row_ids(view) == entries |> Enum.take(50) |> dom_ids()
      assert has_element?(view, "#activities-load-more")
    end

    test "load more appends the older entries in order and hides the button", %{
      conn: conn,
      company: company,
      entries: entries
    } do
      {:ok, view, _html} = live(conn, ~p"/companies/#{company.id}/activity")
      view |> element("#activities-load-more") |> render_click()

      assert row_ids(view) == dom_ids(entries)
      refute has_element?(view, "#activities-load-more")
    end
  end

  describe "undo" do
    setup :verify_on_exit!

    setup %{conn: conn, scope: scope, company: company} do
      expect_ai_reply({:ok, plan_json()})
      {:ok, _plan} = Plans.generate_plan(Plans.current_plan(scope, company).id)
      {:ok, site} = Sites.request_generation(scope, company)
      expect_ai_reply({:ok, site_json()})
      {:ok, _version} = Sites.generate_site(site.id, 1)

      {:ok, site} =
        Sites.update_content(scope, Sites.get_site(scope, company), %{
          "hero" => %{"headline" => "Drugi"}
        })

      %{id: edit} = Sites.undoable_entry(scope, company)
      {:ok, view, _html} = live(conn, ~p"/companies/#{company.id}/activity")

      %{site: site, edit: edit, view: view}
    end

    test "a change elsewhere moves the undo button to the new entry",
         %{view: view, scope: scope, company: company, site: site, edit: edit} do
      {:ok, _site} = Sites.update_content(scope, site, %{"hero" => %{"headline" => "Trzeci"}})
      %{id: newest} = Sites.undoable_entry(scope, company)

      assert has_element?(view, "#activities-#{newest} #undo-entry-#{newest}")
      refute has_element?(view, "#undo-entry-#{edit}")
    end

    test "a stale undo click changes nothing",
         %{view: view, scope: scope, company: company, site: site, edit: edit} do
      {:ok, _site} = Sites.update_content(scope, site, %{"hero" => %{"headline" => "Trzeci"}})

      render_hook(view, "undo", %{"id" => to_string(edit)})

      assert has_element?(view, "#flash-error", "Nie ma czego cofnąć")
      assert Sites.get_site(scope, company).current_version.number == 3
    end

    test "a forged entry id changes nothing", %{view: view, scope: scope, company: company} do
      render_hook(view, "undo", %{"id" => "not-an-id"})

      assert has_element?(view, "#flash-error")
      assert Sites.get_site(scope, company).current_version.number == 2
    end

    test "a new entry is prepended and loaded pages stay",
         %{conn: conn, scope: scope, company: company, site: site} do
      for _ <- 1..51, do: {:ok, _} = Activity.record(company, :agent, :company_updated)
      {:ok, view, _html} = live(conn, ~p"/companies/#{company.id}/activity")
      view |> element("#activities-load-more") |> render_click()
      before = row_ids(view)

      {:ok, _site} = Sites.update_content(scope, site, %{"hero" => %{"headline" => "Trzeci"}})
      %{id: newest} = Sites.undoable_entry(scope, company)

      assert row_ids(view) == ["activities-#{newest}" | before]
      assert has_element?(view, "#undo-entry-#{newest}")
    end

    test "undoing prepends the undo entry without an undo button",
         %{view: view, scope: scope, company: company, edit: edit} do
      view |> element("#undo-entry-#{edit}") |> render_click()
      [undo | _] = Activity.list_for_company(scope, company)

      assert [first | _] = row_ids(view)
      assert {first, undo.action} == {"activities-#{undo.id}", :site_undone}
      refute has_element?(view, "[id^=undo-entry-]")
    end
  end
end
