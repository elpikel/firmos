defmodule FirmosWeb.CompanyLive.Activity do
  @moduledoc """
  The company's activity log, newest first, 50 entries at a time with a
  "Load more" button. The company is loaded through the owner's scope, so
  another owner's company id is a 404. The paging cursor stays in the socket;
  the client never sends one.
  """
  use FirmosWeb, :live_view

  import FirmosWeb.ActivityComponents

  alias Firmos.Activity
  alias Firmos.Companies

  @page_size 50

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    company = Companies.get_company!(socket.assigns.current_scope, id)

    {:ok,
     socket
     |> assign(:page_title, gettext("Activity"))
     |> assign(:company, company)
     |> stream(:activities, [])
     |> load_page(nil)}
  end

  @impl true
  def handle_event("load-more", _params, %{assigns: %{cursor: cursor}} = socket)
      when not is_nil(cursor) do
    {:noreply, load_page(socket, cursor)}
  end

  def handle_event("load-more", _params, socket), do: {:noreply, socket}

  # Reads one extra entry to know whether another page exists.
  defp load_page(socket, before) do
    %{current_scope: scope, company: company} = socket.assigns
    entries = Activity.list_for_company(scope, company, limit: @page_size + 1, before: before)
    {page, rest} = Enum.split(entries, @page_size)

    socket
    |> stream(:activities, page)
    |> assign(:cursor, if(rest != [], do: page |> List.last() |> Activity.cursor()))
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <section id="company-activity" class="mx-auto max-w-2xl space-y-8">
        <header class="space-y-2">
          <.link
            id="company-activity-back"
            navigate={~p"/dashboard"}
            class="inline-flex items-center gap-1 text-sm font-medium text-zinc-500 transition hover:text-zinc-900"
          >
            <.icon name="hero-arrow-left" class="size-4" />
            {gettext("Dashboard")}
          </.link>
          <h1 class="text-2xl font-semibold tracking-tight text-zinc-900">
            {gettext("Activity")}
          </h1>
          <p class="text-sm text-zinc-500">
            {gettext("Everything done in %{company}, by you or by AI, newest first.",
              company: @company.name
            )}
          </p>
        </header>

        <div id="activities" phx-update="stream" class="space-y-3">
          <div
            id="activities-empty"
            class="hidden flex-col items-center gap-3 rounded-2xl border border-dashed border-zinc-300 px-6 py-16 text-center only:flex"
          >
            <span class="flex size-12 items-center justify-center rounded-full bg-zinc-100">
              <.icon name="hero-clock" class="size-6 text-zinc-500" />
            </span>
            <p class="max-w-sm text-sm text-zinc-500">
              {gettext("No activity yet. Changes to your company will show up here.")}
            </p>
          </div>
          <.activity_entry :for={{dom_id, entry} <- @streams.activities} id={dom_id} entry={entry} />
        </div>

        <div :if={@cursor} class="flex justify-center">
          <.button
            id="activities-load-more"
            type="button"
            phx-click="load-more"
            phx-disable-with={gettext("Loading...")}
          >
            {gettext("Load more")}
          </.button>
        </div>
      </section>
    </Layouts.app>
    """
  end
end
