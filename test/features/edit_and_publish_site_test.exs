# STORY-009 — Edit and publish the site
#
# Entry points: `live "/companies/:id/site/edit"` (FirmosWeb.CompanyLive.SiteEdit)
# and `live "/companies/:id/site"` (FirmosWeb.CompanyLive.Site) behind
# `:require_authenticated_user`, the preview controller, and the public page a
# customer gets from `<slug>.localhost` (FirmosWeb.Plugs.SiteHost in the
# Endpoint, driven by setting `conn.host`). Persistence is observed through
# the `Firmos.Sites` and `Firmos.Activity` public APIs.
defmodule FirmosWeb.Features.EditAndPublishSiteTest do
  @moduledoc "Feature: an owner edits their site and publishes it to a public URL"
  use FirmosWeb.ConnCase, async: true

  import Firmos.AccountsFixtures
  import Firmos.CompaniesFixtures
  import Firmos.PlansFixtures
  import Firmos.SitesFixtures
  import Mox
  import Phoenix.LiveViewTest

  alias Firmos.Activity
  alias Firmos.Sites

  setup :verify_on_exit!

  defp run_ai_jobs, do: Oban.drain_queue(queue: :ai, with_safety: false)

  # Wait until the LiveView has handled the broadcasts it triggered.
  defp settle(view), do: render(view)

  defp company_with_draft(scope) do
    company = company_fixture(scope)
    expect_ai_reply({:ok, plan_json()})
    %{success: 1} = run_ai_jobs()
    {:ok, _site} = Sites.request_generation(scope, company)
    expect_ai_reply({:ok, site_json()})
    %{success: 1} = run_ai_jobs()
    company
  end

  defp published_company(scope, slug) do
    company = company_with_draft(scope)
    {:ok, site} = Sites.set_slug(scope, Sites.get_site(scope, company), slug)
    {:ok, _site} = Sites.publish(scope, site)
    company
  end

  defp save_headline(conn, company, headline) do
    {:ok, view, _html} = live(conn, ~p"/companies/#{company.id}/site/edit")

    view
    |> form("#site-content-form", content: %{hero: %{headline: headline}})
    |> render_submit()
  end

  # A customer: a fresh connection without the owner's session.
  defp visit(host, method \\ :get) do
    build_conn()
    |> Map.put(:host, host)
    |> dispatch(@endpoint, method, "/")
  end

  defp document(conn), do: LazyHTML.from_document(conn.resp_body)

  defp text_of(document, selector) do
    document |> LazyHTML.query(selector) |> LazyHTML.text()
  end

  defp entry(scope, company, action) do
    scope |> Activity.list_for_company(company) |> Enum.find(&(&1.action == action))
  end

  # ---------------------------------------------------------------------
  # HAPPY PATH
  # ---------------------------------------------------------------------

  describe "Scenario: AC1 — the owner changes the hero headline and saves" do
    setup :register_and_log_in_user

    setup %{conn: conn, scope: scope} do
      company = company_with_draft(scope)
      save_headline(conn, company, "Najlepszy chleb w Krakowie")
      site = Sites.get_site(scope, company)

      %{
        site: site,
        entry: entry(scope, company, :site_updated),
        preview:
          conn
          |> get(~p"/companies/#{company.id}/site/preview")
          |> html_response(200)
          |> then(&LazyHTML.from_document/1)
      }
    end

    test "saves the edit as a new version", %{site: site} do
      assert %{number: 2, source: :edited} = site.current_version
    end

    test "keeps the rest of the content", %{site: site} do
      assert site.current_version.content.offer.title == site_attrs()["offer"]["title"]
    end

    test "the preview shows the new headline", %{preview: preview} do
      assert text_of(preview, "#site-hero h1") =~ "Najlepszy chleb w Krakowie"
    end

    test "records the owner's edit with the changed field", %{entry: entry, site: site} do
      version_id = site.current_version_id

      assert %{
               actor: :owner,
               subject_type: "site_version",
               subject_id: ^version_id,
               metadata: %{"fields" => ["hero.headline"]}
             } = entry
    end
  end

  describe "Scenario: AC1 — the website section links to the editor" do
    setup :register_and_log_in_user

    setup %{conn: conn, scope: scope} do
      company = company_with_draft(scope)
      {:ok, view, _html} = live(conn, ~p"/companies/#{company.id}/site")

      %{view: view, edit_path: ~p"/companies/#{company.id}/site/edit"}
    end

    test "offers the edit link", %{view: view, edit_path: edit_path} do
      assert has_element?(view, ~s(#site-edit-link[href="#{edit_path}"]))
    end
  end

  describe "Scenario: AC2 — the owner sets the slug and publishes" do
    setup :register_and_log_in_user

    setup %{conn: conn, scope: scope} do
      company = company_with_draft(scope)
      {:ok, view, _html} = live(conn, ~p"/companies/#{company.id}/site")
      view |> form("#site-slug-form", site: %{slug: "  Piekarnia "}) |> render_submit()
      view |> element("#site-publish") |> render_click()
      settle(view)
      public = visit("piekarnia.localhost")

      %{view: view, site: Sites.get_site(scope, company), public: public}
    end

    test "stores the normalized slug", %{site: site} do
      assert site.slug == "piekarnia"
    end

    test "publishes the current version", %{site: site} do
      assert %{status: :published, published_version_id: id, current_version_id: id} = site
    end

    test "shows the public URL", %{view: view} do
      assert has_element?(view, ~s(#site-public-url[href^="http://piekarnia.localhost"]))
    end

    test "a customer gets the page", %{public: public} do
      assert public.status == 200
    end

    test "a customer sees the published headline", %{public: public} do
      assert text_of(document(public), "#site-hero h1") =~ site_attrs()["hero"]["headline"]
    end

    test "the public page sets no session cookie", %{public: public} do
      assert get_resp_header(public, "set-cookie") == []
    end

    test "the public page carries no CSRF token", %{public: public} do
      assert public |> document() |> LazyHTML.query("meta[name=csrf-token]") |> Enum.empty?()
    end

    test "the public page loads no app JavaScript", %{public: public} do
      assert public |> document() |> LazyHTML.query("script") |> Enum.empty?()
    end
  end

  describe "Scenario: AC2 — draft edits after publishing wait for a republish" do
    setup :register_and_log_in_user

    setup %{conn: conn, scope: scope} do
      company = published_company(scope, "piekarnia")
      save_headline(conn, company, "Nowy nagłówek po publikacji")
      before_republish = visit("piekarnia.localhost")
      {:ok, view, _html} = live(conn, ~p"/companies/#{company.id}/site")
      unpublished_changes? = has_element?(view, "#site-unpublished-changes")
      view |> element("#site-publish") |> render_click()
      settle(view)

      %{
        before_republish: before_republish,
        unpublished_changes?: unpublished_changes?,
        after_republish: visit("piekarnia.localhost")
      }
    end

    test "the public page keeps the published headline", %{before_republish: public} do
      assert text_of(document(public), "#site-hero h1") =~ site_attrs()["hero"]["headline"]
    end

    test "the site page shows unpublished changes", %{unpublished_changes?: shown?} do
      assert shown?
    end

    test "republishing shows the new headline", %{after_republish: public} do
      assert text_of(document(public), "#site-hero h1") =~ "Nowy nagłówek po publikacji"
    end
  end

  describe "Scenario: AC2 — the app keeps its own hosts" do
    setup do
      published_company(user_scope_fixture(), "piekarnia")
      %{bare: visit("localhost"), www: visit("www.localhost")}
    end

    test "the bare base domain serves the app home", %{bare: bare} do
      assert bare |> document() |> LazyHTML.query("#home-hero") |> Enum.any?()
    end

    test "www serves the app home", %{www: www} do
      assert www |> document() |> LazyHTML.query("#home-hero") |> Enum.any?()
    end
  end

  describe "Scenario: AC3 — the owner opens the activity log after publishing" do
    setup :register_and_log_in_user

    setup %{conn: conn, scope: scope} do
      company = published_company(scope, "piekarnia")
      entry = entry(scope, company, :site_published)
      {:ok, view, _html} = live(conn, ~p"/companies/#{company.id}/activity")

      %{view: view, entry: entry}
    end

    test "records the owner publishing with the slug and version", %{entry: entry} do
      assert %{actor: :owner, metadata: %{"slug" => "piekarnia", "version" => 1}} = entry
    end

    test "lists a \"site published\" entry", %{view: view, entry: entry} do
      assert has_element?(view, "#activities-#{entry.id}")
    end
  end

  # ---------------------------------------------------------------------
  # SAD PATH
  # ---------------------------------------------------------------------

  describe "Scenario: AC4 — rejecting a customer on a site that was never published" do
    setup do
      scope = user_scope_fixture()
      company = company_with_draft(scope)
      {:ok, _site} = Sites.set_slug(scope, Sites.get_site(scope, company), "piekarnia")

      %{public: visit("piekarnia.localhost")}
    end

    test "responds with not found", %{public: public} do
      assert public.status == 404
    end
  end

  describe "Scenario: AC4 — rejecting a customer on an unknown slug" do
    setup do
      %{public: visit("nieznana.localhost")}
    end

    test "responds with not found", %{public: public} do
      assert public.status == 404
    end
  end

  describe "Scenario: AC4 — rejecting a non-GET request on a public site" do
    setup do
      published_company(user_scope_fixture(), "piekarnia")
      %{public: visit("piekarnia.localhost", :post)}
    end

    test "responds with method not allowed", %{public: public} do
      assert public.status == 405
    end
  end

  describe "Scenario: AC5 — rejecting a slug another company already uses" do
    setup :register_and_log_in_user

    setup %{conn: conn, scope: scope} do
      published_company(user_scope_fixture(), "piekarnia")
      company = company_with_draft(scope)
      {:ok, view, _html} = live(conn, ~p"/companies/#{company.id}/site")
      view |> form("#site-slug-form", site: %{slug: "piekarnia"}) |> render_submit()

      %{view: view, site: Sites.get_site(scope, company)}
    end

    test "shows a \"slug already taken\" error", %{view: view} do
      assert has_element?(view, "#site-slug-form", "ten adres jest już zajęty")
    end

    test "keeps the owner's slug unset", %{site: site} do
      assert site.slug == nil
    end
  end

  describe "Scenario: AC5 — rejecting a slug taken in another letter case" do
    setup do
      published_company(user_scope_fixture(), "piekarnia")
      scope = user_scope_fixture()
      company = company_with_draft(scope)

      %{result: Sites.set_slug(scope, Sites.get_site(scope, company), "PIEKARNIA")}
    end

    test "refuses the slug as taken", %{result: result} do
      assert {:error, %Ecto.Changeset{errors: [slug: {"slug already taken", _}]}} = result
    end
  end

  describe "Scenario: AC5 — rejecting a reserved slug" do
    setup :register_and_log_in_user

    setup %{conn: conn, scope: scope} do
      company = company_with_draft(scope)
      {:ok, view, _html} = live(conn, ~p"/companies/#{company.id}/site")
      view |> form("#site-slug-form", site: %{slug: "www"}) |> render_submit()

      %{view: view, site: Sites.get_site(scope, company)}
    end

    test "shows a \"reserved\" error", %{view: view} do
      assert has_element?(view, "#site-slug-form", "jest zarezerwowane")
    end

    test "keeps the slug unset", %{site: site} do
      assert site.slug == nil
    end
  end

  describe "Scenario: rejecting publish without a slug" do
    setup :register_and_log_in_user

    setup %{conn: conn, scope: scope} do
      company = company_with_draft(scope)
      {:ok, view, _html} = live(conn, ~p"/companies/#{company.id}/site")
      view |> element("#site-publish") |> render_click()

      %{view: view, site: Sites.get_site(scope, company)}
    end

    test "asks for the address first", %{view: view} do
      assert has_element?(view, "#flash-error", "Przed publikacją wybierz adres strony.")
    end

    test "keeps the site a draft", %{site: site} do
      assert site.status == :draft
    end
  end

  describe "Scenario: rejecting script in the edited content on the public page" do
    setup :register_and_log_in_user

    setup %{conn: conn, scope: scope} do
      company = company_with_draft(scope)
      save_headline(conn, company, "<script>alert(1)</script>")
      {:ok, site} = Sites.set_slug(scope, Sites.get_site(scope, company), "piekarnia")
      {:ok, _site} = Sites.publish(scope, site)

      %{public: document(visit("piekarnia.localhost"))}
    end

    test "adds no script element", %{public: public} do
      assert public |> LazyHTML.query("#site-hero script") |> Enum.empty?()
    end

    test "shows the markup as text", %{public: public} do
      assert text_of(public, "#site-hero h1") =~ "<script>alert(1)</script>"
    end
  end

  describe "Scenario: rejecting another owner's site editor" do
    setup :register_and_log_in_user

    setup do
      %{other_company: company_with_draft(user_scope_fixture())}
    end

    test "responds with not found", %{conn: conn, other_company: other_company} do
      assert_raise Ecto.NoResultsError, fn ->
        live(conn, ~p"/companies/#{other_company.id}/site/edit")
      end
    end
  end

  describe "Scenario: rejecting changes to another owner's site" do
    setup do
      other_scope = user_scope_fixture()
      other_site = Sites.get_site(other_scope, company_with_draft(other_scope))
      scope = user_scope_fixture()

      %{
        edit: Sites.update_content(scope, other_site, %{"hero" => %{"headline" => "Przejęte"}}),
        slug: Sites.set_slug(scope, other_site, "przejete"),
        publish: Sites.publish(scope, other_site)
      }
    end

    test "refuses the edit", %{edit: edit} do
      assert edit == {:error, :not_found}
    end

    test "refuses the slug", %{slug: slug} do
      assert slug == {:error, :not_found}
    end

    test "refuses publishing", %{publish: publish} do
      assert publish == {:error, :not_found}
    end
  end
end
