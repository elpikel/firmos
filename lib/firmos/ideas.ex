defmodule Firmos.Ideas do
  @moduledoc """
  Business ideas typed into the home-page prompt.

  A visitor's idea is stored as an anonymous **draft** identified by a random,
  URL-safe token. The token only lets its holder read that one draft's text
  (to show it on the sign-up step) and attach it to the account they create;
  once attached it can no longer be read by token. Signed-in owners' ideas are
  attached to them directly.
  """
  import Ecto.Query, warn: false

  alias Firmos.Accounts.Scope
  alias Firmos.Ideas.Idea
  alias Firmos.Repo

  @token_bytes 32

  @doc "Returns a changeset for the idea form."
  @spec change_idea(map()) :: Ecto.Changeset.t()
  def change_idea(attrs \\ %{}) do
    Idea.changeset(%Idea{}, attrs)
  end

  @doc """
  Saves a visitor's idea as an unattached draft with a fresh token.
  """
  @spec create_draft(map()) :: {:ok, Idea.t()} | {:error, Ecto.Changeset.t()}
  def create_draft(attrs) do
    %Idea{token: generate_token()}
    |> Idea.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Saves an idea attached to the scope's owner.
  """
  @spec create_for_user(%Scope{}, map()) :: {:ok, Idea.t()} | {:error, Ecto.Changeset.t()}
  def create_for_user(%Scope{user: %{id: user_id}}, attrs) do
    %Idea{token: generate_token(), user_id: user_id}
    |> Idea.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Returns the unattached draft for `token`, or `nil`.

  Drafts already attached to a user are never returned, so a leaked token
  stops being useful once the visitor has signed up.
  """
  @spec get_draft_by_token(String.t() | nil) :: Idea.t() | nil
  def get_draft_by_token(token) when is_binary(token) and token != "" do
    token
    |> draft_by_token_query()
    |> Repo.one()
  end

  def get_draft_by_token(_token), do: nil

  @doc """
  Attaches the unattached draft identified by `token` to the scope's owner.

  Returns `{:error, :not_found}` when no such draft exists (unknown token, or
  already attached).
  """
  @spec attach_to_user(%Scope{}, String.t() | nil) :: {:ok, Idea.t()} | {:error, :not_found}
  def attach_to_user(%Scope{user: %{id: user_id}}, token) when is_binary(token) and token != "" do
    query = select(draft_by_token_query(token), [idea: i], i)
    now = DateTime.utc_now(:second)

    case Repo.update_all(query, set: [user_id: user_id, updated_at: now]) do
      {1, [idea]} -> {:ok, idea}
      {0, []} -> {:error, :not_found}
    end
  end

  def attach_to_user(%Scope{}, _token), do: {:error, :not_found}

  @doc """
  Returns the owner's most recent idea that has not yet been turned into a
  company, or `nil`.
  """
  @spec latest_unclaimed_for_user(%Scope{}) :: Idea.t() | nil
  def latest_unclaimed_for_user(%Scope{user: %{id: user_id}}) do
    from(i in Idea, as: :idea)
    |> where([idea: i], i.user_id == ^user_id and is_nil(i.claimed_at))
    |> order_by([idea: i], desc: i.inserted_at, desc: i.id)
    |> limit(1)
    |> Repo.one()
  end

  defp draft_by_token_query(token) do
    from(i in Idea, as: :idea)
    |> where([idea: i], i.token == ^token and is_nil(i.user_id))
  end

  defp generate_token do
    @token_bytes
    |> :crypto.strong_rand_bytes()
    |> Base.url_encode64(padding: false)
  end
end
