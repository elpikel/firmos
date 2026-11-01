defmodule FirmosWeb.DashboardLive do
  @moduledoc """
  The signed-in owner's landing page. Lives in the `:require_authenticated_user`
  live_session, so `@current_scope.user` is always present here.
  """
  use FirmosWeb, :live_view

  alias Firmos.Companies

  require Logger

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope
    ensure_company_from_idea(scope)

    {:ok,
     socket
     |> assign(:page_title, gettext("Dashboard"))
     |> assign(:company, Companies.latest_company(scope))}
  end

  # Runs on both the dead and the connected mount; the context makes it
  # idempotent, so each idea becomes exactly one company. A failure must not
  # lock the owner out of the dashboard, so it is logged and the page renders.
  defp ensure_company_from_idea(scope) do
    case Companies.ensure_company_from_idea(scope, gettext("My company")) do
      {:ok, _companies} ->
        :ok

      {:error, %Ecto.Changeset{} = changeset} ->
        # Field names only: the values are the owner's idea text.
        invalid_fields = changeset.errors |> Keyword.keys() |> Enum.uniq()

        Logger.error(
          "Could not create company from idea for user_id=#{scope.user.id}, " <>
            "invalid fields: #{inspect(invalid_fields)}"
        )
    end
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

        <article
          :if={@company}
          id="current-company"
          class="group space-y-4 rounded-2xl border border-zinc-200 bg-white p-6 shadow-sm transition hover:border-zinc-300 hover:shadow-md"
        >
          <div class="flex items-start justify-between gap-4">
            <div class="space-y-1">
              <p class="text-xs font-medium uppercase tracking-wide text-zinc-500">
                {gettext("Your company")}
              </p>
              <h2 id="current-company-name" class="text-lg font-semibold text-zinc-900">
                {@company.name}
              </h2>
            </div>
            <.link
              id="company-profile-link"
              navigate={~p"/companies/#{@company.id}/profile"}
              class="inline-flex items-center gap-1.5 rounded-lg border border-zinc-200 px-3 py-1.5 text-sm font-medium text-zinc-700 transition hover:border-zinc-300 hover:bg-zinc-50"
            >
              <.icon name="hero-pencil-square" class="size-4" />
              {gettext("Edit profile")}
            </.link>
          </div>
          <p
            :if={@company.description}
            id="current-company-description"
            class="whitespace-pre-line text-sm leading-relaxed text-zinc-600"
          >
            {@company.description}
          </p>
        </article>

        <div
          :if={is_nil(@company)}
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
