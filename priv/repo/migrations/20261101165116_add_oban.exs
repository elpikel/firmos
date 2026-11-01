defmodule Firmos.Repo.Migrations.AddOban do
  use Ecto.Migration

  # Oban's own tables (#17). Pinned to version 14 so a later Oban upgrade adds
  # its migration explicitly instead of silently changing this one.
  def up, do: Oban.Migration.up(version: 14)

  def down, do: Oban.Migration.down(version: 1)
end
