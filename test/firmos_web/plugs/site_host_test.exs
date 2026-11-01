defmodule FirmosWeb.Plugs.SiteHostTest do
  use FirmosWeb.ConnCase, async: true

  import Firmos.AccountsFixtures
  import Firmos.CompaniesFixtures
  import Firmos.PlansFixtures
  import Firmos.SitesFixtures

  alias Firmos.Sites

  setup do
    scope = user_scope_fixture()
    company = company_fixture(scope)
    expect_ai_reply({:ok, plan_json()})
    %{success: 1} = Oban.drain_queue(queue: :ai, with_safety: false)
    {:ok, _site} = Sites.request_generation(scope, company)
    expect_ai_reply({:ok, site_json()})
    %{success: 1} = Oban.drain_queue(queue: :ai, with_safety: false)
    {:ok, site} = Sites.set_slug(scope, Sites.get_site(scope, company), "piekarnia")
    {:ok, _site} = Sites.publish(scope, site)
    :ok
  end

  defp request(method, host, path) do
    build_conn() |> Map.put(:host, host) |> dispatch(@endpoint, method, path)
  end

  test "answers HEAD like GET, without a body" do
    conn = request(:head, "piekarnia.localhost", "/")
    assert {conn.status, conn.resp_body} == {200, ""}
  end

  test "is indexable" do
    assert get_resp_header(request(:get, "piekarnia.localhost", "/"), "x-robots-tag") == []
  end

  test "any path other than / is a Polish 404 page" do
    conn = request(:get, "piekarnia.localhost", "/users/log-in")

    assert conn.status == 404
    assert conn.resp_body =~ "Ta strona nie istnieje"
  end

  test "answers 405 with Allow for other methods" do
    conn = request(:delete, "piekarnia.localhost", "/")
    assert {conn.status, get_resp_header(conn, "allow")} == {405, ["GET, HEAD"]}
  end

  test "still serves static assets on a site host" do
    assert request(:get, "piekarnia.localhost", "/robots.txt").status == 200
  end
end
