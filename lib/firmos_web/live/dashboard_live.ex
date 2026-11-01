defmodule FirmosWeb.DashboardLive do
  @moduledoc """
  The signed-in owner's landing page. Lives in the `:require_authenticated_user`
  live_session, so `@current_scope.user` is always present here.

  Shows one of the owner's companies at a glance: its business plan, its
  website and its latest activity. The company is the `?company=<id>` query
  param (set by `#company-switcher`), resolved through the owner's scope, so
  another owner's id is a 404; without it the dashboard shows the newest
  company. With no company at all it asks for a business idea.

  Sections follow the selected company live through `Firmos.Plans.subscribe/2`
  and `Firmos.Sites.subscribe/2`; switching companies moves the subscriptions.
  """
  use FirmosWeb, :live_view

  import FirmosWeb.ActivityComponents, only: [activity_entry: 1]

  alias Firmos.Activity
  alias Firmos.Companies
  alias Firmos.Companies.Company
  alias Firmos.Plans
  alias Firmos.Sites
  alias FirmosWeb.SiteDomain

  require Logger

  @activity_limit 5

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope
    ensure_company_from_idea(scope)

    {:ok,
     socket
     |> assign(:page_title, gettext("Dashboard"))
     |> assign(:companies, Companies.list_companies(scope))
     |> assign(:company, nil)
     |> stream_configure(:activities, dom_id: &"dashboard-activity-#{&1.id}")
     |> stream(:activities, [])}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, select_company(socket, company_from_params(socket.assigns, params))}
  end

  # Only the owner's own companies are offered; any other id is ignored.
  @impl true
  def handle_event("switch_company", %{"switcher" => %{"company" => id}}, socket)
      when is_binary(id) do
    case Enum.find(socket.assigns.companies, &(Integer.to_string(&1.id) == id)) do
      %Company{id: company_id} ->
        {:noreply, push_patch(socket, to: ~p"/dashboard?company=#{company_id}")}

      nil ->
        {:noreply, socket}
    end
  end

  def handle_event(_event, _params, socket), do: {:noreply, socket}

  @impl true
  def handle_info({:plan_updated, %{company_id: id}}, %{assigns: %{company: %{id: id}}} = socket) do
    {:noreply, socket |> load_plan() |> load_activity()}
  end

  def handle_info({:site_updated, %{company_id: id}}, %{assigns: %{company: %{id: id}}} = socket) do
    {:noreply, socket |> load_site() |> load_activity()}
  end

  # Sent for the previous company before the switch unsubscribed from it.
  def handle_info({event, %{company_id: _other}}, socket)
      when event in [:plan_updated, :site_updated] do
    {:noreply, socket}
  end

  defp company_from_params(%{current_scope: scope}, %{"company" => id}) do
    Companies.get_company!(scope, parse_id!(id))
  end

  defp company_from_params(%{companies: companies}, _params), do: List.first(companies)

  # A malformed id names no company the owner can see: a 404, like a foreign one.
  defp parse_id!(id) do
    case Ecto.Type.cast(:id, id) do
      {:ok, int} when int > 0 -> int
      _invalid -> raise Ecto.NoResultsError, queryable: Company
    end
  end

  defp select_company(socket, company) do
    socket
    |> move_subscriptions(socket.assigns.company, company)
    |> assign(:company, company)
    |> assign(:switcher_form, switcher_form(company))
    |> load_plan()
    |> load_site()
    |> load_activity()
  end

  defp move_subscriptions(socket, %Company{id: id}, %Company{id: id}), do: socket

  defp move_subscriptions(socket, old, new) do
    if connected?(socket) do
      scope = socket.assigns.current_scope

      if old do
        :ok = Plans.unsubscribe(scope, old)
        :ok = Sites.unsubscribe(scope, old)
      end

      if new do
        :ok = Plans.subscribe(scope, new)
        :ok = Sites.subscribe(scope, new)
      end
    end

    socket
  end

  defp switcher_form(nil), do: nil

  defp switcher_form(%Company{id: id}),
    do: to_form(%{"company" => Integer.to_string(id)}, as: :switcher)

  defp load_plan(%{assigns: %{company: nil}} = socket), do: assign(socket, :plan, nil)

  defp load_plan(%{assigns: %{current_scope: scope, company: company}} = socket) do
    assign(socket, :plan, Plans.current_plan(scope, company))
  end

  defp load_site(%{assigns: %{company: nil}} = socket) do
    socket
    |> assign(:site_state, :none)
    |> assign(:public_url, nil)
    |> assign(:unpublished_changes?, false)
  end

  defp load_site(%{assigns: %{current_scope: scope, company: company}} = socket) do
    site = Sites.get_site(scope, company)

    socket
    |> assign(:site_state, site_state(site))
    |> assign(:public_url, public_url(site))
    |> assign(:unpublished_changes?, Sites.unpublished_changes?(site))
  end

  defp load_activity(%{assigns: %{company: nil}} = socket),
    do: stream(socket, :activities, [], reset: true)

  defp load_activity(%{assigns: %{current_scope: scope, company: company}} = socket) do
    entries = Activity.list_for_company(scope, company, limit: @activity_limit)
    stream(socket, :activities, entries, reset: true)
  end

  # A published site stays "published" while a new draft is generated.
  defp site_state(site) do
    cond do
      is_nil(site) -> :none
      Sites.published?(site) -> :published
      Sites.generation_in_progress?(site) -> :generating
      is_nil(site.current_version_id) and Sites.generation_failed?(site) -> :failed
      is_nil(site.current_version_id) -> :none
      true -> :draft
    end
  end

  defp public_url(site) do
    if Sites.published?(site) and is_binary(site.slug), do: SiteDomain.public_url(site.slug)
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

  # A stalled plan shows as failed, so the owner goes and tries again.
  defp plan_state(plan) do
    cond do
      plan.status == :ready -> :ready
      plan.status == :failed or Plans.stalled?(plan) -> :failed
      true -> :in_progress
    end
  end

  attr :id, :string, required: true
  attr :icon, :string, required: true
  attr :title, :string, required: true
  attr :class, :string, default: nil
  slot :inner_block, required: true
  slot :footer

  defp card(assigns) do
    ~H"""
    <section
      id={@id}
      class={[
        "group flex flex-col rounded-2xl border border-zinc-200 bg-white p-6 shadow-sm transition hover:border-zinc-300 hover:shadow-md",
        @class
      ]}
    >
      <header class="mb-4 flex items-center gap-3">
        <span class="flex size-9 items-center justify-center rounded-xl bg-zinc-100 text-zinc-600 transition group-hover:bg-zinc-900 group-hover:text-white">
          <.icon name={@icon} class="size-5" />
        </span>
        <h2 class="text-base font-semibold text-zinc-900">{@title}</h2>
      </header>
      <div class="flex-1 space-y-4">{render_slot(@inner_block)}</div>
      <footer :if={@footer != []} class="mt-6 border-t border-zinc-100 pt-4">
        {render_slot(@footer)}
      </footer>
    </section>
    """
  end

  attr :id, :string, required: true
  attr :navigate, :string, required: true
  attr :icon, :string, default: "hero-arrow-right"
  slot :inner_block, required: true

  defp card_link(assigns) do
    ~H"""
    <.link
      id={@id}
      navigate={@navigate}
      class="group/link inline-flex items-center gap-1.5 text-sm font-semibold text-zinc-900 underline-offset-4 transition hover:underline"
    >
      {render_slot(@inner_block)}
      <.icon name={@icon} class="size-4 transition group-hover/link:translate-x-0.5" />
    </.link>
    """
  end

  attr :plan, Firmos.Plans.Plan, required: true

  defp plan_status(assigns) do
    ~H"""
    <div id="plan-status" data-status={@plan.status}>
      <%= case plan_state(@plan) do %>
        <% :in_progress -> %>
          <p id="plan-progress" role="status" class="flex items-center gap-2 text-sm text-zinc-600">
            <span class="relative flex size-2.5">
              <span class="absolute inline-flex size-full animate-ping rounded-full bg-amber-400 opacity-75">
              </span>
              <span class="relative inline-flex size-2.5 rounded-full bg-amber-500"></span>
            </span>
            {gettext("AI is preparing your business plan...")}
          </p>
        <% :ready -> %>
          <p id="plan-ready" class="flex items-center gap-2 text-sm text-zinc-600">
            <.icon name="hero-check-circle" class="size-5 text-emerald-600" />
            {gettext("Your business plan is ready.")}
          </p>
        <% :failed -> %>
          <p id="plan-failed" class="flex items-center gap-2 text-sm text-red-700">
            <.icon name="hero-exclamation-triangle" class="size-5" />
            {gettext("We couldn't generate your business plan. Open it to try again.")}
          </p>
      <% end %>
    </div>
    """
  end

  attr :plan, Firmos.Plans.Plan, required: true

  defp plan_summary(assigns) do
    ~H"""
    <dl class="space-y-3 text-sm">
      <div class="space-y-1">
        <dt class="text-xs font-medium uppercase tracking-wide text-zinc-500">{gettext("Offer")}</dt>
        <dd id="dashboard-plan-offer" class="line-clamp-3 text-zinc-700">
          {@plan.content.offer}
        </dd>
      </div>
      <div class="space-y-1">
        <dt class="text-xs font-medium uppercase tracking-wide text-zinc-500">
          {gettext("Target customer")}
        </dt>
        <dd id="dashboard-plan-target-customer" class="line-clamp-3 text-zinc-700">
          {@plan.content.target_customer}
        </dd>
      </div>
    </dl>
    <p
      id="dashboard-plan-rating"
      data-rating={@plan.rating || "none"}
      class="flex items-center gap-2 text-sm text-zinc-500"
    >
      <%= case @plan.rating do %>
        <% :up -> %>
          <.icon name="hero-hand-thumb-up" class="size-4 text-emerald-600" />
          {gettext("You rated this plan as helpful.")}
        <% :down -> %>
          <.icon name="hero-hand-thumb-down" class="size-4 text-red-600" />
          {gettext("You rated this plan as not helpful.")}
        <% nil -> %>
          <.icon name="hero-hand-thumb-up" class="size-4" />
          {gettext("Not rated yet. Tell us if the plan helps.")}
      <% end %>
    </p>
    """
  end

  attr :state, :atom, required: true
  attr :public_url, :string, default: nil
  attr :unpublished_changes?, :boolean, required: true

  defp site_status(assigns) do
    ~H"""
    <div id="dashboard-site-status" data-status={@state} class="space-y-3 text-sm">
      <%= case @state do %>
        <% :none -> %>
          <p class="text-zinc-600">
            {gettext("No website yet. Create one from your business plan.")}
          </p>
        <% :generating -> %>
          <p role="status" class="flex items-center gap-2 text-zinc-600">
            <span class="relative flex size-2.5">
              <span class="absolute inline-flex size-full animate-ping rounded-full bg-amber-400 opacity-75">
              </span>
              <span class="relative inline-flex size-2.5 rounded-full bg-amber-500"></span>
            </span>
            {gettext("AI is writing your website...")}
          </p>
        <% :failed -> %>
          <p class="flex items-center gap-2 text-red-700">
            <.icon name="hero-exclamation-triangle" class="size-5" />
            {gettext("We couldn't generate your website. Open it to try again.")}
          </p>
        <% :draft -> %>
          <p class="flex items-center gap-2 text-zinc-600">
            <span class="size-2 rounded-full bg-zinc-400"></span>
            {gettext("Draft. Only you can see it until you publish.")}
          </p>
        <% :published -> %>
          <p class="flex items-center gap-2 font-medium text-emerald-700">
            <span class="size-2 rounded-full bg-emerald-500"></span>
            {gettext("Published")}
          </p>
          <a
            :if={@public_url}
            id="dashboard-site-link"
            href={@public_url}
            target="_blank"
            rel="noopener"
            class="inline-flex max-w-full items-center gap-1 break-all font-semibold text-zinc-900 underline-offset-4 transition hover:underline"
          >
            {@public_url}
            <.icon name="hero-arrow-top-right-on-square" class="size-4 shrink-0" />
          </a>
          <p
            :if={@unpublished_changes?}
            id="dashboard-site-unpublished"
            class="flex items-center gap-1.5 font-medium text-amber-700"
          >
            <span class="size-2 rounded-full bg-amber-500"></span>
            {gettext("The draft has changes customers don't see yet.")}
          </p>
      <% end %>
    </div>
    """
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <section id="dashboard" class="mx-auto max-w-5xl space-y-8">
        <header class="flex flex-wrap items-end justify-between gap-4">
          <div class="space-y-1">
            <p class="text-sm font-medium text-zinc-500">{gettext("Dashboard")}</p>
            <h1 id="dashboard-greeting" class="text-2xl font-semibold tracking-tight text-zinc-900">
              {gettext("Welcome, %{email}", email: @current_scope.user.email)}
            </h1>
          </div>
          <div :if={@company} class="flex flex-wrap items-end gap-3">
            <.form
              for={@switcher_form}
              id="company-switcher"
              phx-change="switch_company"
              class="min-w-48"
            >
              <.input
                type="select"
                field={@switcher_form[:company]}
                label={gettext("Company")}
                options={Enum.map(@companies, &{&1.name, &1.id})}
                class="w-full rounded-lg border border-zinc-200 bg-white px-3 py-2 text-sm font-medium text-zinc-900 shadow-sm transition hover:border-zinc-300 focus:border-zinc-400 focus:outline-none focus:ring-2 focus:ring-zinc-200"
              />
            </.form>
            <.link
              id="dashboard-add-company"
              navigate={~p"/"}
              class="mb-2 inline-flex items-center gap-1.5 rounded-lg border border-zinc-200 px-3 py-2 text-sm font-medium text-zinc-700 transition hover:border-zinc-300 hover:bg-zinc-50"
            >
              <.icon name="hero-plus" class="size-4" />
              {gettext("Add another company")}
            </.link>
          </div>
        </header>

        <%= if @company do %>
          <article
            id="current-company"
            class="space-y-3 rounded-2xl border border-zinc-200 bg-white p-6 shadow-sm"
          >
            <div class="flex flex-wrap items-start justify-between gap-4">
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

          <div class="grid gap-6 lg:grid-cols-2">
            <.card id="dashboard-plan" icon="hero-document-text" title={gettext("Business plan")}>
              <.plan_status :if={@plan} plan={@plan} />
              <p :if={is_nil(@plan)} class="text-sm text-zinc-600">
                {gettext("No business plan yet.")}
              </p>
              <.plan_summary :if={@plan && plan_state(@plan) == :ready} plan={@plan} />
              <:footer>
                <.card_link id="company-plan-link" navigate={~p"/companies/#{@company.id}/plan"}>
                  {gettext("Open business plan")}
                </.card_link>
              </:footer>
            </.card>

            <.card id="dashboard-site" icon="hero-globe-alt" title={gettext("Website")}>
              <.site_status
                state={@site_state}
                public_url={@public_url}
                unpublished_changes?={@unpublished_changes?}
              />
              <:footer>
                <.card_link id="company-site-link" navigate={~p"/companies/#{@company.id}/site"}>
                  {gettext("Manage website")}
                </.card_link>
              </:footer>
            </.card>

            <.card
              id="dashboard-activity"
              icon="hero-clock"
              title={gettext("Recent activity")}
              class="lg:col-span-2"
            >
              <div id="dashboard-activity-entries" phx-update="stream" class="space-y-3">
                <p id="dashboard-activity-empty" class="hidden text-sm text-zinc-500 only:block">
                  {gettext("No activity yet. Changes to your company will show up here.")}
                </p>
                <.activity_entry
                  :for={{dom_id, entry} <- @streams.activities}
                  id={dom_id}
                  entry={entry}
                />
              </div>
              <:footer>
                <.card_link
                  id="company-activity-link"
                  navigate={~p"/companies/#{@company.id}/activity"}
                >
                  {gettext("See the full activity log")}
                </.card_link>
              </:footer>
            </.card>
          </div>
        <% else %>
          <div
            id="dashboard-empty"
            class="flex flex-col items-center gap-4 rounded-2xl border border-dashed border-zinc-300 px-6 py-16 text-center transition-colors hover:border-zinc-400"
          >
            <span class="flex size-12 items-center justify-center rounded-full bg-zinc-100">
              <.icon name="hero-light-bulb" class="size-6 text-zinc-500" />
            </span>
            <div class="space-y-1">
              <h2 class="text-base font-semibold text-zinc-900">
                {gettext("Start with your business idea")}
              </h2>
              <p class="max-w-sm text-sm text-zinc-500">
                {gettext(
                  "Describe what you want to do, and AI will prepare a business plan and a website for your company."
                )}
              </p>
            </div>
            <.link
              id="dashboard-new-idea"
              navigate={~p"/"}
              class="inline-flex items-center gap-1.5 rounded-lg bg-zinc-900 px-4 py-2 text-sm font-semibold text-white shadow-sm transition hover:bg-zinc-700 active:scale-[0.98]"
            >
              <.icon name="hero-sparkles" class="size-4" />
              {gettext("Describe your idea")}
            </.link>
          </div>
        <% end %>
      </section>
    </Layouts.app>
    """
  end
end
