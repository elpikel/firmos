defmodule Firmos.Repo.Migrations.CreateIdeas do
  use Ecto.Migration

  def change do
    create table(:ideas) do
      add :text, :text, null: false
      add :token, :text, null: false
      # nullable-fk: a visitor's idea is saved as a draft before they have an
      # account; it is attached to the user once they sign up (#15).
      add :user_id, references(:users, on_delete: :delete_all)
      # Set when the idea is turned into a company (STORY-006).
      add :claimed_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:ideas, [:token])
    create index(:ideas, [:user_id])

    create constraint(:ideas, :ideas_text_length, check: "char_length(text) BETWEEN 20 AND 2000")
  end
end
