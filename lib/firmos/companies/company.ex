defmodule Firmos.Companies.Company do
  @moduledoc """
  A company run by an owner on Firmos.

  A company usually starts from the owner's idea (`idea_id`, with the idea text
  as its `description`). The owner then edits its profile basics: name,
  industry, city and contact email.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Firmos.Accounts.User
  alias Firmos.Ideas.Idea

  @max_length 160

  @type t :: %__MODULE__{
          id: integer() | nil,
          name: String.t() | nil,
          description: String.t() | nil,
          industry: String.t() | nil,
          city: String.t() | nil,
          contact_email: String.t() | nil,
          user_id: integer() | nil,
          user: %User{} | Ecto.Association.NotLoaded.t() | nil,
          idea_id: integer() | nil,
          idea: Idea.t() | Ecto.Association.NotLoaded.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "companies" do
    field :name, :string
    field :description, :string
    field :industry, :string
    field :city, :string
    field :contact_email, :string

    belongs_to :user, User
    belongs_to :idea, Idea

    timestamps(type: :utc_datetime)
  end

  @profile_fields [:name, :industry, :city, :contact_email]

  @doc """
  Validates the owner-editable profile basics.

  `user_id`, `idea_id` and `description` are set by `Firmos.Companies`, never
  cast from params.
  """
  @spec profile_changeset(t(), map()) :: Ecto.Changeset.t()
  def profile_changeset(company, attrs) do
    company
    |> cast(attrs, @profile_fields)
    |> trim(@profile_fields)
    |> validate_required([:name])
    |> validate_length(:name, max: @max_length, count: :codepoints)
    |> validate_length(:industry, max: @max_length, count: :codepoints)
    |> validate_length(:city, max: @max_length, count: :codepoints)
    |> validate_length(:contact_email, max: @max_length, count: :codepoints)
    |> validate_format(:contact_email, ~r/^[^@,;\s]+@[^@,;\s]+$/,
      message: "must have the @ sign and no spaces"
    )
    |> check_constraint(:name, name: :companies_name_length)
    |> check_constraint(:industry, name: :companies_industry_length)
    |> check_constraint(:city, name: :companies_city_length)
    |> check_constraint(:contact_email, name: :companies_contact_email_length)
    |> unique_constraint(:idea_id)
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:idea_id)
  end

  defp trim(changeset, fields) do
    Enum.reduce(fields, changeset, fn field, acc ->
      update_change(acc, field, &trim_value/1)
    end)
  end

  # A cleared field arrives as `nil` (Ecto's empty-value handling).
  defp trim_value(value) when is_binary(value), do: String.trim(value)
  defp trim_value(nil), do: nil
end
