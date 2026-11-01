defmodule Firmos.Repo.Migrations.CreateApprovals do
  use Ecto.Migration

  def change do
    # Spending approvals (M4/M5) add their kinds with ALTER TYPE ... ADD VALUE.
    execute(
      "CREATE TYPE approval_kind AS ENUM ('publish_site_version')",
      "DROP TYPE approval_kind"
    )

    execute(
      "CREATE TYPE approval_status AS ENUM ('pending', 'approved', 'rejected', 'superseded')",
      "DROP TYPE approval_status"
    )

    execute(
      "CREATE TYPE approval_requester AS ENUM ('agent')",
      "DROP TYPE approval_requester"
    )

    create table(:approvals) do
      add :company_id, references(:companies, on_delete: :delete_all), null: false
      add :kind, :approval_kind, null: false
      # nullable-fk: required for the publish kind only (CHECK below); later
      # kinds are about other things. NO ACTION, not RESTRICT: checked at the
      # end of the statement, so a company deletion cascading to both the
      # versions and the approvals succeeds, while deleting a requested
      # version on its own is still refused (#37).
      add :site_version_id, references(:site_versions, on_delete: :nothing)
      add :status, :approval_status, null: false, default: "pending"
      add :requested_by, :approval_requester, null: false
      # nullable-fk: only an owner's approve/reject has a decider (not a
      # pending or superseded request), and the decision outlives the user.
      add :decided_by_user_id, references(:users, on_delete: :nilify_all)
      add :decided_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    # The queue: at most one pending request per company and kind.
    create unique_index(:approvals, [:company_id, :kind],
             where: "status = 'pending'",
             name: :approvals_one_pending_per_kind
           )

    # Listing a company's requests (also serves the company_id FK).
    create index(:approvals, [:company_id, :status, "inserted_at DESC"])
    create index(:approvals, [:site_version_id])
    create index(:approvals, [:decided_by_user_id])

    create constraint(:approvals, :approvals_publish_has_site_version,
             check: "kind <> 'publish_site_version' OR site_version_id IS NOT NULL"
           )

    create constraint(:approvals, :approvals_decided_at_when_decided,
             check: "(status = 'pending') = (decided_at IS NULL)"
           )

    create constraint(:approvals, :approvals_decider_only_when_decided,
             check: "decided_by_user_id IS NULL OR status IN ('approved', 'rejected')"
           )
  end
end
