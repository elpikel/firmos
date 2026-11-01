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

  Every field but the slug is set by `Firmos.Sites`, never cast from user
  params; the slug is the owner's choice, normalized and checked against
  `Firmos.Sites.Slug` by `slug_changeset/2`. The changesets also map the
  database constraints to errors.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Firmos.Companies.Company
  alias Firmos.Sites.Slug
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

  @doc "Points the site at its new generated `version` and ends the generation."
  @spec current_version_changeset(t(), Version.t()) :: Ecto.Changeset.t()
  def current_version_changeset(site, %Version{} = version) do
    site
    |> current_version_pointer_changeset(version)
    |> change(generation_status: :idle, generation_error: nil)
    |> check_constraint(:generation_error, name: :sites_generation_error_only_when_failed)
  end

  @doc """
  Points the site at its new current `version` (an owner's edit), leaving
  the generation status alone.
  """
  @spec current_version_pointer_changeset(t(), Version.t()) :: Ecto.Changeset.t()
  def current_version_pointer_changeset(site, %Version{id: version_id}) do
    site
    |> change(current_version_id: version_id)
    |> foreign_key_constraint(:current_version_id, name: :sites_current_version_id_fkey)
  end

  @doc """
  The owner's slug (`attrs["slug"]`): trimmed and downcased, then checked
  for the format, the length and the reserved names. A slug another site
  holds (in any letter case: the column is citext) is "slug already taken".
  """
  @spec slug_changeset(t(), map()) :: Ecto.Changeset.t()
  def slug_changeset(site, attrs) do
    site
    |> cast(attrs, [:slug])
    |> update_change(:slug, &Slug.normalize/1)
    |> validate_required([:slug])
    |> validate_length(:slug, min: Slug.min_length(), max: Slug.max_length())
    |> validate_slug_format()
    |> validate_exclusion(:slug, Slug.reserved())
    |> validate_change(:slug, fn :slug, slug ->
      if Slug.punycode?(slug), do: [slug: "can't start with xn--"], else: []
    end)
    |> unique_constraint(:slug, message: "slug already taken")
    |> check_constraint(:slug, name: :sites_slug_format)
  end

  @doc """
  Publishes the current version: customers see it at the slug's address.
  Needs a slug and a current version.
  """
  @spec publish_changeset(t()) :: Ecto.Changeset.t()
  def publish_changeset(%__MODULE__{current_version_id: version_id} = site) do
    site
    |> change(status: :published, published_version_id: version_id)
    |> validate_required([:slug, :published_version_id])
    |> foreign_key_constraint(:published_version_id, name: :sites_published_version_id_fkey)
    |> check_constraint(:status, name: :sites_published_has_version)
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

  # Skipped after a length error: the format regex also rejects short and
  # long slugs, and one error says more than two.
  defp validate_slug_format(changeset) do
    if Keyword.has_key?(changeset.errors, :slug) do
      changeset
    else
      validate_format(changeset, :slug, Slug.format(),
        message: "may only contain lowercase letters, digits and hyphens, not at the start or end"
      )
    end
  end
end
