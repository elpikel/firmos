defmodule FirmosWeb.CompanyLive.Profile do
  @moduledoc """
  Lets an owner edit their company's profile basics: name, industry, city and
  contact email. The company is loaded through the owner's scope, so another
  owner's company id is a 404.
  """
  use FirmosWeb, :live_view

  alias Firmos.Companies

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    company = Companies.get_company!(socket.assigns.current_scope, id)

    {:ok,
     socket
     |> assign(:page_title, gettext("Company profile"))
     |> assign(:company, company)
     |> assign_form(Companies.change_company(socket.assigns.current_scope, company))}
  end

  @impl true
  def handle_event("validate", %{"company" => params}, socket) do
    %{current_scope: scope, company: company} = socket.assigns
    changeset = Companies.change_company(scope, company, params)
    {:noreply, assign_form(socket, Map.put(changeset, :action, :validate))}
  end

  def handle_event("save", %{"company" => params}, socket) do
    %{current_scope: scope, company: company} = socket.assigns

    case Companies.update_company(scope, company, params) do
      {:ok, company} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Company profile saved."))
         |> assign(:company, company)
         |> assign_form(Companies.change_company(scope, company))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp assign_form(socket, changeset), do: assign(socket, :form, to_form(changeset))

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <section id="company-profile" class="mx-auto max-w-xl space-y-8">
        <header class="space-y-2">
          <.link
            id="company-profile-back"
            navigate={~p"/dashboard"}
            class="inline-flex items-center gap-1 text-sm font-medium text-zinc-500 transition hover:text-zinc-900"
          >
            <.icon name="hero-arrow-left" class="size-4" />
            {gettext("Dashboard")}
          </.link>
          <h1 class="text-2xl font-semibold tracking-tight text-zinc-900">
            {gettext("Company profile")}
          </h1>
          <p class="text-sm text-zinc-500">
            {gettext("The basics customers will see about your company.")}
          </p>
        </header>

        <.form
          for={@form}
          id="company-profile-form"
          phx-change="validate"
          phx-submit="save"
          class="space-y-4 rounded-2xl border border-zinc-200 bg-white p-6 shadow-sm"
        >
          <.input field={@form[:name]} type="text" label={gettext("Company name")} />
          <.input field={@form[:industry]} type="text" label={gettext("Industry")} />
          <.input field={@form[:city]} type="text" label={gettext("City")} />
          <.input
            field={@form[:contact_email]}
            type="email"
            label={gettext("Contact email")}
            autocomplete="email"
            spellcheck="false"
          />
          <div class="flex justify-end pt-2">
            <.button
              id="company-profile-save"
              variant="primary"
              phx-disable-with={gettext("Saving...")}
            >
              {gettext("Save")}
            </.button>
          </div>
        </.form>
      </section>
    </Layouts.app>
    """
  end
end
