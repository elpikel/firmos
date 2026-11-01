defmodule Firmos.Repo.Migrations.CreateActivities do
  use Ecto.Migration

  def change do
    execute(
      "CREATE TYPE activity_actor AS ENUM ('owner', 'agent', 'system')",
      "DROP TYPE activity_actor"
    )

    # Later stories add values with `ALTER TYPE activity_action ADD VALUE '…'`
    # in their own migration (#14). A new value can't be used in the
    # transaction that adds it, so keep that migration free of anything using
    # it (or set `@disable_ddl_transaction true`). Postgres can't drop an enum
    # value, so write it as `up/0` with a no-op or raising `down/0`.
    execute(
      "CREATE TYPE activity_action AS ENUM ('company_created', 'company_updated')",
      "DROP TYPE activity_action"
    )

    create table(:activities) do
      add :company_id, references(:companies, on_delete: :delete_all), null: false
      add :actor, :activity_actor, null: false
      # nullable-fk: only owner actions carry a user (agents and the system have
      # none), and an entry must outlive the user it names (#14).
      add :actor_user_id, references(:users, on_delete: :nilify_all)
      add :action, :activity_action, null: false
      add :metadata, :map, null: false, default: %{}
      # What the entry is about beyond the company itself (e.g. a site version
      # for STORY-010 undo); polymorphic, so no FK.
      add :subject_type, :text
      add :subject_id, :bigint

      # Entries are immutable: no updated_at.
      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:activities, [:company_id, "inserted_at DESC", "id DESC"])
    create index(:activities, [:actor_user_id])

    create constraint(:activities, :activities_metadata_object,
             check: "jsonb_typeof(metadata) = 'object'"
           )

    create constraint(:activities, :activities_subject_complete,
             check: "(subject_type IS NULL) = (subject_id IS NULL)"
           )

    create constraint(:activities, :activities_actor_user_only_for_owner,
             check: "actor = 'owner' OR actor_user_id IS NULL"
           )
  end
end
