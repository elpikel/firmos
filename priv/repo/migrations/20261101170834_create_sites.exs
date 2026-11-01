defmodule Firmos.Repo.Migrations.CreateSites do
  use Ecto.Migration

  def change do
    execute(
      "CREATE TYPE site_status AS ENUM ('draft', 'published')",
      "DROP TYPE site_status"
    )

    execute(
      "CREATE TYPE site_generation_status AS ENUM ('idle', 'pending', 'generating', 'failed')",
      "DROP TYPE site_generation_status"
    )

    execute(
      "CREATE TYPE site_version_source AS ENUM ('generated', 'edited', 'undo')",
      "DROP TYPE site_version_source"
    )

    create table(:sites) do
      add :company_id, references(:companies, on_delete: :delete_all), null: false
      # The subdomain (`<slug>.firmos.pl`); NULL until STORY-009 publishes.
      add :slug, :citext
      add :status, :site_status, null: false, default: "draft"
      add :generation_status, :site_generation_status, null: false, default: "idle"
      # A short safe code (e.g. "http_status:500"), never a provider body.
      add :generation_error, :text
      # The Oban job holding the current generation's claim; only that job
      # may store the result. Not an FK: Oban prunes finished jobs.
      add :generation_job_id, :bigint

      timestamps(type: :utc_datetime)
    end

    # One site per company; also serves the company_id FK lookups.
    create unique_index(:sites, [:company_id])
    create unique_index(:sites, [:slug])

    # Checked on the text value: citext's `~` would also accept capitals.
    create constraint(:sites, :sites_slug_format,
             check: "slug IS NULL OR slug::text ~ '^[a-z0-9](?:[a-z0-9-]{1,61}[a-z0-9])?$'"
           )

    create constraint(:sites, :sites_generation_error_only_when_failed,
             check: "(generation_status = 'failed') = (generation_error IS NOT NULL)"
           )

    create constraint(:sites, :sites_generation_error_length,
             check: "char_length(generation_error) <= 100"
           )

    create table(:site_versions) do
      add :site_id, references(:sites, on_delete: :delete_all), null: false
      add :number, :integer, null: false
      # The landing page document (hero, offer, pricing, contact), typed in
      # Elixir by Firmos.Sites.Content (#18).
      add :content, :map, null: false
      add :source, :site_version_source, null: false

      # Versions are immutable: no updated_at.
      timestamps(type: :utc_datetime, updated_at: false)
    end

    # Also serves the site_id FK lookups (leading column).
    create unique_index(:site_versions, [:site_id, :number])
    # Target of the composite pointer FKs below.
    create unique_index(:site_versions, [:site_id, :id])

    create constraint(:site_versions, :site_versions_number_positive, check: "number > 0")

    create constraint(:site_versions, :site_versions_content_object,
             check: "jsonb_typeof(content) = 'object'"
           )

    # The pointers reference (site_id, id), so they can only reach this
    # site's own versions. MATCH SIMPLE: a NULL pointer is not checked.
    # Versions are deleted only with their site (cascade), never on their
    # own, so :restrict guards against deleting a pointed-at version.
    alter table(:sites) do
      # nullable-fk: a site has no version until its first generation succeeds.
      add :current_version_id,
          references(:site_versions, with: [id: :site_id], match: :simple, on_delete: :restrict)

      # nullable-fk: a draft site has never been published (STORY-009).
      add :published_version_id,
          references(:site_versions, with: [id: :site_id], match: :simple, on_delete: :restrict)
    end

    create index(:sites, [:current_version_id])
    create index(:sites, [:published_version_id])

    create constraint(:sites, :sites_published_has_version,
             check:
               "status <> 'published' OR (published_version_id IS NOT NULL AND slug IS NOT NULL)"
           )
  end
end
