# STORY-008 — Generate a landing page
#
# Entry points: `live "/companies/:id/site"` (FirmosWeb.CompanyLive.Site) and
# `get "/companies/:id/site/preview"` (FirmosWeb.SitePreviewController), both
# behind `:require_authenticated_user`, plus the enqueued
# `Firmos.Sites.GenerateWorker` job (drained from the `ai` queue in the test
# process, so the `Firmos.AI.Mock` expectation applies). Persistence is
# observed through the `Firmos.Sites` and `Firmos.Activity` public APIs.
defmodule FirmosWeb.Features.LandingPageTest do
  @moduledoc "Feature: an owner gets a landing page generated from their plan"
  use FirmosWeb.ConnCase, async: true
  use Oban.Testing, repo: Firmos.Repo

  import Firmos.AccountsFixtures
  import Firmos.CompaniesFixtures
  import Firmos.PlansFixtures
  import Firmos.SitesFixtures
  import Mox
  import Phoenix.LiveViewTest

  alias Firmos.Activity
  alias Firmos.Sites

  @worker Firmos.Sites.GenerateWorker

  setup :verify_on_exit!

  # Runs every enqueued job in this process, like the `ai` queue would.
  defp run_ai_jobs, do: Oban.drain_queue(queue: :ai, with_safety: false)

  # A LiveView also gets the broadcasts it triggers or watches; wait until it
  # has handled them, so it never queries after this test's sandbox is gone.
  defp settle(view), do: render(view)

  defp company_with_ready_plan(scope) do
    company = company_fixture(scope)
    expect_ai_reply({:ok, plan_json()})
    %{success: 1} = run_ai_jobs()
    company
  end

  defp company_with_draft(scope) do
    company = company_with_ready_plan(scope)
    {:ok, _site} = Sites.request_generation(scope, company)
    expect_ai_reply({:ok, site_json()})
    %{success: 1} = run_ai_jobs()
    company
  end

  defp preview_document(conn, company) do
    conn
    |> get(~p"/companies/#{company.id}/site/preview")
    |> html_response(200)
    |> LazyHTML.from_document()
  end

  defp text_of(document, selector) do
    document |> LazyHTML.query(selector) |> LazyHTML.text()
  end

  # ---------------------------------------------------------------------
  # HAPPY PATH
  # ---------------------------------------------------------------------

  describe "Scenario: AC1 — the owner clicks \"create website\" with a ready plan" do
    @describetag :skip
    setup :register_and_log_in_user

    setup %{conn: conn, scope: scope} do
      company = company_with_ready_plan(scope)
      {:ok, view, _html} = live(conn, ~p"/companies/#{company.id}/site")
      view |> element("#site-create") |> render_click()
      settle(view)

      %{view: view, site: Sites.get_site(scope, company)}
    end

    test "queues the site's generation", %{site: site} do
      assert %{generation_status: :pending} = site
    end

    test "enqueues the generation job in the background", %{site: site} do
      assert_enqueued(worker: @worker, args: %{site_id: site.id}, queue: :ai)
    end

    test "shows a progress state", %{view: view} do
      assert has_element?(view, "#site-progress")
    end
  end

  describe "Scenario: AC1 — the draft is generated while the website section is open" do
    @describetag :skip
    setup :register_and_log_in_user

    setup %{conn: conn, scope: scope} do
      company = company_with_ready_plan(scope)
      {:ok, view, _html} = live(conn, ~p"/companies/#{company.id}/site")
      view |> element("#site-create") |> render_click()
      expect_ai_reply({:ok, site_json()})
      run_ai_jobs()
      settle(view)
      site = Sites.get_site(scope, company)

      %{
        view: view,
        site: site,
        content: site.current_version.content,
        attrs: site_attrs(),
        entry:
          scope
          |> Activity.list_for_company(company)
          |> Enum.find(&(&1.action == :site_generated))
      }
    end

    test "saves the draft as the first generated version", %{site: site} do
      assert %{number: 1, source: :generated} = site.current_version
    end

    test "keeps the site a draft", %{site: site} do
      assert %{status: :draft} = site
    end

    test "has a hero section", %{content: content, attrs: attrs} do
      assert content.hero.headline == attrs["hero"]["headline"]
    end

    test "has an offer section", %{content: content, attrs: attrs} do
      assert hd(content.offer.items).name == hd(attrs["offer"]["items"])["name"]
    end

    test "has a pricing section", %{content: content, attrs: attrs} do
      assert hd(content.pricing.items).price == hd(attrs["pricing"]["items"])["price"]
    end

    test "has a contact section", %{content: content, attrs: attrs} do
      assert content.contact.text == attrs["contact"]["text"]
    end

    test "records the AI agent generating the site", %{entry: entry, site: site} do
      version_id = site.current_version_id
      assert %{actor: :agent, subject_type: "site_version", subject_id: ^version_id} = entry
    end

    test "shows the draft without a reload", %{view: view} do
      assert has_element?(view, "#site-draft")
    end
  end

  describe "Scenario: AC1 — the owner opens the website section from the dashboard" do
    @describetag :skip
    setup :register_and_log_in_user

    setup %{conn: conn, scope: scope} do
      company = company_with_ready_plan(scope)
      {:ok, dashboard, _html} = live(conn, ~p"/dashboard")
      result = dashboard |> element("#company-site-link") |> render_click()

      %{result: result, site_path: ~p"/companies/#{company.id}/site"}
    end

    test "navigates to the website section", %{result: result, site_path: site_path} do
      assert {:error, {:live_redirect, %{to: ^site_path}}} = result
    end
  end

  describe "Scenario: AC1 — the owner opens the website section from the plan" do
    @describetag :skip
    setup :register_and_log_in_user

    setup %{conn: conn, scope: scope} do
      company = company_with_ready_plan(scope)
      {:ok, plan_view, _html} = live(conn, ~p"/companies/#{company.id}/plan")
      result = plan_view |> element("#plan-site-link") |> render_click()

      %{result: result, site_path: ~p"/companies/#{company.id}/site"}
    end

    test "navigates to the website section", %{result: result, site_path: site_path} do
      assert {:error, {:live_redirect, %{to: ^site_path}}} = result
    end
  end

  describe "Scenario: AC2 — the owner opens the preview of a draft" do
    @describetag :skip
    setup :register_and_log_in_user

    setup %{conn: conn, scope: scope} do
      company = company_with_draft(scope)
      %{document: preview_document(conn, company), attrs: site_attrs()}
    end

    test "renders the hero", %{document: document, attrs: attrs} do
      assert text_of(document, "#site-hero") =~ attrs["hero"]["headline"]
    end

    test "renders the offer", %{document: document, attrs: attrs} do
      assert text_of(document, "#site-offer") =~ hd(attrs["offer"]["items"])["description"]
    end

    test "renders the pricing", %{document: document, attrs: attrs} do
      assert text_of(document, "#site-pricing") =~ hd(attrs["pricing"]["items"])["price"]
    end

    test "renders the contact", %{document: document, attrs: attrs} do
      assert text_of(document, "#site-contact") =~ attrs["contact"]["text"]
    end
  end

  describe "Scenario: AC2 — the website section links to the preview" do
    @describetag :skip
    setup :register_and_log_in_user

    setup %{conn: conn, scope: scope} do
      company = company_with_draft(scope)
      {:ok, view, _html} = live(conn, ~p"/companies/#{company.id}/site")

      %{view: view, preview_path: ~p"/companies/#{company.id}/site/preview"}
    end

    test "offers the preview link", %{view: view, preview_path: preview_path} do
      assert has_element?(view, ~s(#site-draft #site-preview-link[href="#{preview_path}"]))
    end
  end

  # ---------------------------------------------------------------------
  # SAD PATH
  # ---------------------------------------------------------------------

  describe "Scenario: AC3 — rejecting \"create website\" for a company without a plan" do
    @describetag :skip
    setup :register_and_log_in_user

    setup %{conn: conn, scope: scope} do
      company = company_fixture(scope)
      {:ok, view, _html} = live(conn, ~p"/companies/#{company.id}/site")

      %{view: view}
    end

    test "disables \"create website\"", %{view: view} do
      assert has_element?(view, "#site-create[disabled]")
    end

    test "hints to generate a plan first", %{view: view} do
      assert has_element?(view, "#site-needs-plan")
    end
  end

  describe "Scenario: AC3 — rejecting a generation request without a plan" do
    @describetag :skip

    setup do
      scope = user_scope_fixture()
      company = company_fixture(scope)

      %{result: Sites.request_generation(scope, company), site: Sites.get_site(scope, company)}
    end

    test "refuses the request", %{result: result} do
      assert {:error, :no_ready_plan} = result
    end

    test "creates no site", %{site: site} do
      assert site == nil
    end
  end

  describe "Scenario: AC4 — rejecting a draft when the AI provider returns an error" do
    @describetag :skip
    setup :register_and_log_in_user

    setup %{conn: conn, scope: scope} do
      company = company_with_ready_plan(scope)
      {:ok, view, _html} = live(conn, ~p"/companies/#{company.id}/site")
      view |> element("#site-create") |> render_click()
      expect_ai_reply({:error, {:http_status, 500, "overloaded_error: Overloaded"}})
      counts = run_ai_jobs()
      settle(view)

      %{view: view, counts: counts, site: Sites.get_site(scope, company)}
    end

    test "does not retry the job", %{counts: counts} do
      assert %{cancelled: 1} = counts
    end

    test "saves no draft", %{site: site} do
      assert site.current_version_id == nil
    end

    test "shows a failure message", %{view: view} do
      assert has_element?(view, "#site-failed")
    end

    test "offers a try again button", %{view: view} do
      assert has_element?(view, "#site-failed #site-retry")
    end
  end

  describe "Scenario: AC4 — rejecting a draft the AI returned in the wrong shape" do
    @describetag :skip
    setup :register_and_log_in_user

    setup %{conn: conn, scope: scope} do
      company = company_with_ready_plan(scope)
      {:ok, _site} = Sites.request_generation(scope, company)
      expect_ai_reply({:ok, site_json(%{"pricing" => "79 zł"})})
      run_ai_jobs()
      {:ok, view, _html} = live(conn, ~p"/companies/#{company.id}/site")

      %{view: view, site: Sites.get_site(scope, company)}
    end

    test "saves no draft", %{site: site} do
      assert site.current_version_id == nil
    end

    test "shows a failure message", %{view: view} do
      assert has_element?(view, "#site-failed")
    end
  end

  describe "Scenario: AC4 — the owner tries again after a failure" do
    @describetag :skip
    setup :register_and_log_in_user

    setup %{conn: conn, scope: scope} do
      company = company_with_ready_plan(scope)
      {:ok, _site} = Sites.request_generation(scope, company)
      expect_ai_reply({:error, :timeout})
      run_ai_jobs()
      {:ok, view, _html} = live(conn, ~p"/companies/#{company.id}/site")
      view |> element("#site-retry") |> render_click()
      settle(view)

      %{view: view, site: Sites.get_site(scope, company)}
    end

    test "queues the generation again", %{site: site} do
      assert %{generation_status: :pending} = site
    end

    test "enqueues the generation job again", %{site: site} do
      assert_enqueued(worker: @worker, args: %{site_id: site.id}, queue: :ai)
    end

    test "shows the progress state", %{view: view} do
      assert has_element?(view, "#site-progress")
    end
  end

  describe "Scenario: rejecting another owner's website section" do
    @describetag :skip
    setup :register_and_log_in_user

    setup do
      %{other_company: company_fixture(user_scope_fixture())}
    end

    test "responds with not found", %{conn: conn, other_company: other_company} do
      assert_raise Ecto.NoResultsError, fn ->
        live(conn, ~p"/companies/#{other_company.id}/site")
      end
    end
  end

  describe "Scenario: rejecting another owner's preview" do
    @describetag :skip
    setup :register_and_log_in_user

    setup do
      %{other_company: company_with_draft(user_scope_fixture())}
    end

    test "responds with not found", %{conn: conn, other_company: other_company} do
      assert_error_sent 404, fn -> get(conn, ~p"/companies/#{other_company.id}/site/preview") end
    end
  end
end
