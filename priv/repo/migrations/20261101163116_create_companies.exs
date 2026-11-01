defmodule Firmos.Repo.Migrations.CreateCompanies do
  use Ecto.Migration

  def change do
    create table(:companies) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :name, :text, null: false
      add :description, :text
      add :industry, :text
      add :city, :text
      add :contact_email, :text
      # nullable-fk: a company need not start from an idea (STORY-011 adds more
      # companies), and deleting an idea must never delete the company built
      # from it (#16).
      add :idea_id, references(:ideas, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create index(:companies, [:user_id])
    # One company per idea: the backstop for the claim race in
    # `Companies.ensure_company_from_idea/1`.
    create unique_index(:companies, [:idea_id])

    create constraint(:companies, :companies_name_length,
             check: "char_length(name) BETWEEN 1 AND 160"
           )

    create constraint(:companies, :companies_industry_length,
             check: "char_length(industry) <= 160"
           )

    create constraint(:companies, :companies_city_length, check: "char_length(city) <= 160")

    create constraint(:companies, :companies_contact_email_length,
             check: "char_length(contact_email) <= 160"
           )
  end
end
