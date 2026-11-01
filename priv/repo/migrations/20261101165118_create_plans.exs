defmodule Firmos.Repo.Migrations.CreatePlans do
  use Ecto.Migration

  def change do
    execute(
      "CREATE TYPE plan_status AS ENUM ('pending', 'generating', 'ready', 'failed')",
      "DROP TYPE plan_status"
    )

    execute("CREATE TYPE plan_rating AS ENUM ('up', 'down')", "DROP TYPE plan_rating")

    create table(:plans) do
      add :company_id, references(:companies, on_delete: :delete_all), null: false
      add :version, :integer, null: false
      add :status, :plan_status, null: false, default: "pending"
      # The AI document (offer, target_customer, competitors, pricing,
      # channels, tasks_30_days), typed in Elixir by Firmos.Plans.Content;
      # NULL until generation succeeds (#17).
      add :content, :map
      add :rating, :plan_rating
      # A short safe code (e.g. "http_status:500"), never a provider body.
      add :error, :text

      timestamps(type: :utc_datetime)
    end

    # Also serves the company_id FK lookups (leading column).
    create unique_index(:plans, [:company_id, :version])

    create constraint(:plans, :plans_version_positive, check: "version > 0")

    create constraint(:plans, :plans_content_object,
             check: "content IS NULL OR jsonb_typeof(content) = 'object'"
           )

    create constraint(:plans, :plans_content_when_ready,
             check: "status <> 'ready' OR content IS NOT NULL"
           )

    create constraint(:plans, :plans_error_only_when_failed,
             check: "(status = 'failed') = (error IS NOT NULL)"
           )

    create constraint(:plans, :plans_rating_only_when_ready,
             check: "rating IS NULL OR status = 'ready'"
           )

    create constraint(:plans, :plans_error_length, check: "char_length(error) <= 100")
  end
end
