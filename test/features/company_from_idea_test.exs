# STORY-006 — Create a company from the idea
#
# Entry point: `live "/dashboard"` (FirmosWeb.DashboardLive) and
# `live "/companies/:id/profile"` (FirmosWeb.CompanyLive.Profile), both in the
# `:require_authenticated_user` live_session. Persistence is observed through
# the `Firmos.Companies` and `Firmos.Ideas` public APIs.
defmodule FirmosWeb.Features.CompanyFromIdeaTest do
  @moduledoc "Feature: an owner's submitted idea becomes their company"
  use FirmosWeb.ConnCase, async: true

  import Firmos.AccountsFixtures
  import Firmos.CompaniesFixtures
  import Phoenix.LiveViewTest

  alias Firmos.Accounts
  alias Firmos.Accounts.Scope
  alias Firmos.Companies
  alias Firmos.Ideas

  @valid_idea "Piekarnia rzemieślnicza w Krakowie z dostawą pieczywa na zamówienie."

  # A visitor submits the idea on `/`, signs up with it, then logs in.
  defp sign_up_with_idea(conn) do
    {:ok, home, _html} = live(conn, ~p"/")

    {:error, {:live_redirect, %{to: register_path}}} =
      home
      |> form("#idea-form", idea: %{text: @valid_idea})
      |> render_submit()

    email = "owner-#{System.unique_integer([:positive])}@example.com"
    {:ok, register, _html} = live(conn, register_path)

    register
    |> form("#registration_form", user: %{email: email})
    |> render_submit()

    user = Accounts.get_user_by_email(email)
    %{user: user, scope: Scope.for_user(user), conn: log_in_user(build_conn(), user)}
  end

  defp profile_field(name), do: "#company-profile-form [name='company[#{name}]']"

  # ---------------------------------------------------------------------
  # HAPPY PATH
  # ---------------------------------------------------------------------

  describe "Scenario: AC1 — a visitor who signed up with an idea lands on the dashboard" do
    setup %{conn: conn} do
      %{conn: conn, scope: scope} = sign_up_with_idea(conn)
      {:ok, dashboard, _html} = live(conn, ~p"/dashboard")

      %{dashboard: dashboard, scope: scope, companies: Companies.list_companies(scope)}
    end

    test "creates one company owned by them", %{companies: companies} do
      assert [_company] = companies
    end

    test "uses the idea as the company description", %{companies: companies} do
      assert [%{description: @valid_idea}] = companies
    end

    test "shows the company on the dashboard", %{dashboard: dashboard} do
      assert has_element?(dashboard, "#current-company", @valid_idea)
    end

    test "marks the idea as turned into a company", %{scope: scope} do
      refute Ideas.latest_unclaimed_for_user(scope)
    end
  end

  describe "Scenario: AC1 — the owner opens the dashboard again in another tab" do
    setup %{conn: conn} do
      %{conn: conn, scope: scope} = sign_up_with_idea(conn)
      {:ok, _first_tab, _html} = live(conn, ~p"/dashboard")
      {:ok, _second_tab, _html} = live(conn, ~p"/dashboard")

      %{companies: Companies.list_companies(scope)}
    end

    test "still has exactly one company", %{companies: companies} do
      assert length(companies) == 1
    end
  end

  describe "Scenario: AC2 — the owner opens the new company's profile from the dashboard" do
    setup :register_and_log_in_user

    setup %{conn: conn, scope: scope} do
      company = company_fixture(scope)
      {:ok, dashboard, _html} = live(conn, ~p"/dashboard")
      result = dashboard |> element("#company-profile-link") |> render_click()
      {:ok, profile, _html} = follow_redirect(result, conn)

      %{result: result, profile: profile, profile_path: ~p"/companies/#{company.id}/profile"}
    end

    test "navigates to the company profile", %{result: result, profile_path: profile_path} do
      assert {:error, {:live_redirect, %{to: ^profile_path}}} = result
    end

    test "offers the name field", %{profile: profile} do
      assert has_element?(profile, profile_field("name"))
    end

    test "offers the industry field", %{profile: profile} do
      assert has_element?(profile, profile_field("industry"))
    end

    test "offers the city field", %{profile: profile} do
      assert has_element?(profile, profile_field("city"))
    end

    test "offers the contact email field", %{profile: profile} do
      assert has_element?(profile, profile_field("contact_email"))
    end
  end

  describe "Scenario: AC2 — the owner edits and saves the profile" do
    setup :register_and_log_in_user

    setup %{conn: conn, scope: scope} do
      company = company_fixture(scope)
      {:ok, profile, _html} = live(conn, ~p"/companies/#{company.id}/profile")

      profile
      |> form("#company-profile-form",
        company: %{
          name: "Piekarnia Pod Wawelem",
          industry: "Piekarnictwo",
          city: "Kraków",
          contact_email: "kontakt@piekarnia.pl"
        }
      )
      |> render_submit()

      %{saved: Companies.get_company!(scope, company.id)}
    end

    test "saves the name", %{saved: saved} do
      assert saved.name == "Piekarnia Pod Wawelem"
    end

    test "saves the industry", %{saved: saved} do
      assert saved.industry == "Piekarnictwo"
    end

    test "saves the city", %{saved: saved} do
      assert saved.city == "Kraków"
    end

    test "saves the contact email", %{saved: saved} do
      assert saved.contact_email == "kontakt@piekarnia.pl"
    end
  end

  # ---------------------------------------------------------------------
  # SAD PATH
  # ---------------------------------------------------------------------

  describe "Scenario: AC3 — rejecting a profile with the name cleared" do
    setup :register_and_log_in_user

    setup %{conn: conn, scope: scope} do
      company = company_fixture(scope)
      {:ok, profile, _html} = live(conn, ~p"/companies/#{company.id}/profile")

      profile
      |> form("#company-profile-form", company: %{name: ""})
      |> render_submit()

      %{profile: profile, company: company, saved: Companies.get_company!(scope, company.id)}
    end

    test "shows that the name is required", %{profile: profile} do
      assert has_element?(profile, "#company-profile-form", "nie może być puste")
    end

    test "keeps the previous name", %{saved: saved, company: company} do
      assert saved.name == company.name
    end
  end

  describe "Scenario: rejecting another owner's company profile" do
    setup :register_and_log_in_user

    setup do
      %{other_company: company_fixture(user_scope_fixture())}
    end

    test "responds with not found", %{conn: conn, other_company: other_company} do
      assert_raise Ecto.NoResultsError, fn ->
        live(conn, ~p"/companies/#{other_company.id}/profile")
      end
    end
  end
end
