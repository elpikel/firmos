defmodule Firmos.Approvals do
  @moduledoc """
  The owner's approval queue: agents ask before acting outside the plan,
  and nothing happens until the owner approves.

  Today the one kind of request is publishing a site version. A company
  has at most one pending request per kind; a new request supersedes the
  previous one.

  A pending request is OUTDATED, a derived state, once its version is no
  longer the site's current version or is already the published one (the
  owner edited, undid, regenerated or published in the meantime).
  `Firmos.Sites` knows nothing about approvals: `list_pending/2` and
  `count_pending/2` leave outdated requests out, `list_decided/2` shows
  them with the decided ones, and `approve/2` / `reject/2` refuse them
  with `:outdated` (marking them superseded).

  ## Agents (STORY-012/015)

  Call `request_publish/2` inside the transaction that stores the new
  version, under the site's row lock, so the version can't move between
  the two; it doesn't broadcast. After that transaction commits, call
  `broadcast_updated/1`, so open pages reload and see the committed
  request.

  ## The owner

  The owner decides with `approve/2` and `reject/2` (scoped). Approving
  publishes the version through `Firmos.Sites.publish_version/4`, under
  the site's row lock. Every request and decision is recorded in the
  activity log; decisions are broadcast on the company's approvals topic
  (see `subscribe/2`) after they commit. Pages also follow the site topic
  (`Firmos.Sites.subscribe/2`), since a site change can outdate a request.
  """
  import Ecto.Query, warn: false

  alias Firmos.Accounts.Scope
  alias Firmos.Activity
  alias Firmos.Approvals.Approval
  alias Firmos.Companies.Company
  alias Firmos.Repo
  alias Firmos.Sites
  alias Firmos.Sites.Version

  @decided_limit 20

  @typedoc "The message `subscribe/2` delivers after the company's queue changes."
  @type update_message :: {:approvals_updated, %{company_id: integer()}}

  @typedoc "Why a decision was refused."
  @type decision_error :: :not_found | :outdated | :already_decided

  @doc """
  Subscribes the caller to `t:update_message/0`s about the company's
  queue. Raises `FunctionClauseError` for a company the scope doesn't own.
  """
  @spec subscribe(%Scope{}, Company.t()) :: :ok | {:error, term()}
  def subscribe(%Scope{user: %{id: user_id}}, %Company{id: company_id, user_id: user_id}) do
    Phoenix.PubSub.subscribe(Firmos.PubSub, topic(company_id))
  end

  @doc "Stops the caller's `subscribe/2` updates for the company."
  @spec unsubscribe(%Scope{}, Company.t()) :: :ok
  def unsubscribe(%Scope{user: %{id: user_id}}, %Company{id: company_id, user_id: user_id}) do
    Phoenix.PubSub.unsubscribe(Firmos.PubSub, topic(company_id))
  end

  @doc """
  Queues an agent's request to publish `version` of the company's site.

  In one transaction (the caller's, when there is one): supersedes the
  company's pending publish request, inserts a pending one for `version`
  and records `approval_requested` (by the agent, subject the version).
  Doesn't broadcast: call `broadcast_updated/1` after the commit.

  Unscoped: for agents and server code only, never with user input.
  Refused for a version of another company's site (`:not_found`), a
  version that is not the site's current one (`:outdated`: it could never
  be approved) and the version already published (`:already_published`).
  """
  @spec request_publish(Company.t(), Version.t()) ::
          {:ok, Approval.t()}
          | {:error, :not_found | :outdated | :already_published | Ecto.Changeset.t()}
  def request_publish(%Company{id: company_id} = company, %Version{id: version_id} = version)
      when is_integer(version_id) do
    Repo.transact(fn ->
      with :ok <- ensure_current_version(company, version),
           :ok <- supersede_pending(company_id, :publish_site_version),
           {:ok, approval} <-
             company_id
             |> Approval.publish_request_changeset(version_id)
             |> Repo.insert(),
           {:ok, _entry} <-
             Activity.record(company, :agent, :approval_requested,
               subject: {"site_version", version_id},
               metadata: %{"version" => version.number}
             ) do
        {:ok, approval}
      end
    end)
  end

  @doc """
  Tells the company's open pages that its queue changed. Agents call it
  after the transaction that ran `request_publish/2` commits.
  """
  @spec broadcast_updated(integer()) :: :ok
  def broadcast_updated(company_id) when is_integer(company_id) do
    # The local PubSub adapter always answers :ok; anything else is a bug.
    :ok =
      Phoenix.PubSub.broadcast(
        Firmos.PubSub,
        topic(company_id),
        {:approvals_updated, %{company_id: company_id}}
      )
  end

  # Read in the caller's transaction, so a caller holding the site's lock
  # sees its own new version.
  defp ensure_current_version(%Company{id: company_id}, %Version{id: version_id} = version) do
    case Repo.preload(version, :site, force: true) do
      %Version{site: %{company_id: ^company_id, published_version_id: ^version_id}} ->
        {:error, :already_published}

      %Version{site: %{company_id: ^company_id, current_version_id: ^version_id}} ->
        :ok

      %Version{site: %{company_id: ^company_id}} ->
        {:error, :outdated}

      %Version{} ->
        {:error, :not_found}
    end
  end

  # A new request takes the pending slot (one per company and kind).
  defp supersede_pending(company_id, kind) do
    {_count, nil} =
      from(a in Approval, as: :approval)
      |> where([approval: a], a.company_id == ^company_id and a.kind == ^kind)
      |> where([approval: a], a.status == :pending)
      |> Repo.update_all(set: [status: :superseded, decided_at: now(), updated_at: now()])

    :ok
  end

  @doc """
  Approves the owner's pending request and publishes its site version.

  Through `Firmos.Sites.publish_version/4`, under the site's row lock and
  in one transaction: the request is re-read and must still be pending and
  not outdated, becomes `approved` (by the owner, now) with
  `approval_approved` recorded, and its version is published
  (`site_published`, undoable as usual).

  Refused for another owner's request (`:not_found`), a request that was
  already decided (`:already_decided`) and one that no longer applies
  (`:outdated`: superseded, or outdated, after which it is marked
  superseded); `:no_slug` when the site has no address yet.
  """
  @spec approve(%Scope{}, Approval.t()) ::
          {:ok, Approval.t()}
          | {:error, decision_error() | :no_slug | Ecto.Changeset.t()}
  def approve(%Scope{} = scope, %Approval{id: id}) when is_integer(id) do
    with {:ok, approval} <- get_approval(scope, id) do
      scope
      |> Sites.publish_version(approval.company, approval.site_version_id, fn _site ->
        decide(scope, id, :approved)
      end)
      |> after_approve(scope, approval)
    end
  end

  defp after_approve({:ok, _site}, scope, approval) do
    broadcast_updated(approval.company_id)
    get_approval(scope, approval.id)
  end

  defp after_approve({:error, :outdated}, _scope, approval), do: retire(approval)

  defp after_approve({:error, :slug_required}, _scope, _approval), do: {:error, :no_slug}
  defp after_approve({:error, :no_content}, _scope, _approval), do: {:error, :outdated}
  defp after_approve(error, _scope, _approval), do: error

  # An outdated request can't be decided; it is stored as superseded (if
  # still pending) once the owner tried. Runs after the decision's
  # transaction rolled back.
  defp retire(%Approval{id: id}) do
    from(a in Approval, as: :approval, select: a.company_id)
    |> where([approval: a], a.id == ^id and a.status == :pending)
    |> Repo.update_all(set: [status: :superseded, decided_at: now(), updated_at: now()])
    |> case do
      {1, [company_id]} -> broadcast_updated(company_id)
      {0, []} -> :ok
    end

    {:error, :outdated}
  end

  @doc """
  Rejects the owner's pending request: it becomes `rejected` (by the
  owner, now), `approval_rejected` is recorded and nothing is published.
  Refused like `approve/2`.
  """
  @spec reject(%Scope{}, Approval.t()) ::
          {:ok, Approval.t()} | {:error, decision_error() | Ecto.Changeset.t()}
  def reject(%Scope{} = scope, %Approval{id: id} = approval) when is_integer(id) do
    case Repo.transact(fn -> decide(scope, id, :rejected) end) do
      {:ok, rejected} ->
        broadcast_updated(rejected.company_id)
        {:ok, rejected}

      {:error, :outdated} ->
        retire(approval)

      error ->
        error
    end
  end

  # Runs in the caller's transaction (under the site's lock for an
  # approval), so the request can't be decided twice.
  defp decide(scope, id, decision) do
    with {:ok, approval} <- lock_approval(scope, id),
         :ok <- ensure_pending(approval),
         :ok <- ensure_applies(approval),
         {:ok, decided} <-
           approval |> Approval.decide_changeset(decision, scope.user.id) |> Repo.update(),
         {:ok, _entry} <-
           Activity.record(approval.company, scope, decision_action(decision),
             subject: {"site_version", approval.site_version_id},
             metadata: %{"version" => approval.site_version.number}
           ) do
      {:ok, decided}
    end
  end

  defp decision_action(:approved), do: :approval_approved
  defp decision_action(:rejected), do: :approval_rejected

  defp ensure_pending(%Approval{status: :pending}), do: :ok
  defp ensure_pending(%Approval{status: :superseded}), do: {:error, :outdated}
  defp ensure_pending(%Approval{}), do: {:error, :already_decided}

  # The derived outdated state (see the moduledoc), read from the site as
  # loaded under the caller's lock.
  defp ensure_applies(%Approval{site_version_id: version_id, site_version: %{site: site}}) do
    if site.current_version_id == version_id and site.published_version_id != version_id,
      do: :ok,
      else: {:error, :outdated}
  end

  # Locks only the approval row: ownership is checked through a subquery,
  # not a join, so no company row is locked here.
  defp lock_approval(%Scope{user: %{id: user_id}}, id) do
    owned_company_ids =
      from(c in Company, as: :company, where: c.user_id == ^user_id, select: c.id)

    from(a in Approval, as: :approval, lock: "FOR UPDATE")
    |> where([approval: a], a.id == ^id)
    |> where([approval: a], a.company_id in subquery(owned_company_ids))
    |> Repo.one()
    |> case do
      nil -> {:error, :not_found}
      approval -> {:ok, Repo.preload(approval, [:company, site_version: :site])}
    end
  end

  @doc """
  The owner's request `id` with its company and site version, or
  `{:error, :not_found}` for another owner's (or an unknown) id.
  """
  @spec get_approval(%Scope{}, integer()) :: {:ok, Approval.t()} | {:error, :not_found}
  def get_approval(%Scope{} = scope, id) when is_integer(id) do
    scope
    |> owned_approvals()
    |> where([approval: a], a.id == ^id)
    |> fetch_one()
  end

  @doc """
  The company's pending requests that still apply (not outdated), oldest
  first, with their site versions.
  """
  @spec list_pending(%Scope{}, Company.t()) :: [Approval.t()]
  def list_pending(%Scope{user: %{id: user_id}} = scope, %Company{user_id: user_id} = company) do
    scope
    |> company_approvals(company)
    |> where_open()
    |> order_by([approval: a], asc: a.inserted_at, asc: a.id)
    |> Repo.all()
  end

  @doc """
  The company's #{@decided_limit} latest requests that are no longer open,
  newest first: decided, superseded and outdated ones (an outdated request
  is still `pending`).
  """
  @spec list_decided(%Scope{}, Company.t()) :: [Approval.t()]
  def list_decided(%Scope{user: %{id: user_id}} = scope, %Company{user_id: user_id} = company) do
    scope
    |> company_approvals(company)
    |> where(^dynamic(not (^open_condition())))
    |> order_by([approval: a], desc: coalesce(a.decided_at, a.updated_at), desc: a.id)
    |> limit(@decided_limit)
    |> Repo.all()
  end

  @doc "How many requests wait for the owner's decision (outdated ones don't)."
  @spec count_pending(%Scope{}, Company.t()) :: non_neg_integer()
  def count_pending(%Scope{user: %{id: user_id}} = scope, %Company{user_id: user_id} = company) do
    scope
    |> company_approvals(company)
    |> where_open()
    |> exclude(:preload)
    |> select([approval: a], count(a.id))
    |> Repo.one!()
  end

  defp company_approvals(scope, %Company{id: company_id}) do
    scope
    |> owned_approvals()
    |> where([approval: a], a.company_id == ^company_id)
  end

  defp where_open(query), do: where(query, ^open_condition())

  # Pending, and its version is the site's current, unpublished one.
  defp open_condition do
    dynamic(
      [approval: a, site: s],
      a.status == :pending and s.current_version_id == a.site_version_id and
        (is_nil(s.published_version_id) or s.published_version_id != a.site_version_id)
    )
  end

  defp owned_approvals(%Scope{user: %{id: user_id}}) do
    from(a in Approval, as: :approval)
    |> join(:inner, [approval: a], c in assoc(a, :company), as: :company)
    |> where([company: c], c.user_id == ^user_id)
    |> join(:left, [approval: a], v in assoc(a, :site_version), as: :site_version)
    |> join(:left, [site_version: v], s in assoc(v, :site), as: :site)
    |> preload([company: c, site_version: v, site: s], company: c, site_version: {v, site: s})
  end

  defp fetch_one(query) do
    case Repo.one(query) do
      nil -> {:error, :not_found}
      approval -> {:ok, approval}
    end
  end

  defp topic(company_id), do: "company:#{company_id}:approvals"

  defp now, do: DateTime.utc_now(:second)
end
