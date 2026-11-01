defmodule FirmosWeb.SitePreviewController do
  @moduledoc """
  The owner's preview of their site's current draft, rendered by
  `FirmosWeb.SiteComponents.landing/1` in the minimal `:site` root layout:
  the same component and layout as the public page, so the draft looks
  exactly as customers will see it.

  The company is loaded through the owner's scope, so another owner's
  company id is a 404. Previews are never indexed (`x-robots-tag`).
  """
  use FirmosWeb, :controller

  alias Firmos.Companies
  alias Firmos.Sites
  alias Firmos.Sites.Content

  def show(conn, %{"id" => id}) do
    scope = conn.assigns.current_scope
    company = Companies.get_company!(scope, id)

    case Sites.get_site(scope, company) do
      %{current_version: %{content: %Content{} = content}} ->
        conn
        |> put_root_layout(html: {FirmosWeb.Layouts, :site})
        |> put_resp_header("x-robots-tag", "noindex, nofollow")
        |> render(:show,
          company: company,
          content: content,
          page_title: gettext("Preview: %{name}", name: company.name)
        )

      _no_draft ->
        conn
        |> put_flash(:error, gettext("There is no website draft to preview yet."))
        |> redirect(to: ~p"/companies/#{company.id}/site")
    end
  end
end
