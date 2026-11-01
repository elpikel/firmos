defmodule FirmosWeb.PageController do
  use FirmosWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
