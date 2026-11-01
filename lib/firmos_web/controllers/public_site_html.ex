defmodule FirmosWeb.PublicSiteHTML do
  @moduledoc "A published landing page and the public sites' 404 page."
  use FirmosWeb, :html

  import FirmosWeb.SiteComponents

  def show(assigns) do
    ~H"""
    <.landing content={@content} name={@name} />
    """
  end

  def not_found(assigns) do
    ~H"""
    <main
      id="site-not-found"
      class="flex min-h-screen flex-col items-center justify-center gap-4 bg-stone-50 px-6 text-center text-stone-900 antialiased"
    >
      <p class="text-sm font-semibold uppercase tracking-[0.2em] text-amber-700">404</p>
      <h1 class="text-3xl font-semibold tracking-tight sm:text-4xl">
        {gettext("This page doesn't exist")}
      </h1>
      <p class="max-w-md text-stone-600">
        {gettext("The address may be mistyped, or the website isn't published yet.")}
      </p>
    </main>
    """
  end
end
