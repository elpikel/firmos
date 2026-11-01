# STORY-004 — Activity log
#
# Entry points: `live "/companies/:id/profile"` (the owner's change, written
# through `Companies.update_company/3`), `live "/dashboard"` (the idea becomes a
# company), `Firmos.Activity.record/4` (the API agents record through) and
# `live "/companies/:id/activity"` (FirmosWeb.CompanyLive.Activity), all in the
# `:require_authenticated_user` live_session.
defmodule FirmosWeb.Features.ActivityLogTest do
  @moduledoc "Feature: an owner sees every action taken on their company"
  use FirmosWeb.ConnCase, async: true

  import Firmos.AccountsFixtures
  import Firmos.CompaniesFixtures
  import Phoenix.LiveViewTest

  alias Firmos.Activity

  defp row_ids(view) do
    view
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.query("#activities > article")
    |> LazyHTML.attribute("id")
  end

  # ---------------------------------------------------------------------
  # HAPPY PATH
  # ---------------------------------------------------------------------

  describe "Scenario: AC1 — the owner saves a changed company profile" do
    setup :register_and_log_in_user

    setup %{conn: conn, scope: scope} do
      company = company_fixture(scope)
      {:ok, profile, _html} = live(conn, ~p"/companies/#{company.id}/profile")

      profile
      |> form("#company-profile-form", company: %{name: "Piekarnia Pod Wawelem"})
      |> render_submit()

      [latest | _] = Activity.list_for_company(scope, company)
      %{latest: latest}
    end

    test "records the owner as the actor", %{latest: latest} do
      assert latest.actor == :owner
    end

    test "records which owner acted", %{latest: latest, user: user} do
      assert latest.actor_user_id == user.id
    end

    test "records the action", %{latest: latest} do
      assert latest.action == :company_updated
    end

    test "records the timestamp", %{latest: latest} do
      assert %DateTime{} = latest.inserted_at
    end

    test "records only the changed field with its old and new value", %{latest: latest} do
      assert latest.metadata == %{
               "changes" => %{
                 "name" => %{"from" => "Moja firma", "to" => "Piekarnia Pod Wawelem"}
               }
             }
    end
  end

  describe "Scenario: AC1 — the owner's idea becomes their company" do
    setup :register_and_log_in_user

    setup %{scope: scope} do
      company = company_fixture(scope)
      %{entries: Activity.list_for_company(scope, company)}
    end

    test "records the company creation by the owner", %{entries: entries} do
      assert [%{action: :company_created, actor: :owner}] = entries
    end
  end

  describe "Scenario: AC1 — an agent changes company content" do
    setup :register_and_log_in_user

    setup %{scope: scope} do
      company = company_fixture(scope)

      {:ok, _entry} =
        Activity.record(company, :agent, :company_updated,
          metadata: %{"changes" => %{"city" => %{"from" => nil, "to" => "Kraków"}}}
        )

      [latest | _] = Activity.list_for_company(scope, company)
      %{latest: latest}
    end

    test "records the agent as the actor", %{latest: latest} do
      assert latest.actor == :agent
    end

    test "records no owner for the agent's action", %{latest: latest} do
      assert latest.actor_user_id == nil
    end
  end

  describe "Scenario: AC2 — the owner opens the activity log" do
    setup :register_and_log_in_user

    setup %{conn: conn, scope: scope} do
      company = company_fixture(scope)
      [created] = Activity.list_for_company(scope, company)
      {:ok, middle} = Activity.record(company, :system, :company_updated, metadata: %{})

      {:ok, newest} =
        Activity.record(company, :agent, :company_updated,
          metadata: %{"changes" => %{"city" => %{"from" => nil, "to" => "Kraków"}}}
        )

      {:ok, view, _html} = live(conn, ~p"/companies/#{company.id}/activity")

      %{
        view: view,
        newest_row: "#activities-#{newest.id}",
        expected_order: Enum.map([newest, middle, created], &"activities-#{&1.id}")
      }
    end

    test "lists entries newest first", %{view: view, expected_order: expected_order} do
      assert row_ids(view) == expected_order
    end

    test "shows who acted", %{view: view, newest_row: row} do
      assert has_element?(view, "#{row} [data-role=actor]")
    end

    test "shows what was done", %{view: view, newest_row: row} do
      assert has_element?(view, "#{row} [data-role=action]")
    end

    test "shows when it happened", %{view: view, newest_row: row} do
      assert has_element?(view, "#{row} time[datetime]")
    end

    test "shows a summary of what changed", %{view: view, newest_row: row} do
      assert has_element?(view, "#{row} [data-role=summary]", "Kraków")
    end
  end

  describe "Scenario: AC2 — the owner opens the log from the dashboard" do
    setup :register_and_log_in_user

    setup %{conn: conn, scope: scope} do
      company = company_fixture(scope)
      {:ok, dashboard, _html} = live(conn, ~p"/dashboard")
      result = dashboard |> element("#company-activity-link") |> render_click()

      %{result: result, activity_path: ~p"/companies/#{company.id}/activity"}
    end

    test "navigates to the activity log", %{result: result, activity_path: activity_path} do
      assert {:error, {:live_redirect, %{to: ^activity_path}}} = result
    end
  end

  describe "Scenario: AC2 — the owner opens the log from the company profile" do
    setup :register_and_log_in_user

    setup %{conn: conn, scope: scope} do
      company = company_fixture(scope)
      {:ok, profile, _html} = live(conn, ~p"/companies/#{company.id}/profile")
      result = profile |> element("#company-profile-activity-link") |> render_click()

      %{result: result, activity_path: ~p"/companies/#{company.id}/activity"}
    end

    test "navigates to the activity log", %{result: result, activity_path: activity_path} do
      assert {:error, {:live_redirect, %{to: ^activity_path}}} = result
    end
  end

  # ---------------------------------------------------------------------
  # SAD PATH
  # ---------------------------------------------------------------------

  describe "Scenario: AC3 — rejecting another owner's activity log" do
    setup :register_and_log_in_user

    setup do
      %{other_company: company_fixture(user_scope_fixture())}
    end

    test "responds with not found", %{conn: conn, other_company: other_company} do
      assert_raise Ecto.NoResultsError, fn ->
        live(conn, ~p"/companies/#{other_company.id}/activity")
      end
    end
  end
end
