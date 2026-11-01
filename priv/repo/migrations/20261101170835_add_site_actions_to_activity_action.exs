defmodule Firmos.Repo.Migrations.AddSiteActionsToActivityAction do
  use Ecto.Migration

  # Nothing here uses the new values, so they can be added inside the
  # migration's transaction (see CreateActivities, #14). `site_updated`,
  # `site_published` and `site_undone` are for STORY-009/010.
  def up do
    execute("ALTER TYPE activity_action ADD VALUE IF NOT EXISTS 'site_generated'")
    execute("ALTER TYPE activity_action ADD VALUE IF NOT EXISTS 'site_updated'")
    execute("ALTER TYPE activity_action ADD VALUE IF NOT EXISTS 'site_published'")
    execute("ALTER TYPE activity_action ADD VALUE IF NOT EXISTS 'site_undone'")
  end

  # Postgres can't drop an enum value; the values stay harmlessly unused.
  def down, do: :ok
end
