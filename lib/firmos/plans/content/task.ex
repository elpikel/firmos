defmodule Firmos.Plans.Content.Task do
  @moduledoc """
  One step of a plan's 30-day task list: `when` (a day or week, e.g.
  "Tydzień 1") and the `task` itself.
  """
  use Ecto.Schema

  import Ecto.Changeset

  @max_when 60
  @max_task 1_000

  @type t :: %__MODULE__{when: String.t() | nil, task: String.t() | nil}

  @primary_key false
  embedded_schema do
    field :when, :string
    field :task, :string
  end

  @doc "Validates one task as decoded from the AI's JSON."
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(task, attrs) do
    task
    |> cast(attrs, [:when, :task])
    |> validate_required([:when, :task])
    |> validate_length(:when, max: @max_when)
    |> validate_length(:task, max: @max_task)
  end
end
