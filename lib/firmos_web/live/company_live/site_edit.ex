defmodule FirmosWeb.CompanyLive.SiteEdit do
  @moduledoc """
  The owner's editor for the website draft: the hero, the offer and pricing
  titles and items, and the contact title and text. The contact email and
  city are not editable here: they come from the company profile.

  The company is loaded through the owner's scope (another owner's company
  id is a 404) and the site from it; without a draft the owner goes back to
  the website section. Saving goes through `Firmos.Sites.update_content/3`,
  which re-checks ownership, refuses during a generation and stores a new
  version only when something changed.

  The edit is based on the version loaded at mount (`@site`, never a client
  param): `update_content/3` refuses it as `:stale` when the site moved
  since. The page follows the company's site changes and, as soon as the
  current version moves (another tab, an undo, a new generation), shows
  `#site-edit-stale` with a reload link and disables saving.
  """
  use FirmosWeb, :live_view

  alias Firmos.Companies
  alias Firmos.Sites
  alias Firmos.Sites.Version

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    scope = socket.assigns.current_scope
    company = Companies.get_company!(scope, id)

    case Sites.get_site(scope, company) do
      %{current_version: %Version{}} = site ->
        if connected?(socket), do: :ok = Sites.subscribe(scope, company)

        {:ok,
         socket
         |> assign(:page_title, gettext("Edit website"))
         |> assign(:company, company)
         |> assign(:site, site)
         |> assign(:in_progress?, Sites.generation_in_progress?(site))
         |> assign(:stale?, false)
         |> assign(:form, site |> Sites.change_content() |> to_form())}

      _no_draft ->
        {:ok,
         socket
         |> put_flash(:error, gettext("There is no website draft to edit yet."))
         |> push_navigate(to: ~p"/companies/#{company.id}/site")}
    end
  end

  @impl true
  def handle_event("validate", %{"content" => params}, socket) when is_map(params) do
    form =
      socket.assigns.site
      |> Sites.change_content(params)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, :form, form)}
  end

  def handle_event("save", %{"content" => params}, socket) when is_map(params) do
    %{current_scope: scope, company: company, site: site} = socket.assigns

    case Sites.update_content(scope, site, params) do
      {:ok, _site} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Website saved."))
         |> push_navigate(to: ~p"/companies/#{company.id}/site")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}

      {:error, :stale} ->
        {:noreply,
         socket
         |> assign(:stale?, true)
         |> put_flash(:error, stale_message())}

      {:error, :generation_in_progress} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           gettext("A new website is being generated. Try again when it's ready.")
         )}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, gettext("Could not save your website."))}
    end
  end

  # Forged or stale events change nothing.
  def handle_event(_event, _params, socket), do: {:noreply, socket}

  @impl true
  def handle_info({:site_updated, _site}, socket) do
    %{current_scope: scope, company: company, site: site} = socket.assigns

    case Sites.get_site(scope, company) do
      %{current_version_id: current_id} = fresh ->
        {:noreply,
         socket
         |> assign(:in_progress?, Sites.generation_in_progress?(fresh))
         |> assign(:stale?, socket.assigns.stale? or current_id != site.current_version_id)}

      nil ->
        {:noreply, assign(socket, :stale?, true)}
    end
  end

  defp stale_message,
    do: gettext("The website changed in the meantime. Reload to edit the latest version.")

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <section id="company-site-edit" class="mx-auto max-w-3xl space-y-8">
        <header class="space-y-4">
          <.link
            id="site-edit-back"
            navigate={~p"/companies/#{@company.id}/site"}
            class="inline-flex items-center gap-1 text-sm font-medium text-zinc-500 transition hover:text-zinc-900"
          >
            <.icon name="hero-arrow-left" class="size-4" />
            {gettext("Website")}
          </.link>
          <div class="space-y-1">
            <h1 class="text-2xl font-semibold tracking-tight text-zinc-900">
              {gettext("Edit website")}
            </h1>
            <p class="text-sm text-zinc-500">
              {@company.name} · {gettext("draft version %{version}",
                version: @site.current_version.number
              )}
            </p>
          </div>
        </header>

        <div
          :if={@in_progress?}
          id="site-edit-in-progress"
          role="status"
          class="flex items-start gap-3 rounded-2xl border border-amber-200 bg-amber-50 px-5 py-4 text-sm text-amber-900"
        >
          <.icon name="hero-sparkles" class="mt-0.5 size-5 shrink-0" />
          <p>{gettext("A new website is being generated. You can save once it's ready.")}</p>
        </div>

        <div
          :if={@stale?}
          id="site-edit-stale"
          role="alert"
          class="flex flex-wrap items-start gap-3 rounded-2xl border border-rose-200 bg-rose-50 px-5 py-4 text-sm text-rose-900"
        >
          <.icon name="hero-exclamation-triangle" class="mt-0.5 size-5 shrink-0" />
          <p class="flex-1">{stale_message()}</p>
          <.link
            id="site-edit-reload"
            navigate={~p"/companies/#{@company.id}/site/edit"}
            class="font-semibold underline underline-offset-4 transition hover:text-rose-700"
          >
            {gettext("Reload")}
          </.link>
        </div>

        <.form
          for={@form}
          id="site-content-form"
          phx-change="validate"
          phx-submit="save"
          class="space-y-6"
        >
          <.inputs_for :let={hero} field={@form[:hero]}>
            <fieldset id="site-edit-hero" class={fieldset_class()}>
              <legend class={legend_class()}>{gettext("Hero")}</legend>
              <.input field={hero[:headline]} type="text" label={gettext("Headline")} />
              <.input field={hero[:subheadline]} type="textarea" label={gettext("Subheadline")} />
              <.input field={hero[:cta_label]} type="text" label={gettext("Button label")} />
            </fieldset>
          </.inputs_for>

          <.inputs_for :let={offer} field={@form[:offer]}>
            <fieldset id="site-edit-offer" class={fieldset_class()}>
              <legend class={legend_class()}>{gettext("Offer")}</legend>
              <.input field={offer[:title]} type="text" label={gettext("Section title")} />
              <.inputs_for :let={item} field={offer[:items]}>
                <div class={item_class()}>
                  <.input field={item[:name]} type="text" label={gettext("Name")} />
                  <.input field={item[:description]} type="textarea" label={gettext("Description")} />
                </div>
              </.inputs_for>
            </fieldset>
          </.inputs_for>

          <.inputs_for :let={pricing} field={@form[:pricing]}>
            <fieldset id="site-edit-pricing" class={fieldset_class()}>
              <legend class={legend_class()}>{gettext("Pricing")}</legend>
              <.input field={pricing[:title]} type="text" label={gettext("Section title")} />
              <.inputs_for :let={item} field={pricing[:items]}>
                <div class={item_class()}>
                  <.input field={item[:name]} type="text" label={gettext("Name")} />
                  <.input field={item[:price]} type="text" label={gettext("Price")} />
                  <.input field={item[:note]} type="text" label={gettext("Note")} />
                </div>
              </.inputs_for>
            </fieldset>
          </.inputs_for>

          <.inputs_for :let={contact} field={@form[:contact]}>
            <fieldset id="site-edit-contact" class={fieldset_class()}>
              <legend class={legend_class()}>{gettext("Contact")}</legend>
              <.input field={contact[:title]} type="text" label={gettext("Section title")} />
              <.input field={contact[:text]} type="textarea" label={gettext("Text")} />
              <p class="text-xs text-zinc-500">
                {gettext("The email and city come from your company profile.")}
                <.link
                  id="site-edit-profile-link"
                  navigate={~p"/companies/#{@company.id}/profile"}
                  class="font-semibold underline underline-offset-4 transition hover:text-zinc-900"
                >
                  {gettext("Edit the profile")}
                </.link>
              </p>
            </fieldset>
          </.inputs_for>

          <div class="flex flex-wrap items-center justify-end gap-3">
            <.link
              id="site-edit-cancel"
              navigate={~p"/companies/#{@company.id}/site"}
              class="rounded-lg px-4 py-2 text-sm font-medium text-zinc-600 transition hover:bg-zinc-100 hover:text-zinc-900"
            >
              {gettext("Cancel")}
            </.link>
            <button
              id="site-edit-save"
              type="submit"
              disabled={@in_progress? or @stale?}
              phx-disable-with={gettext("Saving...")}
              class="inline-flex items-center gap-1.5 rounded-lg bg-zinc-900 px-4 py-2 text-sm font-semibold text-white shadow-sm transition hover:bg-zinc-700 active:scale-[0.98] disabled:cursor-not-allowed disabled:bg-zinc-300"
            >
              <.icon name="hero-check" class="size-4" />
              {gettext("Save")}
            </button>
          </div>
        </.form>
      </section>
    </Layouts.app>
    """
  end

  defp fieldset_class,
    do: "space-y-2 rounded-2xl border border-zinc-200 bg-white p-6 shadow-sm"

  defp legend_class,
    do: "px-1 text-xs font-semibold uppercase tracking-widest text-zinc-500"

  defp item_class,
    do:
      "space-y-1 rounded-xl border border-zinc-100 bg-zinc-50/60 p-4 transition hover:border-zinc-200"
end
