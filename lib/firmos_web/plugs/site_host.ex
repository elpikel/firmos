defmodule FirmosWeb.Plugs.SiteHost do
  @moduledoc """
  Serves published sites on their own host (`<slug>.<base domain>`).

  Plugged into `FirmosWeb.Endpoint` before the session and the router, so a
  site's response never carries the app's session cookie, CSRF token or
  JavaScript. A host `FirmosWeb.SiteDomain.slug_from_host/1` accepts is
  answered by `FirmosWeb.PublicSiteController` and halted; every other host
  (the bare base domain, `www`, the app's own host) passes through to the
  app untouched.

  Sites are read-only: only `GET` (and `HEAD`, which `Plug.Head` turns into
  a `GET` upstream) is served, anything else is `405`.
  """
  @behaviour Plug

  import Plug.Conn

  alias FirmosWeb.PublicSiteController
  alias FirmosWeb.SiteDomain

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    case SiteDomain.slug_from_host(conn.host) do
      {:ok, slug} -> conn |> serve(slug) |> halt()
      :error -> conn
    end
  end

  defp serve(%Plug.Conn{method: "GET"} = conn, slug) do
    conn
    |> assign(:site_slug, slug)
    |> PublicSiteController.call(PublicSiteController.init(:show))
  end

  defp serve(conn, _slug) do
    conn
    |> put_resp_header("allow", "GET, HEAD")
    |> send_resp(405, "")
  end
end
