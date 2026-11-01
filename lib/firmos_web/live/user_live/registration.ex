defmodule FirmosWeb.UserLive.Registration do
  use FirmosWeb, :live_view

  alias Firmos.Accounts
  alias Firmos.Accounts.Scope
  alias Firmos.Accounts.User
  alias Firmos.Ideas
  alias Firmos.Ideas.Idea

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-sm">
        <div class="text-center">
          <.header>
            {gettext("Register for an account")}
            <:subtitle>
              {gettext("Already registered?")}
              <.link navigate={~p"/users/log-in"} class="font-semibold text-brand hover:underline">
                {gettext("Log in")}
              </.link>
            </:subtitle>
          </.header>
        </div>

        <figure
          :if={@idea}
          id="preserved-idea"
          class="mb-6 space-y-2 rounded-2xl border border-base-300 bg-base-200/60 p-4"
        >
          <figcaption class="flex items-center gap-2 text-sm font-semibold text-base-content/70">
            <.icon name="hero-light-bulb" class="size-4" />
            {gettext("Your idea")}
          </figcaption>
          <blockquote class="whitespace-pre-line break-words text-sm leading-6 text-base-content">
            {@idea.text}
          </blockquote>
          <p class="text-xs text-base-content/60">
            {gettext("Create an account and we will start working on it.")}
          </p>
        </figure>

        <.form for={@form} id="registration_form" phx-submit="save" phx-change="validate">
          <.input
            field={@form[:email]}
            type="email"
            label={gettext("Email")}
            autocomplete="username"
            spellcheck="false"
            required
            phx-mounted={JS.focus()}
          />

          <.button phx-disable-with={gettext("Creating account...")} class="btn btn-primary w-full">
            {gettext("Create an account")}
          </.button>
        </.form>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, %{assigns: %{current_scope: %{user: user}}} = socket)
      when not is_nil(user) do
    {:ok, redirect(socket, to: FirmosWeb.UserAuth.signed_in_path(socket))}
  end

  def mount(params, _session, socket) do
    changeset = Accounts.change_user_email(%User{}, %{}, validate_unique: false)

    {:ok,
     socket
     |> assign(:idea, Ideas.get_draft_by_token(params["idea"]))
     |> assign_form(changeset), temporary_assigns: [form: nil]}
  end

  @impl true
  def handle_event("save", %{"user" => user_params}, socket) do
    case Accounts.register_user(user_params) do
      {:ok, user} ->
        :ok = attach_idea(user, socket.assigns.idea)

        {:ok, _} =
          Accounts.deliver_login_instructions(
            user,
            &url(~p"/users/log-in/#{&1}")
          )

        {:noreply,
         socket
         |> put_flash(
           :info,
           gettext(
             "An email was sent to %{email}, please access it to confirm your account.",
             email: user.email
           )
         )
         |> push_navigate(to: ~p"/users/log-in")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  def handle_event("validate", %{"user" => user_params}, socket) do
    changeset = Accounts.change_user_email(%User{}, user_params, validate_unique: false)
    {:noreply, assign_form(socket, Map.put(changeset, :action, :validate))}
  end

  # The draft may have been attached by another tab between mount and submit;
  # the account still exists, so sign-up carries on without the idea.
  defp attach_idea(_user, nil), do: :ok

  defp attach_idea(user, %Idea{token: token}) do
    case Ideas.attach_to_user(Scope.for_user(user), token) do
      {:ok, _idea} -> :ok
      {:error, :not_found} -> :ok
    end
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    form = to_form(changeset, as: "user")
    assign(socket, form: form)
  end
end
