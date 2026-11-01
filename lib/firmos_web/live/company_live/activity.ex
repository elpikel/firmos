defmodule FirmosWeb.CompanyLive.Activity do
  @moduledoc """
  The company's activity log, newest first, 50 entries at a time with a
  "Load more" button. The company is loaded through the owner's scope, so
  another owner's company id is a 404. The paging cursor stays in the socket;
  the client never sends one.

  The latest website change can be undone from here (`#undo-entry-<id>`,
  offered on the entry `Firmos.Sites.undoable_entry/2` names). The page
  follows the company's site changes: it prepends the entries logged since
  and re-renders the entries losing or gaining the button, keeping the
  pages already loaded. `Firmos.Sites.undo/3` re-checks the entry id the
  client sends.
  """
  use FirmosWeb, :live_view

  import FirmosWeb.ActivityComponents

  alias Firmos.Activity
  alias Firmos.Companies
  alias Firmos.Sites

  @page_size 50

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    scope = socket.assigns.current_scope
    company = Companies.get_company!(scope, id)
    if connected?(socket), do: :ok = Sites.subscribe(scope, company)

    {:ok,
     socket
     |> assign(:page_title, gettext("Activity"))
     |> assign(:company, company)
     |> assign(:undoable_entry, Sites.undoable_entry(scope, company))
     |> load_page(nil)}
  end

  @impl true
  def handle_event("load-more", _params, %{assigns: %{cursor: cursor}} = socket)
      when not is_nil(cursor) do
    {:noreply, load_page(socket, cursor)}
  end

  def handle_event("load-more", _params, socket), do: {:noreply, socket}

  def handle_event("undo", %{"id" => id}, socket) when is_binary(id) do
    %{current_scope: scope, company: company} = socket.assigns

    result =
      case Integer.parse(id) do
        {entry_id, ""} -> Sites.undo(scope, company, entry_id)
        _not_an_id -> {:error, :not_found}
      end

    {:noreply, socket |> put_undo_flash(result) |> refresh()}
  end

  # Forged events change nothing.
  def handle_event(_event, _params, socket), do: {:noreply, socket}

  @impl true
  def handle_info({:site_updated, _site}, socket), do: {:noreply, refresh(socket)}

  defp put_undo_flash(socket, {:ok, _site}),
    do: put_flash(socket, :info, gettext("Change undone. The previous version is back."))

  defp put_undo_flash(socket, {:error, :not_undoable}) do
    put_flash(
      socket,
      :error,
      gettext("Nothing to undo: the website has changed in the meantime.")
    )
  end

  defp put_undo_flash(socket, {:error, :generation_in_progress}) do
    put_flash(
      socket,
      :error,
      gettext("A new website is being generated. Try again when it's ready.")
    )
  end

  defp put_undo_flash(socket, {:error, _reason}),
    do: put_flash(socket, :error, gettext("Could not undo the change."))

  # Brings the page up to date without dropping loaded pages: prepends what
  # was logged since the newest entry shown and re-renders the entries whose
  # undo button appears or disappears (streamed items only re-render when
  # re-inserted). More than a page logged since → start over from the top.
  defp refresh(socket) do
    %{current_scope: scope, company: company, newest: newest} = socket.assigns
    old_undoable = socket.assigns.undoable_entry
    socket = assign(socket, :undoable_entry, Sites.undoable_entry(scope, company))
    newer = Activity.list_for_company(scope, company, limit: @page_size + 1, after: newest)

    if length(newer) > @page_size do
      load_page(socket, nil)
    else
      socket
      |> prepend(newer)
      |> restream_if_changed(old_undoable)
    end
  end

  # `entries` are newest first; inserting each at the top, oldest first,
  # leaves them newest first.
  defp prepend(socket, []), do: socket

  defp prepend(socket, [newest | _] = entries) do
    socket
    |> stream(:activities, Enum.reverse(entries), at: 0)
    |> assign(:newest, Activity.cursor(newest))
  end

  defp restream_if_changed(%{assigns: %{undoable_entry: same}} = socket, same), do: socket

  defp restream_if_changed(socket, old_undoable) do
    [old_undoable, socket.assigns.undoable_entry]
    |> Enum.filter(&loaded?(socket, &1))
    |> Enum.reduce(socket, &stream_insert(&2, :activities, &1))
  end

  # Whether `entry` is on a page already shown (and not just logged).
  defp loaded?(_socket, nil), do: false

  defp loaded?(%{assigns: %{newest: newest, cursor: oldest}}, entry) do
    at = Activity.cursor(entry)
    not is_nil(newest) and not after?(at, newest) and (is_nil(oldest) or not after?(oldest, at))
  end

  defp after?({at_a, id_a}, {at_b, id_b}) do
    case DateTime.compare(at_a, at_b) do
      :gt -> true
      :eq -> id_a > id_b
      :lt -> false
    end
  end

  # Reads one extra entry to know whether another page exists. The first
  # page resets the stream and remembers the newest entry shown.
  defp load_page(socket, before) do
    %{current_scope: scope, company: company} = socket.assigns
    entries = Activity.list_for_company(scope, company, limit: @page_size + 1, before: before)
    {page, rest} = Enum.split(entries, @page_size)

    socket
    |> stream(:activities, page, reset: is_nil(before))
    |> assign(:cursor, if(rest != [], do: page |> List.last() |> Activity.cursor()))
    |> assign_newest(before, page)
  end

  defp assign_newest(socket, nil, [newest | _]),
    do: assign(socket, :newest, Activity.cursor(newest))

  defp assign_newest(socket, nil, []), do: assign(socket, :newest, nil)
  defp assign_newest(socket, _older_page, _page), do: socket

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
          <.activity_entry :for={{dom_id, entry} <- @streams.activities} id={dom_id} entry={entry}>
            <:actions :if={@undoable_entry && entry.id == @undoable_entry.id}>
              <button
                id={"undo-entry-#{entry.id}"}
                type="button"
                phx-click="undo"
                phx-value-id={entry.id}
                phx-disable-with={gettext("Undoing...")}
                class="inline-flex items-center gap-1.5 rounded-lg border border-zinc-200 bg-white px-3 py-1.5 text-xs font-semibold text-zinc-700 shadow-sm transition hover:border-zinc-300 hover:bg-zinc-50 hover:text-zinc-900 active:scale-[0.98]"
              >
                <.icon name="hero-arrow-uturn-left" class="size-3.5" />
                {gettext("Undo")}
              </button>
            </:actions>
          </.activity_entry>
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
