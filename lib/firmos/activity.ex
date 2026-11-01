defmodule Firmos.Activity do
  @moduledoc """
  The activity log: an immutable record of every action taken on a company,
  by its owner, an AI agent or the system.

  `record/4` is the one write API. It is a plain insert that the caller runs
  inside the same `Repo.transact` as the change it describes, so an entry
  commits or rolls back with that change.

  `list_for_company/3` reads an owner's log a page at a time, newest first.
  """
  import Ecto.Query, warn: false

  alias Firmos.Accounts.Scope
  alias Firmos.Activity.Entry
  alias Firmos.Companies.Company
  alias Firmos.Repo

  @typedoc """
  Who acted: an owner (their scope), an AI agent or the system.
  """
  @type actor :: %Scope{} | :agent | :system

  @typedoc """
  * `:metadata` - JSON-encodable details, e.g.
    `%{"changes" => %{"name" => %{"from" => "A", "to" => "B"}}}`. Keys are
    stored as strings.
  * `:subject` - `{type, id}` of the thing the entry is about, e.g.
    `{"site_version", 42}`.
  """
  @type record_opt :: {:metadata, map()} | {:subject, {String.t(), integer()}}

  @doc """
  Records `action` on `company` by `actor`.

  An owner actor must own the company (a `FunctionClauseError` otherwise).
  Call it inside the transaction that makes the change.
  """
  @spec record(Company.t(), actor(), Entry.action(), [record_opt()]) ::
          {:ok, Entry.t()} | {:error, Ecto.Changeset.t()}
  def record(company, actor, action, opts \\ [])

  def record(%Company{user_id: user_id} = company, %Scope{user: %{id: user_id}}, action, opts) do
    insert(company, %{actor: :owner, actor_user_id: user_id}, action, opts)
  end

  def record(%Company{} = company, actor, action, opts) when actor in [:agent, :system] do
    insert(company, %{actor: actor}, action, opts)
  end

  defp insert(%Company{id: company_id}, actor_attrs, action, opts) do
    {subject_type, subject_id} = Keyword.get(opts, :subject, {nil, nil})

    attrs =
      Map.merge(actor_attrs, %{
        company_id: company_id,
        action: action,
        metadata: opts |> Keyword.get(:metadata, %{}) |> stringify_keys(),
        subject_type: subject_type,
        subject_id: subject_id
      })

    %Entry{}
    |> Entry.changeset(attrs)
    |> Repo.insert()
  end

  # Round-trips through JSON so the returned entry matches what a later read
  # loads from the jsonb column (string keys, JSON values).
  defp stringify_keys(metadata) when is_map(metadata) do
    metadata |> Jason.encode!() |> Jason.decode!()
  end

  @default_limit 50

  @typedoc """
  A position in a company's log: the `{inserted_at, id}` of the last entry
  read. Pass it as `:before` to read the next (older) page, or as `:after`
  to read what was logged since.
  """
  @type cursor :: {DateTime.t(), integer()}

  @typedoc """
  * `:limit` - at most this many entries (default #{@default_limit}).
  * `:before` - only entries older than this `t:cursor/0`.
  * `:after` - only entries newer than this `t:cursor/0`.
  """
  @type list_opt ::
          {:limit, pos_integer()} | {:before, cursor()} | {:after, cursor()}

  @doc """
  Returns a page of the company's activity entries, newest first, using a
  keyset (`inserted_at`, `id`) cursor on the `(company_id, inserted_at DESC,
  id DESC)` index.

  Raises `FunctionClauseError` for a company the scope doesn't own; the query
  is also filtered by the owner, so a forged struct reads nothing.
  """
  @spec list_for_company(%Scope{}, Company.t(), [list_opt()]) :: [Entry.t()]
  def list_for_company(
        %Scope{user: %{id: user_id}} = scope,
        %Company{user_id: user_id} = company,
        opts \\ []
      ) do
    scope
    |> owned_entries(company)
    |> before(Keyword.get(opts, :before))
    |> since(Keyword.get(opts, :after))
    |> order_by([entry: e], desc: e.inserted_at, desc: e.id)
    |> limit(^Keyword.get(opts, :limit, @default_limit))
    |> Repo.all()
  end

  @doc """
  The company's newest entry (in log order) whose action is one of
  `actions`, or `nil`; with `before: cursor`, the newest one older than that
  `t:cursor/0`. Raises `FunctionClauseError` for a company the scope doesn't
  own; the query is also filtered by the owner.
  """
  @spec latest_for_company(%Scope{}, Company.t(), [Entry.action(), ...], before: cursor()) ::
          Entry.t() | nil
  def latest_for_company(
        %Scope{user: %{id: user_id}} = scope,
        %Company{user_id: user_id} = company,
        [_ | _] = actions,
        opts \\ []
      ) do
    scope
    |> owned_entries(company)
    |> where([entry: e], e.action in ^actions)
    |> before(Keyword.get(opts, :before))
    |> order_by([entry: e], desc: e.inserted_at, desc: e.id)
    |> limit(1)
    |> Repo.one()
  end

  @doc """
  The company's entry `id`, or `{:error, :not_found}` when it belongs to
  another company (or doesn't exist). Raises `FunctionClauseError` for a
  company the scope doesn't own.
  """
  @spec fetch_entry(%Scope{}, Company.t(), integer()) ::
          {:ok, Entry.t()} | {:error, :not_found}
  def fetch_entry(%Scope{user: %{id: user_id}} = scope, %Company{user_id: user_id} = company, id)
      when is_integer(id) do
    scope
    |> owned_entries(company)
    |> where([entry: e], e.id == ^id)
    |> Repo.one()
    |> case do
      nil -> {:error, :not_found}
      entry -> {:ok, entry}
    end
  end

  defp owned_entries(%Scope{user: %{id: user_id}}, %Company{id: company_id}) do
    from(e in Entry, as: :entry)
    |> join(:inner, [entry: e], c in assoc(e, :company), as: :company)
    |> where([entry: e], e.company_id == ^company_id)
    |> where([company: c], c.user_id == ^user_id)
  end

  @doc """
  The id of `entry`'s subject when it is of `type` (e.g. `"site_version"`),
  else `nil`.
  """
  @spec subject_id(Entry.t(), String.t()) :: integer() | nil
  def subject_id(%Entry{subject_type: type, subject_id: id}, type) when is_integer(id), do: id
  def subject_id(%Entry{}, _type), do: nil

  @doc "The cursor pointing just after `entry`, for `list_for_company/3`."
  @spec cursor(Entry.t()) :: cursor()
  def cursor(%Entry{inserted_at: %DateTime{} = inserted_at, id: id}), do: {inserted_at, id}

  defp before(query, nil), do: query

  # Row comparison matches the index order; the cast keeps the parameter a
  # plain timestamp like the column (no session time zone involved).
  defp before(query, {%DateTime{} = inserted_at, id}) when is_integer(id) do
    where(
      query,
      [entry: e],
      fragment(
        "(?, ?) < (?, ?)",
        e.inserted_at,
        e.id,
        type(^inserted_at, :utc_datetime),
        type(^id, :id)
      )
    )
  end

  defp since(query, nil), do: query

  defp since(query, {%DateTime{} = inserted_at, id}) when is_integer(id) do
    where(
      query,
      [entry: e],
      fragment(
        "(?, ?) > (?, ?)",
        e.inserted_at,
        e.id,
        type(^inserted_at, :utc_datetime),
        type(^id, :id)
      )
    )
  end
end
