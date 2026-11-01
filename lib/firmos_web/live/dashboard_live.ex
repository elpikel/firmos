defmodule FirmosWeb.DashboardLive do
  @moduledoc """
  The signed-in owner's landing page. Lives in the `:require_authenticated_user`
  live_session, so `@current_scope.user` is always present here.
  """
  use FirmosWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :page_title, gettext("Dashboard"))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <section id="dashboard" class="mx-auto max-w-3xl space-y-8">
        <header class="space-y-1">
          <p class="text-sm font-medium text-zinc-500">{gettext("Dashboard")}</p>
          <h1 id="dashboard-greeting" class="text-2xl font-semibold tracking-tight text-zinc-900">
            {gettext("Welcome, %{email}", email: @current_scope.user.email)}
          </h1>
        </header>

        <div
          id="dashboard-empty"
          class="flex flex-col items-center gap-3 rounded-2xl border border-dashed border-zinc-300 px-6 py-16 text-center transition-colors hover:border-zinc-400"
        >
          <span class="flex size-12 items-center justify-center rounded-full bg-zinc-100">
            <.icon name="hero-squares-2x2" class="size-6 text-zinc-500" />
          </span>
          <h2 class="text-base font-semibold text-zinc-900">{gettext("Nothing here yet")}</h2>
          <p class="max-w-sm text-sm text-zinc-500">
            {gettext("Your firm's activity will show up here once you start using Firmos.")}
          </p>
        </div>
      </section>
    </Layouts.app>
    """
  end
end
