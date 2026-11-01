defmodule Firmos.Sites.Site do
  @moduledoc """
  A company's landing page (one per company).

  The content lives in immutable `Firmos.Sites.Version`s; the site only
  points at the `current_version` (the draft the owner sees) and, once
  published (STORY-009), the `published_version` customers see on
  `<slug>.firmos.pl`. Every content change adds a version and moves a
  pointer, so older versions stay available for undo (STORY-010).

  `generation_status` tracks the AI generation of the next version:
  `idle` → `pending` → `generating` → `idle` (a version was stored) or
  `failed` (with a safe `generation_error` code; the owner can try again).

  Every field is set by `Firmos.Sites`, never cast from user params; the
  changesets here only validate and map the database constraints to errors.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Firmos.Companies.Company
  alias Firmos.Sites.Version

  @type status :: :draft | :published
  @type generation_status :: :idle | :pending | :generating | :failed

  @type t :: %__MODULE__{
          id: integer() | nil,
          company_id: integer() | nil,
          company: Company.t() | Ecto.Association.NotLoaded.t() | nil,
          slug: String.t() | nil,
          status: status(),
          generation_status: generation_status(),
          generation_error: String.t() | nil,
          generation_job_id: integer() | nil,
          current_version_id: integer() | nil,
          current_version: Version.t() | Ecto.Association.NotLoaded.t() | nil,
          published_version_id: integer() | nil,
          published_version: Version.t() | Ecto.Association.NotLoaded.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "sites" do
    # citext in the database: compared case-insensitively.
    field :slug, :string
    field :status, Ecto.Enum, values: [:draft, :published], default: :draft

    field :generation_status, Ecto.Enum,
      values: [:idle, :pending, :generating, :failed],
      default: :idle

    field :generation_error, :string
    # The Oban job holding the generation claim (see Firmos.Sites).
    field :generation_job_id, :integer

    belongs_to :company, Company
    belongs_to :current_version, Version
    belongs_to :published_version, Version
    has_many :versions, Version

    timestamps(type: :utc_datetime)
  end

  @doc "A new draft site for `company_id`, with no content yet."
  @spec new_changeset(integer()) :: Ecto.Changeset.t()
  def new_changeset(company_id) do
    %__MODULE__{}
    |> change(company_id: company_id)
    |> validate_required([:company_id])
    |> foreign_key_constraint(:company_id)
    |> unique_constraint(:company_id)
  end

  @doc "Queues the generation of a new version."
  @spec pending_changeset(t()) :: Ecto.Changeset.t()
  def pending_changeset(site) do
    site
    |> change(generation_status: :pending, generation_error: nil, generation_job_id: nil)
    # Re-queuing a stalled pending site changes no other field, so without
    # this Ecto would skip the UPDATE and the stall clock would stay old.
    |> force_change(:updated_at, DateTime.utc_now(:second))
    |> check_constraint(:generation_error, name: :sites_generation_error_only_when_failed)
  end

  @doc "Points the site at its new current `version` and ends the generation."
  @spec current_version_changeset(t(), Version.t()) :: Ecto.Changeset.t()
  def current_version_changeset(site, %Version{id: version_id}) do
    site
    |> change(current_version_id: version_id, generation_status: :idle, generation_error: nil)
    |> foreign_key_constraint(:current_version_id, name: :sites_current_version_id_fkey)
    |> check_constraint(:generation_error, name: :sites_generation_error_only_when_failed)
  end

  @doc "Marks the generation failed with a short, safe `code`."
  @spec failed_changeset(t(), String.t()) :: Ecto.Changeset.t()
  def failed_changeset(site, code) when is_binary(code) do
    site
    |> change(generation_status: :failed, generation_error: code)
    |> validate_length(:generation_error, max: 100)
    |> check_constraint(:generation_error, name: :sites_generation_error_only_when_failed)
    |> check_constraint(:generation_error, name: :sites_generation_error_length)
  end
end
