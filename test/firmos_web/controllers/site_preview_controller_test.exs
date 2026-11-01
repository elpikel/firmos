defmodule FirmosWeb.SitePreviewControllerTest do
  use FirmosWeb.ConnCase, async: true
  use Oban.Testing, repo: Firmos.Repo

  import Firmos.CompaniesFixtures
  import Firmos.PlansFixtures
  import Firmos.SitesFixtures
  import Mox

  alias Firmos.Plans
  alias Firmos.Sites

  setup :verify_on_exit!
  setup :register_and_log_in_user

  setup %{scope: scope} do
    company = company_fixture(scope)
    expect_ai_reply({:ok, plan_json()})
    {:ok, _plan} = Plans.generate_plan(Plans.current_plan(scope, company).id)
    %{company: company}
  end

  defp generate_site(scope, company, json) do
    {:ok, site} = Sites.request_generation(scope, company)
    expect_ai_reply({:ok, json})
    {:ok, _version} = Sites.generate_site(site.id, 1)
  end

  test "renders the draft without the app chrome and keeps it out of search engines",
       %{conn: conn, scope: scope, company: company} do
    generate_site(scope, company, site_json())
    conn = get(conn, ~p"/companies/#{company.id}/site/preview")
    document = conn |> html_response(200) |> LazyHTML.from_document()

    assert get_resp_header(conn, "x-robots-tag") == ["noindex, nofollow"]
    refute Enum.empty?(LazyHTML.query(document, "#site-landing"))
    assert Enum.empty?(LazyHTML.query(document, "#auth-nav"))
    assert Enum.empty?(LazyHTML.query(document, "script"))
  end

  test "escapes a script the AI returned", %{conn: conn, scope: scope, company: company} do
    hero = Map.put(site_attrs()["hero"], "headline", "<script>alert(1)</script>")
    generate_site(scope, company, site_json(%{"hero" => hero}))

    document =
      conn
      |> get(~p"/companies/#{company.id}/site/preview")
      |> html_response(200)
      |> LazyHTML.from_document()

    assert Enum.empty?(LazyHTML.query(document, "script"))
    assert document |> LazyHTML.query("#site-hero h1") |> LazyHTML.text() =~ "<script>"
  end

  test "redirects to the website section when there is no draft yet",
       %{conn: conn, company: company} do
    conn = get(conn, ~p"/companies/#{company.id}/site/preview")
    assert redirected_to(conn) == ~p"/companies/#{company.id}/site"
  end

  test "requires a signed-in owner", %{company: company} do
    conn = get(build_conn(), ~p"/companies/#{company.id}/site/preview")
    assert redirected_to(conn) == ~p"/users/log-in"
  end

  describe "?version=<n>" do
    setup %{scope: scope, company: company} do
      generate_site(scope, company, site_json())
      site = Sites.get_site(scope, company)
      {:ok, _site} = Sites.update_content(scope, site, %{"hero" => %{"headline" => "Druga"}})
      :ok
    end

    defp preview_headline(conn) do
      conn
      |> html_response(200)
      |> LazyHTML.from_document()
      |> LazyHTML.query("#site-hero h1")
      |> LazyHTML.text()
    end

    test "renders that version", %{conn: conn, company: company} do
      conn = get(conn, ~p"/companies/#{company.id}/site/preview?version=1")
      assert preview_headline(conn) =~ site_attrs()["hero"]["headline"]
    end

    test "renders a later version", %{conn: conn, company: company} do
      conn = get(conn, ~p"/companies/#{company.id}/site/preview?version=2")
      assert preview_headline(conn) =~ "Druga"
    end

    for version <- ["3", "0", "abc", "1x"] do
      test "responds with not found for version #{version}", %{conn: conn, company: company} do
        assert_error_sent 404, fn ->
          get(conn, ~p"/companies/#{company.id}/site/preview?version=#{unquote(version)}")
        end
      end
    end

    test "responds with not found for a malformed version param",
         %{conn: conn, company: company} do
      assert_error_sent 404, fn ->
        get(conn, "/companies/#{company.id}/site/preview?version[]=1")
      end
    end

    test "responds with not found for another owner's company", %{company: company} do
      conn = log_in_user(build_conn(), Firmos.AccountsFixtures.user_fixture())

      assert_error_sent 404, fn ->
        get(conn, ~p"/companies/#{company.id}/site/preview?version=1")
      end
    end
  end
end
