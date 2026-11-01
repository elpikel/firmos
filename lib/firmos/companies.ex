defmodule Firmos.Companies do
  @moduledoc """
  Companies run by owners.

  An owner's company is created from the idea they described on the home page
  (`ensure_company_from_idea/2`); the owner then edits its profile basics.
  Every function takes the caller's `Firmos.Accounts.Scope` and only ever sees
  that owner's companies.

  `update_company/3` is the single write path for profile changes.

  Every change is recorded in the company's activity log (`Firmos.Activity`)
  in the same transaction as the change itself.
  """
  import Ecto.Query, warn: false

  alias Firmos.Accounts.Scope
  alias Firmos.Activity
  alias Firmos.Companies.Company
  alias Firmos.Ideas
  alias Firmos.Repo

  @doc """
  Turns each of the owner's unclaimed ideas into a company, oldest first, so
  the newest idea becomes the newest company. Each company gets the idea text
  as its description and `default_name` (a translated placeholder supplied by
  the caller) as its name, and a `company_created` activity entry by the owner.

  Everything runs in one transaction. Each idea is claimed with a conditional
  update that only matches while it is still unclaimed; ideas another caller
  claimed first (the LiveView's double mount, a second tab) are skipped, so
  every idea becomes exactly one company and repeat calls are no-ops.

  Returns `{:ok, companies}` with the companies created by this call (oldest
  first, `[]` when there was nothing to claim).
  """
  @spec ensure_company_from_idea(%Scope{}, String.t()) ::
          {:ok, [Company.t()]} | {:error, Ecto.Changeset.t()}
  def ensure_company_from_idea(%Scope{} = scope, default_name) when is_binary(default_name) do
    case Ideas.list_unclaimed_for_user(scope) do
      [] -> {:ok, []}
      ideas -> Repo.transact(fn -> create_companies_from_ideas(scope, ideas, default_name) end)
    end
  end

  defp create_companies_from_ideas(scope, ideas, default_name) do
    ideas
    |> Enum.reduce_while({:ok, []}, fn idea, {:ok, created} ->
      case create_company_from_idea(scope, idea, default_name) do
        {:ok, company} -> {:cont, {:ok, [company | created]}}
        {:error, :already_claimed} -> {:cont, {:ok, created}}
        {:error, %Ecto.Changeset{}} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, created} -> {:ok, Enum.reverse(created)}
      error -> error
    end
  end

  defp create_company_from_idea(%Scope{user: %{id: user_id}} = scope, idea, default_name) do
    with {:ok, claimed} <- Ideas.claim(scope, idea),
         {:ok, company} <-
           %Company{user_id: user_id, idea_id: claimed.id, description: claimed.text}
           |> Company.profile_changeset(%{name: default_name})
           |> Repo.insert(),
         {:ok, _entry} <-
           Activity.record(company, scope, :company_created, metadata: %{"name" => company.name}) do
      {:ok, company}
    end
  end

  @doc "Returns the owner's companies, newest first."
  @spec list_companies(%Scope{}) :: [Company.t()]
  def list_companies(%Scope{} = scope) do
    scope
    |> owned_query()
    |> order_by([company: c], desc: c.inserted_at, desc: c.id)
    |> Repo.all()
  end

  @doc "Returns the owner's newest company, or `nil`."
  @spec latest_company(%Scope{}) :: Company.t() | nil
  def latest_company(%Scope{} = scope) do
    scope
    |> owned_query()
    |> order_by([company: c], desc: c.inserted_at, desc: c.id)
    |> limit(1)
    |> Repo.one()
  end

  @doc """
  Gets one of the owner's companies.

  Raises `Ecto.NoResultsError` (a 404) when the id doesn't exist or belongs to
  another owner.
  """
  @spec get_company!(%Scope{}, integer() | String.t()) :: Company.t()
  def get_company!(%Scope{} = scope, id) do
    scope
    |> owned_query()
    |> where([company: c], c.id == ^id)
    |> Repo.one!()
  end

  @doc """
  Returns a changeset for the company profile form. Raises
  `FunctionClauseError` for a company the scope doesn't own.
  """
  @spec change_company(%Scope{}, Company.t(), map()) :: Ecto.Changeset.t()
  def change_company(
        %Scope{user: %{id: user_id}},
        %Company{user_id: user_id} = company,
        attrs \\ %{}
      ) do
    Company.profile_changeset(company, attrs)
  end

  @doc """
  Updates the profile basics of one of the owner's companies. The single
  write path for profile changes. Raises `FunctionClauseError` for a company
  the scope doesn't own.

  In the same transaction it records a `company_updated` activity entry by the
  owner with each changed field's old and new value. Nothing changed, no entry.
  """
  @spec update_company(%Scope{}, Company.t(), map()) ::
          {:ok, Company.t()} | {:error, Ecto.Changeset.t()}
  def update_company(
        %Scope{user: %{id: user_id}} = scope,
        %Company{user_id: user_id} = company,
        attrs
      ) do
    changeset = Company.profile_changeset(company, attrs)

    Repo.transact(fn ->
      with {:ok, updated} <- Repo.update(changeset),
           {:ok, _entry_or_unchanged} <- record_profile_changes(scope, company, changeset) do
        {:ok, updated}
      end
    end)
  end

  defp record_profile_changes(scope, company, changeset) do
    case profile_changes(company, changeset) do
      changes when map_size(changes) == 0 ->
        {:ok, :unchanged}

      changes ->
        Activity.record(company, scope, :company_updated, metadata: %{"changes" => changes})
    end
  end

  # Ecto drops a change equal to the current value, so `changes` holds only
  # the fields that actually changed.
  defp profile_changes(company, %Ecto.Changeset{changes: changes}) do
    Map.new(changes, fn {field, new_value} ->
      {Atom.to_string(field), %{"from" => Map.fetch!(company, field), "to" => new_value}}
    end)
  end

  defp owned_query(%Scope{user: %{id: user_id}}) do
    from(c in Company, as: :company)
    |> where([company: c], c.user_id == ^user_id)
  end
end
