defmodule FirmosWeb.SitePreviewHTML do
  @moduledoc """
  The draft preview page: a slim preview bar above the landing page. The bar
  is the only difference from the public page.
  """
  use FirmosWeb, :html

  import FirmosWeb.SiteComponents

  def show(assigns) do
    ~H"""
    <div
      id="site-preview-bar"
      class="flex flex-wrap items-center justify-between gap-2 bg-amber-300 px-4 py-2 text-sm text-stone-950"
    >
      <p class="flex items-center gap-2 font-medium">
        <.icon name="hero-eye" class="size-4" />
        {gettext("Draft preview. This is how customers will see your website.")}
      </p>
      <.link
        id="site-preview-back"
        href={~p"/companies/#{@company.id}/site"}
        class="inline-flex items-center gap-1 font-semibold underline-offset-4 hover:underline"
      >
        <.icon name="hero-arrow-left" class="size-4" />
        {gettext("Back to website")}
      </.link>
    </div>
    <.landing content={@content} name={@company.name} />
    """
  end
end
