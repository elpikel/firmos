defmodule Firmos.Ideas.Idea do
  @moduledoc """
  A business idea described by a visitor or owner on the home page.

  An idea starts either as an anonymous draft (no `user_id`, readable only via
  its `token`) or attached to an owner. `claimed_at` is set once the idea has
  been turned into a company.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Firmos.Accounts.User

  @min_length 20
  @max_length 2000

  # The token is a bearer capability for reading the draft; keep it out of logs.
  @derive {Inspect, except: [:token]}

  @type t :: %__MODULE__{
          id: integer() | nil,
          text: String.t() | nil,
          token: String.t() | nil,
          user_id: integer() | nil,
          user: %User{} | Ecto.Association.NotLoaded.t() | nil,
          claimed_at: DateTime.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "ideas" do
    field :text, :string
    field :token, :string
    field :claimed_at, :utc_datetime

    belongs_to :user, User

    timestamps(type: :utc_datetime)
  end

  @doc """
  Validates the owner-supplied idea text: trimmed, #{@min_length}–#{@max_length}
  characters (codepoints, matching the `ideas_text_length` DB check).

  `token` and `user_id` are set by `Firmos.Ideas`, never cast from params.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(idea, attrs) do
    idea
    |> cast(attrs, [:text])
    |> update_change(:text, &String.trim/1)
    |> validate_required([:text])
    |> validate_no_null_bytes()
    |> validate_length(:text,
      min: @min_length,
      count: :codepoints,
      message: "is too short, please give more detail (at least %{count} characters)"
    )
    |> validate_length(:text,
      max: @max_length,
      count: :codepoints,
      message: "is too long, maximum %{count} characters"
    )
    |> check_constraint(:text, name: :ideas_text_length)
    |> unique_constraint(:token)
  end

  # Postgres `text` cannot store U+0000; without this the insert raises.
  defp validate_no_null_bytes(changeset) do
    validate_change(changeset, :text, fn :text, text ->
      if String.contains?(text, <<0>>),
        do: [text: "contains characters that are not allowed"],
        else: []
    end)
  end
end
