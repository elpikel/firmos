defmodule FirmosWeb.CompanyLive.Approvals do
  @moduledoc """
  The company's approval queue: the agents' pending requests to publish a
  website version, each with a preview of that version and approve /
  reject buttons, and the latest decided requests below.

  The company is loaded through the owner's scope, so another owner's
  company id is a 404. The pending requests the page shows are held in the
  socket (loaded through the owner's scope); an approve or reject event
  only names one of them, and an id the page doesn't hold does nothing.
  `Firmos.Approvals` re-checks ownership and that the request still
  applies. The page follows the queue and the site live through
  `Firmos.Approvals.subscribe/2` and `Firmos.Sites.subscribe/2` (a site
  change can outdate a request, which then moves to the history).
  """
  use FirmosWeb, :live_view

  import FirmosWeb.ActivityComponents, only: [actor_label: 1]

  alias Firmos.Approvals
  alias Firmos.Approvals.Approval
  alias Firmos.Companies
  alias Firmos.Sites

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    scope = socket.assigns.current_scope
    company = Companies.get_company!(scope, id)

    if connected?(socket) do
      :ok = Approvals.subscribe(scope, company)
      :ok = Sites.subscribe(scope, company)
    end

    {:ok,
     socket
     |> assign(:page_title, gettext("Approvals"))
     |> assign(:company, company)
     |> assign(:no_slug?, false)
     |> stream_configure(:pending, dom_id: &"approvals-#{&1.id}")
     |> stream_configure(:decided, dom_id: &"decided-#{&1.id}")
     |> load()}
  end

  @impl true
  def handle_event(event, %{"id" => id}, socket)
      when event in ["approve", "reject"] and is_binary(id) do
    case Map.fetch(socket.assigns.pending, id) do
      {:ok, approval} ->
        result = decide(event, socket.assigns.current_scope, approval)
        {:noreply, socket |> put_result(event, result) |> load()}

      :error ->
        {:noreply, socket |> put_result(event, {:error, :not_found}) |> load()}
    end
  end

  # Forged events change nothing.
  def handle_event(_event, _params, socket), do: {:noreply, socket}

  @impl true
  def handle_info(
        {event, %{company_id: company_id}},
        %{assigns: %{company: %{id: company_id}}} = socket
      )
      when event in [:approvals_updated, :site_updated] do
    {:noreply, load(socket)}
  end

  defp decide("approve", scope, approval), do: Approvals.approve(scope, approval)
  defp decide("reject", scope, approval), do: Approvals.reject(scope, approval)

  defp put_result(socket, "approve", {:ok, _approval}) do
    socket
    |> assign(:no_slug?, false)
    |> put_flash(:info, gettext("Approved. Your website is published."))
  end

  defp put_result(socket, "reject", {:ok, _approval}),
    do: put_flash(socket, :info, gettext("Rejected. Nothing was published."))

  defp put_result(socket, _event, {:error, :outdated}) do
    put_flash(
      socket,
      :error,
      gettext("This request is outdated: the website changed after it was made.")
    )
  end

  defp put_result(socket, _event, {:error, :no_slug}) do
    socket
    |> assign(:no_slug?, true)
    |> put_flash(:error, gettext("Choose your website's address before approving."))
  end

  defp put_result(socket, _event, {:error, :already_decided}),
    do: put_flash(socket, :error, gettext("This request has already been decided."))

  defp put_result(socket, _event, {:error, :not_found}),
    do: put_flash(socket, :error, gettext("This request no longer exists."))

  defp put_result(socket, _event, {:error, _reason}),
    do: put_flash(socket, :error, gettext("Could not save your decision. Please try again."))

  defp load(socket) do
    %{current_scope: scope, company: company} = socket.assigns
    pending = Approvals.list_pending(scope, company)
    decided = Approvals.list_decided(scope, company)

    socket
    |> assign(:pending, Map.new(pending, &{Integer.to_string(&1.id), &1}))
    |> assign(:decided_empty?, decided == [])
    |> stream(:pending, pending, reset: true)
    |> stream(:decided, decided, reset: true)
  end

  defp request_title(%Approval{kind: :publish_site_version, site_version: version}),
    do: gettext("Publish version %{version} of the website", version: version.number)

  # The history also lists pending requests that became outdated
  # (`Firmos.Approvals.list_decided/2`); they show as outdated.
  defp history_status(%Approval{status: :pending}), do: :superseded
  defp history_status(%Approval{status: status}), do: status

  defp history_time(%Approval{decided_at: nil, updated_at: at}), do: at
  defp history_time(%Approval{decided_at: at}), do: at

  defp status_label(:approved), do: gettext("Approved")
  defp status_label(:rejected), do: gettext("Rejected")
  defp status_label(:superseded), do: gettext("Outdated")

  defp status_class(:approved), do: "bg-emerald-50 text-emerald-700 ring-emerald-200"
  defp status_class(:rejected), do: "bg-red-50 text-red-700 ring-red-200"
  defp status_class(:superseded), do: "bg-zinc-100 text-zinc-600 ring-zinc-200"

  # No tz database yet, so times show in UTC with a label (#14).
  defp format_timestamp(%DateTime{} = at),
    do: gettext("%{time} UTC", time: Calendar.strftime(at, "%d.%m.%Y, %H:%M"))

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <section id="company-approvals" class="mx-auto max-w-3xl space-y-8">
        <header class="space-y-4">
          <.link
            id="company-approvals-back"
            navigate={~p"/dashboard?company=#{@company.id}"}
            class="inline-flex items-center gap-1 text-sm font-medium text-zinc-500 transition hover:text-zinc-900"
          >
            <.icon name="hero-arrow-left" class="size-4" />
            {gettext("Dashboard")}
          </.link>
          <div class="space-y-1">
            <h1 class="text-2xl font-semibold tracking-tight text-zinc-900">
              {gettext("Approvals")}
            </h1>
            <p class="text-sm text-zinc-500">
              {@company.name} · {gettext(
                "Nothing the AI agent asks for goes live without your consent."
              )}
            </p>
          </div>
        </header>

        <div
          :if={@no_slug?}
          id="approvals-no-slug"
          class="flex items-start gap-3 rounded-2xl border border-amber-200 bg-amber-50 px-5 py-4 text-sm text-amber-900"
        >
          <.icon name="hero-globe-alt" class="mt-0.5 size-5 shrink-0" />
          <p>
            {gettext("Your website needs an address before it can be published.")}
            <.link
              id="approvals-site-link"
              navigate={~p"/companies/#{@company.id}/site"}
              class="font-semibold underline underline-offset-4 transition hover:text-amber-700"
            >
              {gettext("Choose the address")}
            </.link>
          </p>
        </div>

        <section class="space-y-3">
          <h2 class="text-sm font-semibold uppercase tracking-wide text-zinc-500">
            {gettext("Waiting for your decision")}
          </h2>
          <div id="approvals-pending" phx-update="stream" class="space-y-3">
            <div
              id="approvals-pending-empty"
              class="hidden flex-col items-center gap-3 rounded-2xl border border-dashed border-zinc-300 px-6 py-12 text-center only:flex"
            >
              <span class="flex size-10 items-center justify-center rounded-full bg-zinc-100">
                <.icon name="hero-check" class="size-5 text-zinc-500" />
              </span>
              <p class="text-sm text-zinc-500">{gettext("Nothing waits for your approval.")}</p>
            </div>
            <article
              :for={{dom_id, approval} <- @streams.pending}
              id={dom_id}
              class="group space-y-4 rounded-2xl border border-amber-200 bg-white p-5 shadow-sm transition hover:border-amber-300 hover:shadow-md"
            >
              <div class="flex flex-wrap items-start justify-between gap-3">
                <div class="space-y-1">
                  <p class="text-sm font-semibold text-zinc-900">{request_title(approval)}</p>
                  <p class="flex items-center gap-1.5 text-xs text-zinc-500">
                    <.icon name="hero-sparkles" class="size-3.5" />
                    {actor_label(approval.requested_by)} · {format_timestamp(approval.inserted_at)}
                  </p>
                </div>
                <.link
                  id={"preview-#{approval.id}"}
                  href={
                    ~p"/companies/#{@company.id}/site/preview?version=#{approval.site_version.number}"
                  }
                  target="_blank"
                  rel="noopener"
                  class="inline-flex items-center gap-1.5 rounded-lg border border-zinc-200 px-3 py-1.5 text-sm font-medium text-zinc-700 transition hover:border-zinc-300 hover:bg-zinc-50"
                >
                  <.icon name="hero-eye" class="size-4" />
                  {gettext("Preview")}
                </.link>
              </div>
              <div class="flex flex-wrap items-center gap-2 border-t border-zinc-100 pt-4">
                <button
                  id={"approve-#{approval.id}"}
                  type="button"
                  phx-click="approve"
                  phx-value-id={approval.id}
                  phx-disable-with={gettext("Publishing...")}
                  class="inline-flex items-center gap-1.5 rounded-lg bg-emerald-600 px-4 py-2 text-sm font-semibold text-white shadow-sm transition hover:bg-emerald-500 active:scale-[0.98]"
                >
                  <.icon name="hero-check" class="size-4" />
                  {gettext("Approve and publish")}
                </button>
                <button
                  id={"reject-#{approval.id}"}
                  type="button"
                  phx-click="reject"
                  phx-value-id={approval.id}
                  phx-disable-with={gettext("Rejecting...")}
                  class="inline-flex items-center gap-1.5 rounded-lg border border-zinc-200 px-4 py-2 text-sm font-semibold text-zinc-700 transition hover:border-red-200 hover:bg-red-50 hover:text-red-700 active:scale-[0.98]"
                >
                  <.icon name="hero-x-mark" class="size-4" />
                  {gettext("Reject")}
                </button>
              </div>
            </article>
          </div>
        </section>

        <section class="space-y-3">
          <h2 class="text-sm font-semibold uppercase tracking-wide text-zinc-500">
            {gettext("Decided")}
          </h2>
          <p :if={@decided_empty?} id="approvals-history-empty" class="text-sm text-zinc-500">
            {gettext("No decisions yet.")}
          </p>
          <ul id="approvals-history" phx-update="stream" class="space-y-2">
            <li
              :for={{dom_id, approval} <- @streams.decided}
              id={dom_id}
              class="flex flex-wrap items-center justify-between gap-3 rounded-xl border border-zinc-200 bg-white px-4 py-3 text-sm transition hover:border-zinc-300"
            >
              <span class="text-zinc-700">{request_title(approval)}</span>
              <span class="flex items-center gap-3">
                <time
                  datetime={DateTime.to_iso8601(history_time(approval))}
                  class="text-xs tabular-nums text-zinc-500"
                >
                  {format_timestamp(history_time(approval))}
                </time>
                <span
                  data-status={history_status(approval)}
                  class={[
                    "rounded-full px-2.5 py-0.5 text-xs font-medium ring-1 ring-inset",
                    status_class(history_status(approval))
                  ]}
                >
                  {status_label(history_status(approval))}
                </span>
              </span>
            </li>
          </ul>
        </section>
      </section>
    </Layouts.app>
    """
  end
end
