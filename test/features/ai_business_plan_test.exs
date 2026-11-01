# STORY-007 — AI business plan
#
# Entry points: `live "/dashboard"` (FirmosWeb.DashboardLive: the idea becomes a
# company and its first plan is enqueued), the enqueued
# `Firmos.Plans.GenerateWorker` job (drained from the `ai` queue in the test
# process, so the `Firmos.AI.Mock` expectation applies), `live
# "/companies/:id/plan"` (FirmosWeb.CompanyLive.Plan) and `live
# "/companies/:id/activity"`, all in the `:require_authenticated_user`
# live_session. Persistence is observed through the `Firmos.Plans` public API.
defmodule FirmosWeb.Features.AiBusinessPlanTest do
  @moduledoc "Feature: an owner gets an AI-generated business plan for their idea"
  use FirmosWeb.ConnCase, async: true
  use Oban.Testing, repo: Firmos.Repo

  import Firmos.AccountsFixtures
  import Firmos.CompaniesFixtures
  import Firmos.PlansFixtures
  import Mox
  import Phoenix.LiveViewTest

  alias Firmos.Activity
  alias Firmos.Ideas
  alias Firmos.Plans

  @worker Firmos.Plans.GenerateWorker

  setup :verify_on_exit!

  # Runs every enqueued plan job in this process, like the `ai` queue would.
  defp run_plan_jobs, do: Oban.drain_queue(queue: :ai, with_safety: false)

  # A LiveView also gets the plan broadcasts it triggers or watches; wait until
  # it has handled them, so it never queries after this test's sandbox is gone.
  defp settle(view), do: render(view)

  defp generated_company(scope) do
    company = company_fixture(scope)
    expect_ai_reply({:ok, plan_json()})
    %{success: 1} = run_plan_jobs()
    company
  end

  # ---------------------------------------------------------------------
  # HAPPY PATH
  # ---------------------------------------------------------------------

  describe "Scenario: AC1 — the owner reaches the dashboard with a new company" do
    setup :register_and_log_in_user

    setup %{conn: conn, scope: scope} do
      {:ok, _idea} = Ideas.create_for_user(scope, %{text: valid_idea_text()})
      {:ok, dashboard, _html} = live(conn, ~p"/dashboard")
      [company] = Firmos.Companies.list_companies(scope)

      %{dashboard: dashboard, plan: Plans.current_plan(scope, company)}
    end

    test "creates the first plan version", %{plan: plan} do
      assert %{version: 1, status: :pending} = plan
    end

    test "enqueues its generation in the background", %{plan: plan} do
      assert_enqueued(worker: @worker, args: %{plan_id: plan.id}, queue: :ai)
    end

    test "shows a progress state", %{dashboard: dashboard} do
      assert has_element?(dashboard, "#plan-status #plan-progress")
    end
  end

  describe "Scenario: AC1 — generation finishes while the dashboard is open" do
    setup :register_and_log_in_user

    setup %{conn: conn, scope: scope} do
      company_fixture(scope)
      {:ok, dashboard, _html} = live(conn, ~p"/dashboard")
      expect_ai_reply({:ok, plan_json()})
      run_plan_jobs()

      %{dashboard: dashboard}
    end

    test "shows the plan as ready without a reload", %{dashboard: dashboard} do
      assert has_element?(dashboard, "#plan-status #plan-ready")
    end
  end

  describe "Scenario: AC2 — the owner opens the generated plan" do
    setup :register_and_log_in_user

    setup %{conn: conn, scope: scope} do
      company = generated_company(scope)
      {:ok, view, _html} = live(conn, ~p"/companies/#{company.id}/plan")
      %{view: view, attrs: plan_attrs()}
    end

    test "shows the offer", %{view: view, attrs: attrs} do
      assert has_element?(view, "#plan-offer", attrs["offer"])
    end

    test "shows the target customer", %{view: view, attrs: attrs} do
      assert has_element?(view, "#plan-target-customer", attrs["target_customer"])
    end

    test "shows the competitors", %{view: view, attrs: attrs} do
      assert has_element?(view, "#plan-competitors", hd(attrs["competitors"]))
    end

    test "shows the pricing", %{view: view, attrs: attrs} do
      assert has_element?(view, "#plan-pricing", attrs["pricing"])
    end

    test "shows the channels", %{view: view, attrs: attrs} do
      assert has_element?(view, "#plan-channels", hd(attrs["channels"]))
    end

    test "shows the 30-day task list", %{view: view, attrs: attrs} do
      assert has_element?(view, "#plan-tasks", hd(attrs["tasks_30_days"])["task"])
    end
  end

  describe "Scenario: AC2 — the owner opens the plan from the dashboard" do
    setup :register_and_log_in_user

    setup %{conn: conn, scope: scope} do
      company = generated_company(scope)
      {:ok, dashboard, _html} = live(conn, ~p"/dashboard")
      result = dashboard |> element("#company-plan-link") |> render_click()

      %{result: result, plan_path: ~p"/companies/#{company.id}/plan"}
    end

    test "navigates to the plan", %{result: result, plan_path: plan_path} do
      assert {:error, {:live_redirect, %{to: ^plan_path}}} = result
    end
  end

  describe "Scenario: AC3 — the owner opens the activity log after generation" do
    setup :register_and_log_in_user

    setup %{conn: conn, scope: scope} do
      company = generated_company(scope)

      entry =
        scope |> Activity.list_for_company(company) |> Enum.find(&(&1.action == :plan_generated))

      {:ok, view, _html} = live(conn, ~p"/companies/#{company.id}/activity")

      %{view: view, entry: entry}
    end

    test "records the AI agent generating the plan", %{entry: entry} do
      assert %{actor: :agent} = entry
    end

    test "lists a \"plan generated\" entry", %{view: view, entry: entry} do
      assert has_element?(view, "#activities-#{entry.id} [data-role=action]", "Plan wygenerowany")
    end
  end

  describe "Scenario: AC4 — the owner gives the plan a thumbs up" do
    setup :register_and_log_in_user

    setup %{conn: conn, scope: scope} do
      company = generated_company(scope)
      {:ok, view, _html} = live(conn, ~p"/companies/#{company.id}/plan")
      view |> element("#plan-rate-up") |> render_click()
      settle(view)

      %{plan: Plans.current_plan(scope, company)}
    end

    test "stores the up rating on the plan", %{plan: plan} do
      assert plan.rating == :up
    end
  end

  describe "Scenario: AC4 — the owner gives the plan a thumbs down" do
    setup :register_and_log_in_user

    setup %{conn: conn, scope: scope} do
      company = generated_company(scope)
      {:ok, view, _html} = live(conn, ~p"/companies/#{company.id}/plan")
      view |> element("#plan-rate-down") |> render_click()
      settle(view)

      %{plan: Plans.current_plan(scope, company)}
    end

    test "stores the down rating on the plan", %{plan: plan} do
      assert plan.rating == :down
    end
  end

  # ---------------------------------------------------------------------
  # SAD PATH
  # ---------------------------------------------------------------------

  describe "Scenario: AC5 — rejecting a plan when the AI provider returns an error" do
    setup :register_and_log_in_user

    setup %{conn: conn, scope: scope} do
      company = company_fixture(scope)
      {:ok, view, _html} = live(conn, ~p"/companies/#{company.id}/plan")
      expect_ai_reply({:error, {:http_status, 500, "overloaded_error: Overloaded"}})
      counts = run_plan_jobs()
      settle(view)

      %{view: view, counts: counts}
    end

    test "does not retry the job", %{counts: counts} do
      assert %{cancelled: 1} = counts
    end

    test "shows a failure message", %{view: view} do
      assert has_element?(view, "#plan-failed")
    end

    test "offers a try again button", %{view: view} do
      assert has_element?(view, "#plan-failed #plan-retry")
    end
  end

  describe "Scenario: AC5 — rejecting a plan the AI returned as invalid JSON" do
    setup :register_and_log_in_user

    setup %{conn: conn, scope: scope} do
      company = company_fixture(scope)
      expect_ai_reply({:ok, "Oto Twój plan: brak JSON-a"})
      run_plan_jobs()
      {:ok, view, _html} = live(conn, ~p"/companies/#{company.id}/plan")

      %{view: view}
    end

    test "shows a failure message", %{view: view} do
      assert has_element?(view, "#plan-failed")
    end
  end

  describe "Scenario: AC5 — the owner tries again after a failure" do
    setup :register_and_log_in_user

    setup %{conn: conn, scope: scope} do
      company = company_fixture(scope)
      expect_ai_reply({:error, :timeout})
      run_plan_jobs()
      {:ok, view, _html} = live(conn, ~p"/companies/#{company.id}/plan")
      view |> element("#plan-retry") |> render_click()
      settle(view)

      %{view: view, plan: Plans.current_plan(scope, company)}
    end

    test "puts the same plan back to pending", %{plan: plan} do
      assert %{version: 1, status: :pending} = plan
    end

    test "enqueues its generation again", %{plan: plan} do
      assert_enqueued(worker: @worker, args: %{plan_id: plan.id}, queue: :ai)
    end

    test "shows the progress state", %{view: view} do
      assert has_element?(view, "#plan-progress")
    end
  end

  describe "Scenario: AC6 — the owner regenerates an existing plan" do
    setup :register_and_log_in_user

    setup %{conn: conn, scope: scope} do
      company = generated_company(scope)
      {:ok, view, _html} = live(conn, ~p"/companies/#{company.id}/plan")
      view |> element("#plan-regenerate") |> render_click()
      settle(view)
      [newest, previous] = Plans.list_plans(scope, company)
      {:ok, previous_view, _html} = live(conn, ~p"/companies/#{company.id}/plan?version=1")

      %{view: view, previous_view: previous_view, newest: newest, previous: previous}
    end

    test "creates a new pending version", %{newest: newest} do
      assert %{version: 2, status: :pending} = newest
    end

    test "enqueues the new version's generation", %{newest: newest} do
      assert_enqueued(worker: @worker, args: %{plan_id: newest.id}, queue: :ai)
    end

    test "keeps the previous version", %{previous: previous} do
      assert %{version: 1, status: :ready} = previous
    end

    test "lists the previous version", %{view: view} do
      assert has_element?(view, "#plan-versions #plan-version-1")
    end

    test "shows the previous version's plan when it is opened", %{previous_view: previous_view} do
      assert has_element?(previous_view, "#plan-offer", plan_attrs()["offer"])
    end
  end

  describe "Scenario: rejecting another owner's plan" do
    setup :register_and_log_in_user

    setup do
      %{other_company: company_fixture(user_scope_fixture())}
    end

    test "responds with not found", %{conn: conn, other_company: other_company} do
      assert_raise Ecto.NoResultsError, fn ->
        live(conn, ~p"/companies/#{other_company.id}/plan")
      end
    end
  end
end
