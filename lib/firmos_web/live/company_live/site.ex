defmodule FirmosWeb.CompanyLive.Site do
  @moduledoc """
  The company's website section: "create website" (enabled once the current
  business plan is ready), the generation's progress or failure, the
  current draft with links to its preview and editor, the site's address
  (slug) and publishing.

  The company is loaded through the owner's scope, so another owner's
  company id is a 404. Every action works on the company and site held in
  the socket, never on an id sent by the client, and `Firmos.Sites`
  re-checks ownership (and the ready plan, slug and content). The page follows the generation and the
  plan live through `Firmos.Sites.subscribe/2` and `Firmos.Plans.subscribe/2`.
  """
  use FirmosWeb, :live_view

  alias Firmos.Companies
  alias Firmos.Plans
  alias Firmos.Sites
  alias Firmos.Sites.Version
  alias FirmosWeb.SiteDomain

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    scope = socket.assigns.current_scope
    company = Companies.get_company!(scope, id)

    if connected?(socket) do
      :ok = Sites.subscribe(scope, company)
      :ok = Plans.subscribe(scope, company)
    end

    {:ok,
     socket
     |> assign(:page_title, gettext("Website"))
     |> assign(:company, company)
     |> load()}
  end

  @impl true
  def handle_event("generate", _params, socket) do
    %{current_scope: scope, company: company} = socket.assigns

    socket =
      case Sites.request_generation(scope, company) do
        {:ok, _site} ->
          socket

        {:error, :no_ready_plan} ->
          put_flash(socket, :error, gettext("Generate your business plan first."))

        {:error, :generation_in_progress} ->
          put_flash(socket, :error, gettext("A website is already being generated."))

        {:error, _reason} ->
          put_flash(socket, :error, gettext("Could not start generating your website."))
      end

    {:noreply, load(socket)}
  end

  def handle_event("validate_slug", %{"site" => params}, %{assigns: %{site: %{} = site}} = socket) do
    form =
      site
      |> Sites.change_slug(params)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, :slug_form, form)}
  end

  def handle_event(
        "save_slug",
        %{"site" => %{"slug" => slug}},
        %{assigns: %{site: %{} = site}} = socket
      )
      when is_binary(slug) do
    case Sites.set_slug(socket.assigns.current_scope, site, slug) do
      {:ok, _site} ->
        {:noreply, socket |> put_flash(:info, gettext("Website address saved.")) |> load()}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :slug_form, to_form(changeset))}

      {:error, _reason} ->
        {:noreply, socket |> put_flash(:error, gettext("Could not save the address.")) |> load()}
    end
  end

  def handle_event("publish", _params, %{assigns: %{site: %{} = site}} = socket) do
    socket =
      case Sites.publish(socket.assigns.current_scope, site) do
        {:ok, _site} ->
          put_flash(socket, :info, gettext("Your website is published."))

        {:error, :slug_required} ->
          put_flash(socket, :error, gettext("Choose your website's address before publishing."))

        {:error, :no_content} ->
          put_flash(socket, :error, gettext("There is no website draft to publish yet."))

        {:error, _reason} ->
          put_flash(socket, :error, gettext("Could not publish your website."))
      end

    {:noreply, load(socket)}
  end

  # Forged or stale events change nothing.
  def handle_event(_event, _params, socket), do: {:noreply, socket}

  @impl true
  def handle_info(
        {event, %{company_id: company_id}},
        %{assigns: %{company: %{id: company_id}}} = socket
      )
      when event in [:site_updated, :plan_updated] do
    {:noreply, load(socket)}
  end

  defp load(socket) do
    %{current_scope: scope, company: company} = socket.assigns

    site = Sites.get_site(scope, company)

    socket
    |> assign(:site, site)
    |> assign(:slug_form, site && site |> Sites.change_slug() |> to_form())
    |> assign(:public_url, public_url(site))
    |> assign(:published?, Sites.published?(site))
    |> assign(:unpublished_changes?, Sites.unpublished_changes?(site))
    |> assign(:plan_ready?, match?({:ok, _plan}, Plans.ready_plan(scope, company)))
    |> assign(:draft, draft(site))
    |> assign(:in_progress?, Sites.generation_in_progress?(site))
    |> assign(:failed?, Sites.generation_failed?(site))
  end

  defp draft(%{current_version: %Version{} = version}), do: version
  defp draft(_no_site_or_no_version), do: nil

  defp public_url(%{slug: slug}) when is_binary(slug), do: SiteDomain.public_url(slug)
  defp public_url(_no_site_or_no_slug), do: nil

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <section id="company-site" class="mx-auto max-w-3xl space-y-8">
        <header class="space-y-4">
          <.link
            id="company-site-back"
            navigate={~p"/dashboard"}
            class="inline-flex items-center gap-1 text-sm font-medium text-zinc-500 transition hover:text-zinc-900"
          >
            <.icon name="hero-arrow-left" class="size-4" />
            {gettext("Dashboard")}
          </.link>
          <div class="flex flex-wrap items-end justify-between gap-4">
            <div class="space-y-1">
              <h1 class="text-2xl font-semibold tracking-tight text-zinc-900">
                {gettext("Website")}
              </h1>
              <p class="text-sm text-zinc-500">
                <span>{@company.name}</span>
                <span :if={@draft}>
                  · {gettext("draft version %{version}", version: @draft.number)}
                </span>
              </p>
            </div>
            <button
              :if={not @in_progress?}
              id="site-create"
              type="button"
              phx-click="generate"
              disabled={not @plan_ready?}
              phx-disable-with={gettext("Starting...")}
              data-confirm={@draft && gettext("Generate a new draft? The current one will be kept.")}
              class="inline-flex items-center gap-1.5 rounded-lg bg-zinc-900 px-4 py-2 text-sm font-semibold text-white shadow-sm transition hover:bg-zinc-700 active:scale-[0.98] disabled:cursor-not-allowed disabled:bg-zinc-300 disabled:active:scale-100"
            >
              <.icon name="hero-sparkles" class="size-4" />
              {if @draft, do: gettext("Regenerate website"), else: gettext("Create website")}
            </button>
          </div>
        </header>

        <div
          :if={not @plan_ready?}
          id="site-needs-plan"
          class="flex items-start gap-3 rounded-2xl border border-amber-200 bg-amber-50 px-5 py-4 text-sm text-amber-900"
        >
          <.icon name="hero-light-bulb" class="mt-0.5 size-5 shrink-0" />
          <p>
            {gettext("Your website is written from your business plan. Generate the plan first.")}
            <.link
              id="site-plan-link"
              navigate={~p"/companies/#{@company.id}/plan"}
              class="font-semibold underline underline-offset-4 transition hover:text-amber-700"
            >
              {gettext("Go to the business plan")}
            </.link>
          </p>
        </div>

        <div
          :if={@in_progress?}
          id="site-progress"
          role="status"
          class="flex flex-col items-center gap-4 rounded-2xl border border-zinc-200 bg-white px-6 py-16 text-center shadow-sm"
        >
          <span class="relative flex size-12 items-center justify-center rounded-full bg-zinc-900 text-white">
            <span class="absolute inset-0 animate-ping rounded-full bg-zinc-900 opacity-20"></span>
            <.icon name="hero-sparkles" class="size-6" />
          </span>
          <div class="space-y-1">
            <h2 class="text-base font-semibold text-zinc-900">
              {gettext("Writing your website...")}
            </h2>
            <p class="max-w-sm text-sm text-zinc-500">
              {gettext(
                "This usually takes a minute or two. The page updates by itself when it's ready."
              )}
            </p>
          </div>
        </div>

        <div
          :if={@failed?}
          id="site-failed"
          class="flex flex-col items-center gap-4 rounded-2xl border border-red-200 bg-red-50 px-6 py-12 text-center"
        >
          <span class="flex size-12 items-center justify-center rounded-full bg-white text-red-600 shadow-sm">
            <.icon name="hero-exclamation-triangle" class="size-6" />
          </span>
          <div class="space-y-1">
            <h2 class="text-base font-semibold text-red-900">
              {gettext("We couldn't generate your website")}
            </h2>
            <p class="max-w-sm text-sm text-red-700">
              {gettext(
                "The AI service didn't deliver a usable website. Nothing was saved. Please try again."
              )}
            </p>
          </div>
          <button
            id="site-retry"
            type="button"
            phx-click="generate"
            disabled={not @plan_ready?}
            phx-disable-with={gettext("Starting...")}
            class="inline-flex items-center gap-1.5 rounded-lg bg-zinc-900 px-4 py-2 text-sm font-semibold text-white shadow-sm transition hover:bg-zinc-700 active:scale-[0.98] disabled:cursor-not-allowed disabled:bg-zinc-300"
          >
            <.icon name="hero-arrow-path" class="size-4" />
            {gettext("Try again")}
          </button>
        </div>

        <article
          :if={@draft}
          id="site-draft"
          class="group overflow-hidden rounded-2xl border border-zinc-200 bg-white shadow-sm transition hover:border-zinc-300 hover:shadow-md"
        >
          <div class="space-y-3 bg-zinc-950 px-6 py-10 text-white">
            <p class="text-xs font-semibold uppercase tracking-widest text-amber-300">
              {gettext("Draft")}
            </p>
            <h2 id="site-draft-headline" class="text-2xl font-semibold tracking-tight">
              {@draft.content.hero.headline}
            </h2>
            <p class="text-sm leading-relaxed text-zinc-300">{@draft.content.hero.subheadline}</p>
          </div>
          <div class="flex flex-wrap items-center justify-between gap-3 px-6 py-4">
            <p class="text-sm text-zinc-500">
              {gettext("Hero, offer, pricing and contact sections are ready.")}
            </p>
            <div class="flex flex-wrap items-center gap-2">
              <.link
                id="site-edit-link"
                navigate={~p"/companies/#{@company.id}/site/edit"}
                class="inline-flex items-center gap-1.5 rounded-lg border border-zinc-200 px-3 py-1.5 text-sm font-medium text-zinc-700 transition hover:border-zinc-300 hover:bg-zinc-50"
              >
                <.icon name="hero-pencil-square" class="size-4" />
                {gettext("Edit")}
              </.link>
              <.link
                id="site-preview-link"
                href={~p"/companies/#{@company.id}/site/preview"}
                target="_blank"
                rel="noopener"
                class="inline-flex items-center gap-1.5 rounded-lg border border-zinc-200 px-3 py-1.5 text-sm font-medium text-zinc-700 transition hover:border-zinc-300 hover:bg-zinc-50"
              >
                <.icon name="hero-eye" class="size-4" />
                {gettext("Preview")}
              </.link>
            </div>
          </div>
        </article>

        <section
          :if={@draft}
          id="site-publishing"
          class="space-y-6 rounded-2xl border border-zinc-200 bg-white p-6 shadow-sm"
        >
          <div class="flex flex-wrap items-start justify-between gap-4">
            <div class="space-y-1">
              <h2 class="text-base font-semibold text-zinc-900">{gettext("Publishing")}</h2>
              <p id="site-publish-status" class="text-sm text-zinc-500">
                <%= cond do %>
                  <% @unpublished_changes? -> %>
                    <span
                      id="site-unpublished-changes"
                      class="inline-flex items-center gap-1.5 font-medium text-amber-700"
                    >
                      <span class="size-2 rounded-full bg-amber-500"></span>
                      {gettext("The draft has changes customers don't see yet.")}
                    </span>
                  <% @published? -> %>
                    <span class="inline-flex items-center gap-1.5 font-medium text-emerald-700">
                      <span class="size-2 rounded-full bg-emerald-500"></span>
                      {gettext("Published and up to date.")}
                    </span>
                  <% true -> %>
                    {gettext("Not published yet. Only you can see the draft.")}
                <% end %>
              </p>
              <a
                :if={@published? and @public_url}
                id="site-public-url"
                href={@public_url}
                target="_blank"
                rel="noopener"
                class="inline-flex items-center gap-1 text-sm font-semibold text-zinc-900 underline-offset-4 transition hover:underline"
              >
                {@public_url}
                <.icon name="hero-arrow-top-right-on-square" class="size-4" />
              </a>
            </div>
            <button
              :if={not @published? or @unpublished_changes?}
              id="site-publish"
              type="button"
              phx-click="publish"
              phx-disable-with={gettext("Publishing...")}
              class="inline-flex items-center gap-1.5 rounded-lg bg-emerald-600 px-4 py-2 text-sm font-semibold text-white shadow-sm transition hover:bg-emerald-500 active:scale-[0.98]"
            >
              <.icon name="hero-rocket-launch" class="size-4" />
              {if @published?, do: gettext("Publish changes"), else: gettext("Publish")}
            </button>
          </div>

          <.form
            for={@slug_form}
            id="site-slug-form"
            phx-change="validate_slug"
            phx-submit="save_slug"
            class="space-y-2 border-t border-zinc-100 pt-6"
          >
            <div class="flex flex-wrap items-end gap-3">
              <div class="min-w-0 flex-1">
                <.input
                  field={@slug_form[:slug]}
                  type="text"
                  label={gettext("Website address")}
                  placeholder="piekarnia"
                  autocomplete="off"
                  phx-debounce="300"
                />
              </div>
              <span class="pb-4 text-sm text-zinc-500">.{SiteDomain.base_domain()}</span>
              <div class="pb-2">
                <button
                  id="site-slug-save"
                  type="submit"
                  phx-disable-with={gettext("Saving...")}
                  class="inline-flex items-center gap-1.5 rounded-lg bg-zinc-900 px-4 py-2 text-sm font-semibold text-white shadow-sm transition hover:bg-zinc-700 active:scale-[0.98]"
                >
                  {gettext("Save address")}
                </button>
              </div>
            </div>
            <p class="text-xs text-zinc-500">
              {gettext(
                "Lowercase letters, digits and hyphens. Changing the address of a published website moves it: the old address stops working."
              )}
            </p>
          </.form>
        </section>

        <div
          :if={@plan_ready? and is_nil(@draft) and not @in_progress? and not @failed?}
          id="site-empty"
          class="flex flex-col items-center gap-3 rounded-2xl border border-dashed border-zinc-300 px-6 py-16 text-center"
        >
          <span class="flex size-12 items-center justify-center rounded-full bg-zinc-100">
            <.icon name="hero-globe-alt" class="size-6 text-zinc-500" />
          </span>
          <p class="max-w-sm text-sm text-zinc-500">
            {gettext(
              "No website yet. Create one and AI will write a landing page from your business plan."
            )}
          </p>
        </div>
      </section>
    </Layouts.app>
    """
  end
end
