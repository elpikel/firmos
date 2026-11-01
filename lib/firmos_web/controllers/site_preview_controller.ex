defmodule FirmosWeb.SitePreviewController do
  @moduledoc """
  The owner's preview of their site's current draft, or with
  `?version=<n>` of version n (e.g. a version an agent asks to publish,
  STORY-014), rendered by `FirmosWeb.SiteComponents.landing/1` in the
  minimal `:site` root layout: the same component and layout as the public
  page, so the draft looks exactly as customers will see it.

  The company and the version are loaded through the owner's scope, so
  another owner's company id, an unknown version number or a malformed one
  is a 404. Previews are never indexed (`x-robots-tag`).
  """
  use FirmosWeb, :controller

  alias Firmos.Companies
  alias Firmos.Sites
  alias Firmos.Sites.Content
  alias Firmos.Sites.Version

  def show(conn, %{"id" => id} = params) do
    scope = conn.assigns.current_scope
    company = Companies.get_company!(scope, id)

    case preview_content(scope, company, params) do
      %Content{} = content ->
        conn
        |> put_root_layout(html: {FirmosWeb.Layouts, :site})
        |> put_resp_header("x-robots-tag", "noindex, nofollow")
        |> render(:show,
          company: company,
          content: content,
          page_title: gettext("Preview: %{name}", name: company.name)
        )

      nil ->
        conn
        |> put_flash(:error, gettext("There is no website draft to preview yet."))
        |> redirect(to: ~p"/companies/#{company.id}/site")
    end
  end

  defp preview_content(scope, company, %{"version" => number}) do
    %Version{content: content} = Sites.get_version!(scope, company, parse_number!(number))
    content
  end

  defp preview_content(scope, company, _current_draft) do
    case Sites.get_site(scope, company) do
      %{current_version: %{content: %Content{} = content}} -> content
      _no_draft -> nil
    end
  end

  # A malformed number names no version: a 404, like an unknown one.
  defp parse_number!(number) when is_binary(number) do
    case Integer.parse(number) do
      {int, ""} when int > 0 -> int
      _invalid -> raise Ecto.NoResultsError, queryable: Version
    end
  end

  defp parse_number!(_not_a_string), do: raise(Ecto.NoResultsError, queryable: Version)
end
