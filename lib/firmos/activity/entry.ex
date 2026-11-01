defmodule Firmos.Activity.Entry do
  @moduledoc """
  One immutable entry in a company's activity log: who (`actor`) did what
  (`action`) and when (`inserted_at`), with the details in `metadata`.

  The human-readable summary is not stored; the web layer renders it from
  `action` + `metadata` through gettext, so the log follows the UI language.
  `metadata` is string-keyed JSON once loaded from the database.

  Entries are built by `Firmos.Activity`; every field is set by the context,
  never cast from user params.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Firmos.Accounts.User
  alias Firmos.Companies.Company

  @actors [:owner, :agent, :system]
  @actions [
    :company_created,
    :company_updated,
    :plan_generated,
    :plan_regenerated,
    :site_generated,
    :site_updated,
    :site_published,
    :site_undone,
    :approval_requested,
    :approval_approved,
    :approval_rejected
  ]

  @type actor :: :owner | :agent | :system
  @type action ::
          :company_created
          | :company_updated
          | :plan_generated
          | :plan_regenerated
          | :site_generated
          | :site_updated
          | :site_published
          | :site_undone
          | :approval_requested
          | :approval_approved
          | :approval_rejected

  @type t :: %__MODULE__{
          id: integer() | nil,
          company_id: integer() | nil,
          company: Company.t() | Ecto.Association.NotLoaded.t() | nil,
          actor: actor() | nil,
          actor_user_id: integer() | nil,
          actor_user: %User{} | Ecto.Association.NotLoaded.t() | nil,
          action: action() | nil,
          metadata: map(),
          subject_type: String.t() | nil,
          subject_id: integer() | nil,
          inserted_at: DateTime.t() | nil
        }

  schema "activities" do
    field :actor, Ecto.Enum, values: @actors
    field :action, Ecto.Enum, values: @actions
    field :metadata, :map, default: %{}
    field :subject_type, :string
    field :subject_id, :integer

    belongs_to :company, Company
    belongs_to :actor_user, User

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @doc "The actions an entry can record."
  @spec actions() :: [action()]
  def actions, do: @actions

  @doc """
  Builds a new entry. Every field comes from `Firmos.Activity`, not from user
  params; the changeset only maps the database constraints to errors.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(entry, attrs) do
    entry
    |> change(attrs)
    |> validate_required([:company_id, :actor, :action])
    |> validate_inclusion(:actor, @actors)
    |> validate_inclusion(:action, @actions)
    |> foreign_key_constraint(:company_id)
    |> foreign_key_constraint(:actor_user_id)
    |> check_constraint(:metadata, name: :activities_metadata_object)
    |> check_constraint(:subject_id, name: :activities_subject_complete)
    |> check_constraint(:actor_user_id, name: :activities_actor_user_only_for_owner)
  end
end
