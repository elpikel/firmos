defmodule FirmosWeb.PageControllerTest do
  use FirmosWeb.ConnCase

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "Zespół AI, który prowadzi Twoją małą firmę"
  end
end
