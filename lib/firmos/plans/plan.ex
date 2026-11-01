defmodule Firmos.Plans.Plan do
  @moduledoc """
  One version of a company's AI business plan.

  A plan moves `pending` → `generating` → `ready` | `failed`; a failed plan can
  go back to `pending` (try again). Regenerating adds a new version instead of
  changing this one, and the highest version is the company's current plan.

  Every field is set by `Firmos.Plans`, never cast from user params; the
  changesets here only validate and map the database constraints to errors.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Firmos.Companies.Company
  alias Firmos.Plans.Content

  @statuses [:pending, :generating, :ready, :failed]
  @ratings [:up, :down]

  @type status :: :pending | :generating | :ready | :failed
  @type rating :: :up | :down

  @type t :: %__MODULE__{
          id: integer() | nil,
          company_id: integer() | nil,
          company: Company.t() | Ecto.Association.NotLoaded.t() | nil,
          version: pos_integer() | nil,
          status: status(),
          content: Content.t() | nil,
          rating: rating() | nil,
          error: String.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "plans" do
    field :version, :integer
    field :status, Ecto.Enum, values: @statuses, default: :pending
    embeds_one :content, Content, on_replace: :update
    field :rating, Ecto.Enum, values: @ratings
    field :error, :string

    belongs_to :company, Company

    timestamps(type: :utc_datetime)
  end

  @doc "The ratings an owner can give."
  @spec ratings() :: [rating()]
  def ratings, do: @ratings

  @doc "A new pending plan `version` for `company_id`."
  @spec new_changeset(integer(), pos_integer()) :: Ecto.Changeset.t()
  def new_changeset(company_id, version) do
    %__MODULE__{}
    |> change(company_id: company_id, version: version, status: :pending)
    |> validate_required([:company_id, :version])
    |> validate_number(:version, greater_than: 0)
    |> foreign_key_constraint(:company_id)
    |> unique_constraint(:version, name: :plans_company_id_version_index)
    |> check_constraint(:version, name: :plans_version_positive)
  end

  @doc "Stores the generated `content` and marks the plan ready."
  @spec ready_changeset(t(), Content.t()) :: Ecto.Changeset.t()
  def ready_changeset(plan, %Content{} = content) do
    plan
    |> change(status: :ready, error: nil)
    |> put_embed(:content, content)
    |> check_constraint(:content, name: :plans_content_when_ready)
  end

  @doc "Marks the plan failed with a short, safe `error` code."
  @spec failed_changeset(t(), String.t()) :: Ecto.Changeset.t()
  def failed_changeset(plan, error) when is_binary(error) do
    plan
    |> change(status: :failed, error: error)
    |> validate_length(:error, max: 100)
    |> check_constraint(:error, name: :plans_error_only_when_failed)
    |> check_constraint(:error, name: :plans_error_length)
  end

  @doc "Puts a failed plan back in the queue."
  @spec pending_changeset(t()) :: Ecto.Changeset.t()
  def pending_changeset(plan) do
    plan
    |> change(status: :pending, error: nil)
    |> check_constraint(:error, name: :plans_error_only_when_failed)
  end

  @doc "Stores the owner's `rating` of a ready plan."
  @spec rating_changeset(t(), rating()) :: Ecto.Changeset.t()
  def rating_changeset(plan, rating) do
    plan
    |> change(rating: rating)
    |> validate_inclusion(:rating, @ratings)
    |> check_constraint(:rating, name: :plans_rating_only_when_ready)
  end
end
