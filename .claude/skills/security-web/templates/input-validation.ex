# Boundary input-validation pattern.
#
# Rule: external input (controller params, handle_event payloads, webhook
# bodies, Oban args from outside) is *parsed into a typed struct at the
# boundary* by a changeset, never passed raw into a query or schema. The
# `cast/3` field list is an allowlist — fields not in it cannot reach your
# domain (this is also the mass-assignment fix). After parsing, read the
# struct, never the raw params again.
#
# Copy to lib/firmos/<context>/<name>_params.ex and rename.

defmodule Firmos.Accounts.UpdateProfileParams do
  @moduledoc "Validated input for updating a user's own profile."
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    field :name, :string
    field :bio, :string
    field :visibility, Ecto.Enum, values: [:public, :private]
    # privilege/ownership fields (role, admin, user_id, org_id, confirmed_at)
    # are deliberately ABSENT — they come from the scope, never from input.
  end

  @type t :: %__MODULE__{}

  @fields [:name, :bio, :visibility]

  # 1. Parse at the boundary. `apply_action/2` returns {:ok, struct} or
  #    {:error, changeset} — the changeset feeds `to_form/1` for LiveView
  #    re-render; nothing is persisted.
  @spec parse(map()) :: {:ok, t()} | {:error, Ecto.Changeset.t()}
  def parse(params) when is_map(params) do
    %__MODULE__{}
    |> changeset(params)
    |> apply_action(:validate)
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(struct, params) do
    struct
    |> cast(params, @fields)                      # unknown keys silently dropped
    |> update_change(:name, &String.trim/1)
    |> validate_required([:name])
    |> validate_length(:name, min: 1, max: 80)
    |> validate_length(:bio, max: 500)
  end
end

# 2. Use the parsed value only; scope comes from the session, not params.
#
#   def handle_event("save", %{"profile" => params}, socket) do
#     scope = socket.assigns.current_scope
#
#     with {:ok, input} <- UpdateProfileParams.parse(params),
#          {:ok, _user} <- Accounts.update_profile(scope, input) do   # scope.user, not params["id"]
#       {:noreply, put_flash(socket, :info, "Saved")}
#     else
#       {:error, %Ecto.Changeset{} = cs} -> {:noreply, assign(socket, form: to_form(cs, as: :profile))}
#     end
#   end
#
# Notes:
# - Ids/numbers from path/query are strings — cast them through a schema
#   field (`:integer`, `:binary_id`) instead of `String.to_integer/1` (raises)
#   or `String.to_atom/1` (atom exhaustion).
# - Enums: `Ecto.Enum` maps strings to a fixed atom set — the safe
#   alternative to `String.to_atom`.
# - For persisted schemas the same rule applies: one changeset per use case,
#   cast only what that actor may set; set owner fields on the struct
#   (`%Invoice{org_id: scope.org.id}`) or via `put_change/3`.
# - On failure, log details server-side if useful; return the changeset
#   errors to the form, never internal state.
