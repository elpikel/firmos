defmodule Firmos.Approvals.Approval do
  @moduledoc """
  A request, made by an agent, for the owner's consent to an action outside
  the plan: today publishing a site version (`kind` `publish_site_version`,
  with its `site_version`).

  `status` goes `pending` → `approved` or `rejected` (the owner's decision,
  with `decided_by_user_id`), or `superseded` (a newer request, or the site
  moved on so the request no longer applies). A company has at most one
  pending request per kind. `decided_at` is set exactly when the request is
  no longer pending.

  Every field is set by `Firmos.Approvals`, never cast from user params; the
  changesets only map the database constraints to errors.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Firmos.Accounts.User
  alias Firmos.Companies.Company
  alias Firmos.Sites.Version

  @type kind :: :publish_site_version
  @type status :: :pending | :approved | :rejected | :superseded

  @type t :: %__MODULE__{
          id: integer() | nil,
          company_id: integer() | nil,
          company: Company.t() | Ecto.Association.NotLoaded.t() | nil,
          kind: kind() | nil,
          site_version_id: integer() | nil,
          site_version: Version.t() | Ecto.Association.NotLoaded.t() | nil,
          status: status(),
          requested_by: :agent | nil,
          decided_by_user_id: integer() | nil,
          decided_by_user: %User{} | Ecto.Association.NotLoaded.t() | nil,
          decided_at: DateTime.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "approvals" do
    field :kind, Ecto.Enum, values: [:publish_site_version]

    field :status, Ecto.Enum,
      values: [:pending, :approved, :rejected, :superseded],
      default: :pending

    field :requested_by, Ecto.Enum, values: [:agent]
    field :decided_at, :utc_datetime

    belongs_to :company, Company
    belongs_to :site_version, Version
    belongs_to :decided_by_user, User

    timestamps(type: :utc_datetime)
  end

  @doc "A new pending request by an agent to publish `version_id` of the company's site."
  @spec publish_request_changeset(integer(), integer()) :: Ecto.Changeset.t()
  def publish_request_changeset(company_id, version_id) do
    %__MODULE__{}
    |> change(
      company_id: company_id,
      kind: :publish_site_version,
      site_version_id: version_id,
      requested_by: :agent
    )
    |> validate_required([:company_id, :kind, :site_version_id, :requested_by])
    |> foreign_key_constraint(:company_id)
    |> foreign_key_constraint(:site_version_id)
    |> unique_constraint([:company_id, :kind],
      name: :approvals_one_pending_per_kind,
      message: "already has a pending request"
    )
    |> check_constraint(:site_version_id, name: :approvals_publish_has_site_version)
  end

  @doc "The owner's decision (`:approved` or `:rejected`) by `user_id`, now."
  @spec decide_changeset(t(), :approved | :rejected, integer()) :: Ecto.Changeset.t()
  def decide_changeset(%__MODULE__{status: :pending} = approval, decision, user_id)
      when decision in [:approved, :rejected] and is_integer(user_id) do
    approval
    |> change(status: decision, decided_by_user_id: user_id, decided_at: now())
    |> foreign_key_constraint(:decided_by_user_id)
    |> check_constraint(:decided_at, name: :approvals_decided_at_when_decided)
    |> check_constraint(:decided_by_user_id, name: :approvals_decider_only_when_decided)
  end

  defp now, do: DateTime.utc_now(:second)
end
