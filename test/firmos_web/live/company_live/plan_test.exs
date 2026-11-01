defmodule FirmosWeb.CompanyLive.PlanTest do
  use FirmosWeb.ConnCase, async: true

  import Ecto.Query
  import Firmos.CompaniesFixtures
  import Firmos.PlansFixtures
  import Mox
  import Phoenix.LiveViewTest

  alias Firmos.Plans

  setup :verify_on_exit!
  setup :register_and_log_in_user

  setup %{scope: scope} do
    company = company_fixture(scope)
    %{company: company, plan: Plans.current_plan(scope, company)}
  end

  defp generate(plan, attrs) do
    expect_ai_reply({:ok, plan_json(attrs)})
    {:ok, ready} = Plans.generate_plan(plan.id)
    ready
  end

  test "renders AI content escaped", %{conn: conn, company: company, plan: plan} do
    generate(plan, %{"offer" => "<script>alert('x')</script> chleb"})
    {:ok, view, _html} = live(conn, ~p"/companies/#{company.id}/plan")

    refute has_element?(view, "#plan-offer script")
    assert has_element?(view, "#plan-offer", "<script>alert('x')</script> chleb")
  end

  test "shows progress and no regenerate button while generating",
       %{conn: conn, company: company} do
    {:ok, view, _html} = live(conn, ~p"/companies/#{company.id}/plan")

    assert has_element?(view, "#plan-progress")
    refute has_element?(view, "#plan-regenerate")
  end

  test "marks the stored rating as pressed", %{
    conn: conn,
    company: company,
    plan: plan,
    scope: scope
  } do
    ready = generate(plan, %{})
    {:ok, _rated} = Plans.rate_plan(scope, ready, :down)
    {:ok, view, _html} = live(conn, ~p"/companies/#{company.id}/plan")

    assert has_element?(view, "#plan-rate-down[aria-pressed=true]")
    assert has_element?(view, "#plan-rate-up[aria-pressed=false]")
  end

  test "switches between versions with ?version=",
       %{conn: conn, company: company, plan: plan, scope: scope} do
    generate(plan, %{"offer" => "Pierwsza oferta"})
    {:ok, v2} = Plans.regenerate_plan(scope, company)
    generate(v2, %{"offer" => "Druga oferta"})

    {:ok, view, _html} = live(conn, ~p"/companies/#{company.id}/plan")
    assert has_element?(view, "#plan-offer", "Druga oferta")

    view |> element("#plan-version-1") |> render_click()
    assert has_element?(view, "#plan-offer", "Pierwsza oferta")
  end

  test "responds with not found for an unknown version", %{conn: conn, company: company} do
    assert_raise Ecto.NoResultsError, fn ->
      live(conn, ~p"/companies/#{company.id}/plan?version=9")
    end
  end

  test "offers try again for a stalled plan", %{conn: conn, company: company, plan: plan} do
    stale = DateTime.add(DateTime.utc_now(:second), -3, :hour)

    Firmos.Repo.update_all(
      from(p in Firmos.Plans.Plan, where: p.id == ^plan.id),
      set: [status: :generating, updated_at: stale]
    )

    {:ok, view, _html} = live(conn, ~p"/companies/#{company.id}/plan")

    assert has_element?(view, "#plan-failed #plan-retry")
  end

  test "offers try again only on the current version",
       %{conn: conn, company: company, plan: plan, scope: scope} do
    expect_ai_reply({:error, :timeout})
    {:error, _} = Plans.generate_plan(plan.id)
    {:ok, _v2} = Plans.regenerate_plan(scope, company)

    {:ok, view, _html} = live(conn, ~p"/companies/#{company.id}/plan?version=1")

    assert has_element?(view, "#plan-failed")
    refute has_element?(view, "#plan-retry")
  end

  test "ignores forged events", %{conn: conn, company: company} do
    {:ok, view, _html} = live(conn, ~p"/companies/#{company.id}/plan")

    render_hook(view, "rate", %{"rating" => "sideways"})
    render_hook(view, "made-up", %{})

    assert has_element?(view, "#plan-progress")
  end

  test "ignores rate and retry when there is no plan", %{conn: conn, company: company} do
    Firmos.Repo.delete_all(from(p in Firmos.Plans.Plan, where: p.company_id == ^company.id))
    {:ok, view, _html} = live(conn, ~p"/companies/#{company.id}/plan")

    render_hook(view, "rate", %{"rating" => "up"})
    render_hook(view, "retry", %{})

    assert has_element?(view, "#plan-empty")
  end
end
