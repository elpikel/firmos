defmodule FirmosWeb.CompanyLive.Plan do
  @moduledoc """
  The company's AI business plan: the six sections of the current version (or
  an older one via `?version=`), the owner's thumbs up / down, "try again"
  for a failed generation and "regenerate" for a new version.

  The company is loaded through the owner's scope, so another owner's company
  id is a 404. Every action works on the plan held in the socket, never on an
  id sent by the client. The page follows generation live through
  `Firmos.Plans.subscribe/2`. AI text is rendered escaped, like any other
  untrusted input.
  """
  use FirmosWeb, :live_view

  alias Firmos.Companies
  alias Firmos.Plans
  alias Firmos.Plans.Plan

  @ratings %{"up" => :up, "down" => :down}

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    scope = socket.assigns.current_scope
    company = Companies.get_company!(scope, id)

    if connected?(socket) do
      :ok = Plans.subscribe(scope, company)
    end

    {:ok,
     socket
     |> assign(:page_title, gettext("Business plan"))
     |> assign(:company, company)}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply,
     socket
     |> assign(:requested_version, params["version"])
     |> load_plans()}
  end

  @impl true
  def handle_event(event, _params, %{assigns: %{plan: nil}} = socket)
      when event in ["rate", "retry"] do
    {:noreply, socket}
  end

  def handle_event("rate", %{"rating" => rating}, socket) when is_map_key(@ratings, rating) do
    %{current_scope: scope, plan: plan} = socket.assigns

    case Plans.rate_plan(scope, plan, Map.fetch!(@ratings, rating)) do
      {:ok, _plan} ->
        {:noreply, load_plans(socket)}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, gettext("Could not save your rating."))}
    end
  end

  def handle_event("retry", _params, socket) do
    %{current_scope: scope, plan: plan} = socket.assigns

    case Plans.retry_plan(scope, plan) do
      {:ok, _plan} ->
        {:noreply, load_plans(socket)}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, gettext("This plan can't be retried right now."))}
    end
  end

  def handle_event("regenerate", _params, socket) do
    %{current_scope: scope, company: company} = socket.assigns

    case Plans.regenerate_plan(scope, company) do
      {:ok, _plan} ->
        {:noreply, push_patch(socket, to: ~p"/companies/#{company.id}/plan")}

      {:error, :generation_in_progress} ->
        {:noreply, put_flash(socket, :error, gettext("A plan is already being generated."))}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, gettext("Could not start a new plan."))}
    end
  end

  # Forged or stale events (unknown rating, unknown event) change nothing.
  def handle_event(_event, _params, socket), do: {:noreply, socket}

  @impl true
  def handle_info(
        {:plan_updated, %{company_id: company_id}},
        %{assigns: %{company: %{id: company_id}}} = socket
      ) do
    {:noreply, load_plans(socket)}
  end

  defp load_plans(socket) do
    %{current_scope: scope, company: company, requested_version: requested} = socket.assigns
    plans = Plans.list_plans(scope, company)
    latest = List.first(plans)

    socket
    |> assign(:plan, select_plan(plans, requested))
    |> assign(:latest, latest)
    |> stream(:versions, plans, reset: true)
  end

  defp select_plan(plans, nil), do: List.first(plans)

  defp select_plan(plans, version) do
    Enum.find(plans, &(Integer.to_string(&1.version) == version)) ||
      raise Ecto.NoResultsError, queryable: Plan
  end

  # A stalled plan counts as failed: the owner can try again or regenerate.
  defp in_progress?(%Plan{status: status} = plan),
    do: status in [:pending, :generating] and not Plans.stalled?(plan)

  defp in_progress?(nil), do: false

  defp failed?(%Plan{status: :failed}), do: true
  defp failed?(%Plan{} = plan), do: Plans.stalled?(plan)
  defp failed?(nil), do: false

  # Only the current version can be retried; older ones are history.
  defp latest?(%Plan{id: id}, %Plan{id: id}), do: true
  defp latest?(_plan, _latest), do: false

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <section id="company-plan" class="mx-auto max-w-3xl space-y-8">
        <header class="space-y-4">
          <.link
            id="company-plan-back"
            navigate={~p"/dashboard"}
            class="inline-flex items-center gap-1 text-sm font-medium text-zinc-500 transition hover:text-zinc-900"
          >
            <.icon name="hero-arrow-left" class="size-4" />
            {gettext("Dashboard")}
          </.link>
          <div class="flex flex-wrap items-end justify-between gap-4">
            <div class="space-y-1">
              <h1 class="text-2xl font-semibold tracking-tight text-zinc-900">
                {gettext("Business plan")}
              </h1>
              <p class="text-sm text-zinc-500">
                <span>{@company.name}</span>
                <span :if={@plan}>
                  · {gettext("version %{version}", version: @plan.version)}
                </span>
              </p>
            </div>
            <button
              :if={not in_progress?(@latest)}
              id="plan-regenerate"
              type="button"
              phx-click="regenerate"
              phx-disable-with={gettext("Starting...")}
              data-confirm={@latest && gettext("Generate a new version? This one will be kept.")}
              class="inline-flex items-center gap-1.5 rounded-lg border border-zinc-200 bg-white px-3 py-1.5 text-sm font-medium text-zinc-700 shadow-sm transition hover:border-zinc-300 hover:bg-zinc-50 active:scale-[0.98]"
            >
              <.icon name="hero-arrow-path" class="size-4" />
              {if @latest, do: gettext("Regenerate"), else: gettext("Generate plan")}
            </button>
          </div>
        </header>

        <div
          :if={is_nil(@plan)}
          id="plan-empty"
          class="flex flex-col items-center gap-3 rounded-2xl border border-dashed border-zinc-300 px-6 py-16 text-center"
        >
          <span class="flex size-12 items-center justify-center rounded-full bg-zinc-100">
            <.icon name="hero-document-text" class="size-6 text-zinc-500" />
          </span>
          <p class="max-w-sm text-sm text-zinc-500">
            {gettext(
              "No business plan yet. Generate one to see your offer, customers and first steps."
            )}
          </p>
        </div>

        <.progress :if={in_progress?(@plan)} />

        <div
          :if={failed?(@plan)}
          id="plan-failed"
          class="flex flex-col items-center gap-4 rounded-2xl border border-red-200 bg-red-50 px-6 py-12 text-center"
        >
          <span class="flex size-12 items-center justify-center rounded-full bg-white text-red-600 shadow-sm">
            <.icon name="hero-exclamation-triangle" class="size-6" />
          </span>
          <div class="space-y-1">
            <h2 class="text-base font-semibold text-red-900">
              {gettext("We couldn't generate your plan")}
            </h2>
            <p class="max-w-sm text-sm text-red-700">
              {gettext("The AI service didn't deliver a usable plan. Please try again.")}
            </p>
          </div>
          <button
            :if={latest?(@plan, @latest)}
            id="plan-retry"
            type="button"
            phx-click="retry"
            phx-disable-with={gettext("Starting...")}
            class="inline-flex items-center gap-1.5 rounded-lg bg-zinc-900 px-4 py-2 text-sm font-semibold text-white shadow-sm transition hover:bg-zinc-700 active:scale-[0.98]"
          >
            <.icon name="hero-arrow-path" class="size-4" />
            {gettext("Try again")}
          </button>
        </div>

        <div :if={@plan && @plan.status == :ready} id="plan-content" class="space-y-4">
          <.plan_section id="plan-offer" icon="hero-gift" title={gettext("Offer")}>
            <p class="whitespace-pre-line">{@plan.content.offer}</p>
          </.plan_section>

          <.plan_section
            id="plan-target-customer"
            icon="hero-user-group"
            title={gettext("Target customer")}
          >
            <p class="whitespace-pre-line">{@plan.content.target_customer}</p>
          </.plan_section>

          <.plan_section id="plan-competitors" icon="hero-scale" title={gettext("Competitors")}>
            <ul class="list-disc space-y-1 pl-5">
              <li :for={competitor <- @plan.content.competitors}>{competitor}</li>
            </ul>
          </.plan_section>

          <.plan_section id="plan-pricing" icon="hero-banknotes" title={gettext("Pricing")}>
            <p class="whitespace-pre-line">{@plan.content.pricing}</p>
          </.plan_section>

          <.plan_section id="plan-channels" icon="hero-megaphone" title={gettext("Channels")}>
            <ul class="list-disc space-y-1 pl-5">
              <li :for={channel <- @plan.content.channels}>{channel}</li>
            </ul>
          </.plan_section>

          <.plan_section id="plan-tasks" icon="hero-calendar-days" title={gettext("First 30 days")}>
            <ol class="divide-y divide-zinc-100">
              <li
                :for={task <- @plan.content.tasks_30_days}
                class="flex gap-4 py-2 first:pt-0 last:pb-0"
              >
                <span class="w-24 shrink-0 text-xs font-semibold uppercase tracking-wide text-zinc-500">
                  {task.when}
                </span>
                <span>{task.task}</span>
              </li>
            </ol>
          </.plan_section>

          <div
            id="plan-rating"
            class="flex flex-wrap items-center justify-between gap-3 rounded-2xl border border-zinc-200 bg-white px-5 py-4 shadow-sm"
          >
            <p class="text-sm text-zinc-600">{gettext("Is this plan useful?")}</p>
            <div class="flex gap-2">
              <.rate_button
                id="plan-rate-up"
                rating="up"
                icon="hero-hand-thumb-up"
                label={gettext("Useful")}
                active={@plan.rating == :up}
              />
              <.rate_button
                id="plan-rate-down"
                rating="down"
                icon="hero-hand-thumb-down"
                label={gettext("Not useful")}
                active={@plan.rating == :down}
              />
            </div>
          </div>
        </div>

        <nav :if={@latest} aria-labelledby="plan-versions-title" class="space-y-3">
          <h2 id="plan-versions-title" class="text-sm font-semibold text-zinc-900">
            {gettext("Versions")}
          </h2>
          <ul id="plan-versions" phx-update="stream" class="flex flex-wrap gap-2">
            <li :for={{dom_id, version} <- @streams.versions} id={dom_id}>
              <.link
                id={"plan-version-#{version.version}"}
                patch={~p"/companies/#{@company.id}/plan?version=#{version.version}"}
                aria-current={@plan && @plan.id == version.id && "page"}
                class={[
                  "inline-flex items-center gap-1.5 rounded-full border px-3 py-1 text-xs font-medium transition",
                  if(@plan && @plan.id == version.id,
                    do: "border-zinc-900 bg-zinc-900 text-white",
                    else: "border-zinc-200 text-zinc-600 hover:border-zinc-300 hover:bg-zinc-50"
                  )
                ]}
              >
                {gettext("v%{version}", version: version.version)}
                <span class="opacity-70">· {status_label(version.status)}</span>
              </.link>
            </li>
          </ul>
        </nav>
      </section>
    </Layouts.app>
    """
  end

  defp progress(assigns) do
    ~H"""
    <div
      id="plan-progress"
      role="status"
      class="flex flex-col items-center gap-4 rounded-2xl border border-zinc-200 bg-white px-6 py-16 text-center shadow-sm"
    >
      <span class="relative flex size-12 items-center justify-center rounded-full bg-zinc-900 text-white">
        <span class="absolute inset-0 animate-ping rounded-full bg-zinc-900 opacity-20"></span>
        <.icon name="hero-sparkles" class="size-6" />
      </span>
      <div class="space-y-1">
        <h2 class="text-base font-semibold text-zinc-900">
          {gettext("Preparing your business plan...")}
        </h2>
        <p class="max-w-sm text-sm text-zinc-500">
          {gettext("This usually takes a minute or two. The page updates by itself when it's ready.")}
        </p>
      </div>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :icon, :string, required: true
  attr :title, :string, required: true
  slot :inner_block, required: true

  defp plan_section(assigns) do
    ~H"""
    <section
      id={@id}
      class="group space-y-3 rounded-2xl border border-zinc-200 bg-white p-6 shadow-sm transition hover:border-zinc-300 hover:shadow-md"
    >
      <h2 class="flex items-center gap-2 text-sm font-semibold text-zinc-900">
        <span class="flex size-8 items-center justify-center rounded-full bg-zinc-100 text-zinc-600 transition group-hover:bg-zinc-900 group-hover:text-white">
          <.icon name={@icon} class="size-4" />
        </span>
        {@title}
      </h2>
      <div class="text-sm leading-relaxed text-zinc-700">{render_slot(@inner_block)}</div>
    </section>
    """
  end

  attr :id, :string, required: true
  attr :rating, :string, required: true
  attr :icon, :string, required: true
  attr :label, :string, required: true
  attr :active, :boolean, required: true

  defp rate_button(assigns) do
    ~H"""
    <button
      id={@id}
      type="button"
      phx-click="rate"
      phx-value-rating={@rating}
      aria-pressed={to_string(@active)}
      aria-label={@label}
      title={@label}
      class={[
        "inline-flex size-9 items-center justify-center rounded-full border transition active:scale-95",
        if(@active,
          do: "border-zinc-900 bg-zinc-900 text-white",
          else:
            "border-zinc-200 text-zinc-500 hover:border-zinc-300 hover:bg-zinc-50 hover:text-zinc-900"
        )
      ]}
    >
      <.icon name={@icon} class="size-4" />
    </button>
    """
  end

  defp status_label(:pending), do: gettext("queued")
  defp status_label(:generating), do: gettext("generating")
  defp status_label(:ready), do: gettext("ready")
  defp status_label(:failed), do: gettext("failed")
end
