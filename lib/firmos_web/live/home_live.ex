defmodule FirmosWeb.HomeLive do
  @moduledoc """
  The home page: a single prompt where a visitor or owner describes their
  business idea.

  A visitor's idea is saved as a draft and they continue to sign-up with the
  draft's token in the URL; a signed-in owner's idea is attached to them and
  they go straight to the dashboard.
  """
  use FirmosWeb, :live_view

  alias Firmos.Accounts.Scope
  alias Firmos.Ideas

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign_form(socket, Ideas.change_idea())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <section id="home-hero" class="mx-auto max-w-2xl space-y-8 py-12 sm:py-20">
        <div class="space-y-6 text-center">
          <p class="text-sm font-semibold uppercase tracking-widest text-base-content/60">Firmos</p>
          <h1 class="text-balance text-4xl font-semibold tracking-tight text-base-content sm:text-5xl">
            {gettext("An AI team that runs your small business.")}
          </h1>
          <p class="mx-auto max-w-xl text-pretty text-lg leading-8 text-base-content/70">
            {gettext(
              "You set the direction. Firmos agents build your website, look after your customers and report back every morning."
            )}
          </p>
        </div>

        <.form
          for={@form}
          id="idea-form"
          phx-change="validate"
          phx-submit="save"
          class="rounded-2xl border border-base-300 bg-base-100 p-4 shadow-sm transition-shadow focus-within:shadow-md sm:p-6"
        >
          <.input
            field={@form[:text]}
            id="idea-input"
            type="textarea"
            rows="5"
            label={gettext("Describe your business idea")}
            placeholder={
              gettext(
                "For example: an artisan bakery in Kraków that delivers fresh bread to offices every morning."
              )
            }
            phx-debounce="blur"
            required
          />
          <div class="flex flex-col-reverse items-stretch gap-3 pt-2 sm:flex-row sm:items-center sm:justify-between">
            <p class="text-sm text-base-content/60">
              {gettext("A few sentences are enough: what you sell, to whom and where.")}
            </p>
            <.button
              id="idea-submit"
              phx-disable-with={gettext("Saving...")}
              class="btn btn-primary transition-transform hover:-translate-y-0.5"
            >
              {gettext("Get started")} <span aria-hidden="true">&rarr;</span>
            </.button>
          </div>
        </.form>
      </section>
    </Layouts.app>
    """
  end

  @impl true
  def handle_event("validate", %{"idea" => idea_params}, socket) do
    changeset = Ideas.change_idea(idea_params)
    {:noreply, assign_form(socket, Map.put(changeset, :action, :validate))}
  end

  def handle_event("save", %{"idea" => idea_params}, socket) do
    socket.assigns.current_scope
    |> save_idea(idea_params)
    |> case do
      {:ok, {:owner, _idea}} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Your idea has been saved."))
         |> push_navigate(to: ~p"/dashboard")}

      {:ok, {:visitor, idea}} ->
        {:noreply, push_navigate(socket, to: ~p"/users/register?#{[idea: idea.token]}")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp save_idea(%Scope{user: user} = scope, params) when not is_nil(user) do
    with {:ok, idea} <- Ideas.create_for_user(scope, params), do: {:ok, {:owner, idea}}
  end

  defp save_idea(_scope, params) do
    with {:ok, idea} <- Ideas.create_draft(params), do: {:ok, {:visitor, idea}}
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    assign(socket, :form, to_form(changeset))
  end
end
