# STORY-014 — Approval queue
#
# Entry point: `live "/companies/:id/approvals"` (FirmosWeb.CompanyLive.Approvals)
# behind `:require_authenticated_user`; the owner clicks `#approve-<id>` or
# `#reject-<id>`. Pending requests are created through
# `Firmos.Approvals.request_publish/2`, the public API agents use. The result
# is observed on the public page a customer gets from `<slug>.localhost`
# and through the `Firmos.Approvals` and `Firmos.Activity` public APIs.
defmodule FirmosWeb.Features.ApprovalQueueTest do
  @moduledoc "Feature: an owner approves or rejects agent requests to publish"
  use FirmosWeb.ConnCase, async: true

  import Firmos.AccountsFixtures
  import Firmos.CompaniesFixtures
  import Firmos.PlansFixtures
  import Firmos.SitesFixtures
  import Mox
  import Phoenix.LiveViewTest

  alias Firmos.Activity
  alias Firmos.Approvals
  alias Firmos.Sites

  setup :verify_on_exit!

  @new_headline "Nowy nagłówek od agenta"

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

  # Version 1 is live at `slug`; version 2 (a new headline) is the current
  # draft, and publishing it is pending the owner's approval.
  defp pending_publication(scope, slug) do
    company = company_with_draft(scope)
    {:ok, site} = Sites.set_slug(scope, Sites.get_site(scope, company), slug)
    {:ok, site} = Sites.publish(scope, site)
    {:ok, site} = Sites.update_content(scope, site, %{"hero" => %{"headline" => @new_headline}})
    {:ok, approval} = Approvals.request_publish(company, site.current_version)
    %{company: company, approval: approval}
  end

  defp latest_entry(scope, company, action) do
    scope |> Activity.list_for_company(company) |> Enum.find(&(&1.action == action))
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

  describe "Scenario: AC1 — the owner sees a pending request" do
    setup :register_and_log_in_user

    setup %{conn: conn, scope: scope} do
      %{company: company, approval: approval} = pending_publication(scope, "piekarnia")
      {:ok, view, _html} = live(conn, ~p"/companies/#{company.id}/approvals")
      %{view: view, approval: approval, company: company}
    end

    test "lists the request as pending", %{view: view, approval: approval} do
      assert has_element?(view, "#approvals-pending #approvals-#{approval.id}")
    end

    test "links to the preview of the requested version", %{view: view, company: company} do
      assert has_element?(
               view,
               ~s(#approvals-pending a[href="/companies/#{company.id}/site/preview?version=2"])
             )
    end
  end

  describe "Scenario: AC1 — the owner approves a pending publication" do
    setup :register_and_log_in_user

    setup %{conn: conn, scope: scope} do
      %{company: company, approval: approval} = pending_publication(scope, "piekarnia")
      {:ok, view, _html} = live(conn, ~p"/companies/#{company.id}/approvals")
      view |> element("#approve-#{approval.id}") |> render_click()

      %{
        view: view,
        approval: approval,
        public: visit("piekarnia.localhost"),
        stored: Approvals.get_approval(scope, approval.id),
        logged: latest_entry(scope, company, :approval_approved)
      }
    end

    test "publishes the requested version", %{public: public} do
      assert headline(public) =~ @new_headline
    end

    test "marks the request approved", %{stored: stored} do
      assert {:ok, %{status: :approved}} = stored
    end

    test "logs the approval", %{logged: logged, approval: approval} do
      assert logged.subject_id == approval.site_version_id
    end

    test "removes the request from the pending list", %{view: view, approval: approval} do
      refute has_element?(view, "#approvals-pending #approvals-#{approval.id}")
    end

    test "shows the request in the history", %{view: view, approval: approval} do
      assert has_element?(view, "#approvals-history #decided-#{approval.id}")
    end
  end

  describe "Scenario: AC2 — the owner rejects a pending publication" do
    setup :register_and_log_in_user

    setup %{conn: conn, scope: scope} do
      %{company: company, approval: approval} = pending_publication(scope, "piekarnia")
      {:ok, view, _html} = live(conn, ~p"/companies/#{company.id}/approvals")
      view |> element("#reject-#{approval.id}") |> render_click()

      %{
        view: view,
        approval: approval,
        public: visit("piekarnia.localhost"),
        stored: Approvals.get_approval(scope, approval.id),
        logged: latest_entry(scope, company, :approval_rejected)
      }
    end

    test "keeps the previous version live", %{public: public} do
      assert headline(public) =~ site_attrs()["hero"]["headline"]
    end

    test "marks the request rejected", %{stored: stored} do
      assert {:ok, %{status: :rejected}} = stored
    end

    test "logs the rejection", %{logged: logged, approval: approval} do
      assert logged.subject_id == approval.site_version_id
    end

    test "removes the request from the pending list", %{view: view, approval: approval} do
      refute has_element?(view, "#approvals-pending #approvals-#{approval.id}")
    end
  end

  describe "Scenario: the dashboard shows the number of pending approvals" do
    setup :register_and_log_in_user

    setup %{conn: conn, scope: scope} do
      %{company: company} = pending_publication(scope, "piekarnia")
      {:ok, view, _html} = live(conn, ~p"/dashboard?company=#{company.id}")
      %{view: view, company: company}
    end

    test "shows one pending approval", %{view: view} do
      assert has_element?(view, ~s(#dashboard-approvals[data-count="1"]))
    end

    test "links to the approvals page", %{view: view, company: company} do
      assert has_element?(
               view,
               ~s(#dashboard-approvals[href="/companies/#{company.id}/approvals"])
             )
    end
  end

  # ---------------------------------------------------------------------
  # SAD PATH
  # ---------------------------------------------------------------------

  describe "Scenario: AC3 — rejecting an approval after the owner edited the draft" do
    setup do
      scope = user_scope_fixture()
      %{company: company, approval: approval} = pending_publication(scope, "piekarnia")
      site = Sites.get_site(scope, company)
      {:ok, _site} = Sites.update_content(scope, site, %{"hero" => %{"headline" => "Poprawka"}})

      %{
        result: Approvals.approve(scope, approval),
        public: visit("piekarnia.localhost")
      }
    end

    test "refuses the approval as outdated", %{result: result} do
      assert {:error, :outdated} = result
    end

    test "publishes nothing", %{public: public} do
      assert headline(public) =~ site_attrs()["hero"]["headline"]
    end
  end

  describe "Scenario: AC4 — rejecting another owner's approvals page" do
    setup :register_and_log_in_user

    setup do
      %{other: pending_publication(user_scope_fixture(), "inna-firma")}
    end

    test "responds with not found", %{conn: conn, other: %{company: company}} do
      assert_raise Ecto.NoResultsError, fn ->
        live(conn, ~p"/companies/#{company.id}/approvals")
      end
    end
  end

  describe "Scenario: AC4 — rejecting a forged approval id on the owner's own page" do
    setup :register_and_log_in_user

    setup %{conn: conn, scope: scope} do
      other_scope = user_scope_fixture()
      %{approval: other} = pending_publication(other_scope, "inna-firma")
      %{company: company} = pending_publication(scope, "piekarnia")
      {:ok, view, _html} = live(conn, ~p"/companies/#{company.id}/approvals")
      render_hook(view, "approve", %{"id" => Integer.to_string(other.id)})
      render_hook(view, "reject", %{"id" => Integer.to_string(other.id)})

      %{
        stored: Approvals.get_approval(other_scope, other.id),
        public: visit("inna-firma.localhost")
      }
    end

    test "leaves the other owner's request pending", %{stored: stored} do
      assert {:ok, %{status: :pending}} = stored
    end

    test "publishes nothing for the other owner", %{public: public} do
      assert headline(public) =~ site_attrs()["hero"]["headline"]
    end
  end

  describe "Scenario: AC4 — rejecting a decision on another owner's approval" do
    setup do
      %{approval: other} = pending_publication(user_scope_fixture(), "inna-firma")
      scope = user_scope_fixture()
      %{approve: Approvals.approve(scope, other), reject: Approvals.reject(scope, other)}
    end

    test "refuses to approve it", %{approve: approve} do
      assert {:error, :not_found} = approve
    end

    test "refuses to reject it", %{reject: reject} do
      assert {:error, :not_found} = reject
    end
  end
end
