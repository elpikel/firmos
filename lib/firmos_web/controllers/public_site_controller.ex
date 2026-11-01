defmodule FirmosWeb.PublicSiteController do
  @moduledoc """
  A company's published landing page, as customers see it on
  `<slug>.<base domain>`. Called by `FirmosWeb.Plugs.SiteHost` (not the
  router) with the host's slug in `conn.assigns.site_slug`.

  Renders the PUBLISHED version (later draft edits stay hidden until the
  owner publishes again) with `FirmosWeb.SiteComponents.landing/1` in the
  minimal `:site` root layout, like the owner's preview. The page is
  public and indexable. Only `/` exists; an unknown slug, a site that was
  never published, or any other path is a 404.
  """
  use FirmosWeb, :controller

  alias Firmos.Sites

  plug :put_format, "html"
  plug :put_root_layout, html: {FirmosWeb.Layouts, :site}
  plug :put_secure_browser_headers

  def show(%Plug.Conn{request_path: "/"} = conn, _params) do
    case Sites.get_published_by_slug(conn.assigns.site_slug) do
      {:ok, site} ->
        render(conn, :show,
          content: site.published_version.content,
          name: site.company.name,
          page_title: site.company.name
        )

      {:error, :not_found} ->
        not_found(conn)
    end
  end

  def show(conn, _params), do: not_found(conn)

  defp not_found(conn) do
    conn
    |> put_status(:not_found)
    |> render(:not_found, page_title: gettext("Page not found"))
  end
end
