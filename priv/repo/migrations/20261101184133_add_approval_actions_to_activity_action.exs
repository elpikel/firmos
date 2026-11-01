defmodule Firmos.Repo.Migrations.AddApprovalActionsToActivityAction do
  use Ecto.Migration

  # Nothing here uses the new values, so they can be added inside the
  # migration's transaction (see CreateActivities, #14). STORY-014 (#37).
  def up do
    execute("ALTER TYPE activity_action ADD VALUE IF NOT EXISTS 'approval_requested'")
    execute("ALTER TYPE activity_action ADD VALUE IF NOT EXISTS 'approval_approved'")
    execute("ALTER TYPE activity_action ADD VALUE IF NOT EXISTS 'approval_rejected'")
  end

  # Postgres can't drop an enum value; the values stay harmlessly unused.
  def down, do: :ok
end
