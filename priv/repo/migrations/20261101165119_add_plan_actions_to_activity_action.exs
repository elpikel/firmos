defmodule Firmos.Repo.Migrations.AddPlanActionsToActivityAction do
  use Ecto.Migration

  # Nothing here uses the new values, so they can be added inside the
  # migration's transaction (see CreateActivities, #14).
  def up do
    execute("ALTER TYPE activity_action ADD VALUE IF NOT EXISTS 'plan_generated'")
    execute("ALTER TYPE activity_action ADD VALUE IF NOT EXISTS 'plan_regenerated'")
  end

  # Postgres can't drop an enum value; the values stay harmlessly unused.
  def down, do: :ok
end
