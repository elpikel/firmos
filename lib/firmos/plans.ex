defmodule Firmos.Plans do
  @moduledoc """
  AI business plans for companies.

  A company's plans are numbered versions; the highest version is the current
  plan. A plan is generated in the background by `Firmos.Plans.GenerateWorker`
  (Oban, queue `ai`): every function that creates or re-queues a plan inserts
  the job in the same transaction as the plan row, so a job never exists for
  a rolled-back plan.

  Owner-facing functions take the caller's `Firmos.Accounts.Scope` and only
  ever see that owner's plans. `generate_plan/2` is the worker's entry point
  and takes a bare id.

  Every status or rating change is broadcast on the company's plans topic (see
  `subscribe/2`) after it commits.
  """
  import Ecto.Query, warn: false

  alias Firmos.Accounts.Scope
  alias Firmos.Activity
  alias Firmos.AI
  alias Firmos.Companies.Company
  alias Firmos.Plans.Content
  alias Firmos.Plans.GenerateWorker
  alias Firmos.Plans.Plan
  alias Firmos.Plans.Prompt
  alias Firmos.Repo

  @in_progress [:pending, :generating]

  # A `generating` plan untouched for this long has lost its job: longer than
  # the worst-case AI call (~30 min, see Firmos.AI.Claude) plus Lifeline's
  # `rescue_after` (45 min, config.exs) and a resumed second attempt.
  @stale_after_minutes 120

  @typedoc """
  The message `subscribe/2` delivers after a plan changes.
  """
  @type update_message ::
          {:plan_updated,
           %{id: integer(), company_id: integer(), version: pos_integer(), status: Plan.status()}}

  @doc """
  Subscribes the caller to updates of the company's plans: a
  `t:update_message/0` after every status or rating change. Raises
  `FunctionClauseError` for a company the scope doesn't own.
  """
  @spec subscribe(%Scope{}, Company.t()) :: :ok | {:error, term()}
  def subscribe(%Scope{user: %{id: user_id}}, %Company{id: company_id, user_id: user_id}) do
    Phoenix.PubSub.subscribe(Firmos.PubSub, topic(company_id))
  end

  @doc """
  Creates the company's first plan (pending version 1) and enqueues its
  generation. Meant to run inside the transaction that creates the company,
  so the job exists only if the company commits. Raises
  `FunctionClauseError` for a company the scope doesn't own.
  """
  @spec start_first_plan(%Scope{}, Company.t()) :: {:ok, Plan.t()} | {:error, Ecto.Changeset.t()}
  def start_first_plan(%Scope{user: %{id: user_id}}, %Company{id: company_id, user_id: user_id}) do
    Repo.transact(fn -> insert_and_enqueue(company_id, 1) end)
  end

  @doc "The company's current (highest version) plan, or `nil`."
  @spec current_plan(%Scope{}, Company.t()) :: Plan.t() | nil
  def current_plan(%Scope{} = scope, %Company{} = company) do
    scope
    |> company_plans_query(company)
    |> limit(1)
    |> Repo.one()
  end

  @doc "All of the company's plan versions, newest first."
  @spec list_plans(%Scope{}, Company.t()) :: [Plan.t()]
  def list_plans(%Scope{} = scope, %Company{} = company) do
    scope
    |> company_plans_query(company)
    |> Repo.all()
  end

  @doc """
  Stores the owner's `:up` / `:down` rating on a ready plan.

  The plan is re-read through the scope, so only its id is trusted.
  """
  @spec rate_plan(%Scope{}, Plan.t(), Plan.rating()) ::
          {:ok, Plan.t()} | {:error, :not_found | :not_ready | Ecto.Changeset.t()}
  def rate_plan(%Scope{} = scope, %Plan{id: plan_id}, rating) when rating in [:up, :down] do
    with {:ok, plan} <- fetch_owned_plan(scope, plan_id),
         :ok <- ensure_status(plan, [:ready], :not_ready),
         {:ok, rated} <- plan |> Plan.rating_changeset(rating) |> Repo.update() do
      broadcast(rated)
      {:ok, rated}
    end
  end

  @doc """
  Whether a `generating` plan has stalled: its job died without storing a
  result (#{@stale_after_minutes} minutes without a change). A stalled plan
  can be retried or replaced like a failed one.
  """
  @spec stalled?(Plan.t()) :: boolean()
  def stalled?(%Plan{status: :generating, updated_at: %DateTime{} = updated_at}) do
    DateTime.diff(DateTime.utc_now(), updated_at, :minute) >= @stale_after_minutes
  end

  def stalled?(%Plan{}), do: false

  @doc """
  Puts the company's current plan back to pending and enqueues its generation
  again (the owner's "try again"). Only a failed or `stalled?/1` plan can be
  retried, and only the current version: an older version is kept as it is.

  The company row is locked like in `regenerate_plan/2`, so a retry and a
  regenerate (or a double click) can't race.
  """
  @spec retry_plan(%Scope{}, Plan.t()) ::
          {:ok, Plan.t()}
          | {:error, :not_found | :not_failed | :not_current | Ecto.Changeset.t()}
  def retry_plan(%Scope{} = scope, %Plan{id: plan_id, company_id: company_id}) do
    Repo.transact(fn ->
      with {:ok, company} <- lock_company(scope, company_id),
           {:ok, plan} <- fetch_owned_plan(scope, plan_id, lock: true),
           :ok <- ensure_retryable(plan),
           :ok <- ensure_current(plan, current_plan(scope, company)),
           {:ok, pending} <- plan |> Plan.pending_changeset() |> Repo.update(),
           {:ok, _job} <- enqueue(pending) do
        {:ok, pending}
      end
    end)
    |> broadcast_ok()
  end

  @doc """
  Creates the next plan version (pending) and enqueues its generation; older
  versions are kept. Records a `plan_regenerated` entry by the owner.

  The company row is locked so concurrent calls number versions in turn.
  Refused while the current plan is still pending or generating, unless it
  has `stalled?/1`.
  """
  @spec regenerate_plan(%Scope{}, Company.t()) ::
          {:ok, Plan.t()}
          | {:error, :not_found | :generation_in_progress | Ecto.Changeset.t()}
  def regenerate_plan(
        %Scope{user: %{id: user_id}} = scope,
        %Company{id: company_id, user_id: user_id}
      ) do
    Repo.transact(fn ->
      with {:ok, company} <- lock_company(scope, company_id),
           current = current_plan(scope, company),
           :ok <- ensure_not_in_progress(current),
           {:ok, plan} <- insert_and_enqueue(company.id, next_version(current)),
           {:ok, _entry} <-
             Activity.record(company, scope, :plan_regenerated,
               subject: {"plan", plan.id},
               metadata: %{"version" => plan.version}
             ) do
        {:ok, plan}
      end
    end)
    |> broadcast_ok()
  end

  @doc """
  Generates the plan `plan_id` (the worker's entry point).

  Claims the plan by moving it from `pending`/`failed` to `generating`
  (`resume: true` also takes a `generating` plan, for a job resumed after a
  crash), asks the AI for the plan and stores the result:

    * `{:ok, plan}` - stored `ready` with its content, and a
      `plan_generated` activity entry by the agent, in one transaction
    * `{:error, {:generation_failed, code}}` - the AI call failed or its reply
      was not a valid plan; stored `failed` with the safe `code`
    * `{:error, :not_claimable}` - nothing to do (unknown id, already ready,
      or another job has it)

  Blocks for as long as the AI call takes; run it only from the job.
  """
  @spec generate_plan(integer(), resume: boolean()) ::
          {:ok, Plan.t()}
          | {:error, :not_claimable | {:generation_failed, String.t()} | Ecto.Changeset.t()}
  def generate_plan(plan_id, opts \\ []) when is_integer(plan_id) do
    with {:ok, plan} <- claim(plan_id, Keyword.get(opts, :resume, false)) do
      broadcast(plan)

      case request_content(plan.company) do
        {:ok, content} -> store_ready(plan, content)
        {:error, reason} -> store_failed(plan, error_code(reason))
      end
    end
  end

  @doc """
  Marks the plan `plan_id` failed with the safe `code`, unless it is already
  ready or failed (the worker's last resort when a final attempt could not
  store its result). Unscoped, like `generate_plan/2`.
  """
  @spec mark_failed(integer(), String.t()) :: {:ok, Plan.t()} | {:error, :not_found}
  def mark_failed(plan_id, code) when is_integer(plan_id) and is_binary(code) do
    from(p in Plan, as: :plan, select: p)
    |> where([plan: p], p.id == ^plan_id and p.status in ^@in_progress)
    |> Repo.update_all(set: [status: :failed, error: code, updated_at: now()])
    |> case do
      {1, [plan]} ->
        broadcast(plan)
        {:ok, plan}

      {0, []} ->
        {:error, :not_found}
    end
  end

  defp claim(plan_id, resume?) do
    claimable = if resume?, do: [:pending, :failed, :generating], else: [:pending, :failed]

    from(p in Plan, as: :plan, select: p)
    |> where([plan: p], p.id == ^plan_id and p.status in ^claimable)
    |> Repo.update_all(set: [status: :generating, error: nil, updated_at: now()])
    |> case do
      {1, [plan]} -> {:ok, Repo.preload(plan, :company)}
      {0, []} -> {:error, :not_claimable}
    end
  end

  defp request_content(company) do
    with {:ok, text} <- company |> Prompt.for_company() |> AI.complete(system: Prompt.system()) do
      Content.from_json(text)
    end
  end

  defp store_ready(plan, content) do
    Repo.transact(fn ->
      with {:ok, ready} <- plan |> Plan.ready_changeset(content) |> Repo.update(),
           {:ok, _entry} <-
             Activity.record(plan.company, :agent, :plan_generated,
               subject: {"plan", ready.id},
               metadata: %{"version" => ready.version}
             ) do
        {:ok, ready}
      end
    end)
    |> broadcast_ok()
  end

  defp store_failed(plan, code) do
    with {:ok, failed} <- plan |> Plan.failed_changeset(code) |> Repo.update() do
      broadcast(failed)
      {:error, {:generation_failed, code}}
    end
  end

  # Only codes leave this module: provider bodies, partial text and refusal
  # details can hold anything, so none of it is stored or shown.
  defp error_code({:http_status, status, _summary}) when is_integer(status),
    do: "http_status:#{status}"

  defp error_code({:refusal, _details}), do: "refusal"
  defp error_code({:truncated, _text}), do: "truncated"
  defp error_code({:unexpected_body, _summary}), do: "unexpected_body"
  defp error_code({:missing_config, _keys}), do: "missing_config"

  defp error_code(reason)
       when reason in [
              :invalid_json,
              :invalid_shape,
              :empty_response,
              :missing_api_key,
              :timeout,
              :econnrefused,
              :closed
            ],
       do: Atom.to_string(reason)

  defp error_code(_other), do: "provider_error"

  defp insert_and_enqueue(company_id, version) do
    with {:ok, plan} <- company_id |> Plan.new_changeset(version) |> Repo.insert(),
         {:ok, _job} <- enqueue(plan) do
      {:ok, plan}
    end
  end

  defp enqueue(%Plan{id: plan_id}) do
    %{plan_id: plan_id}
    |> GenerateWorker.new()
    |> Oban.insert()
  end

  defp next_version(nil), do: 1
  defp next_version(%Plan{version: version}), do: version + 1

  defp ensure_not_in_progress(%Plan{status: status} = plan) when status in @in_progress do
    if stalled?(plan), do: :ok, else: {:error, :generation_in_progress}
  end

  defp ensure_not_in_progress(_current_or_none), do: :ok

  defp ensure_retryable(%Plan{status: :failed}), do: :ok

  defp ensure_retryable(plan) do
    if stalled?(plan), do: :ok, else: {:error, :not_failed}
  end

  defp ensure_current(%Plan{id: id}, %Plan{id: id}), do: :ok
  defp ensure_current(_plan, _current), do: {:error, :not_current}

  defp ensure_status(%Plan{status: status}, allowed, error) do
    if status in allowed, do: :ok, else: {:error, error}
  end

  defp lock_company(%Scope{user: %{id: user_id}}, company_id) do
    from(c in Company, as: :company, lock: "FOR UPDATE")
    |> where([company: c], c.id == ^company_id and c.user_id == ^user_id)
    |> Repo.one()
    |> found()
  end

  defp fetch_owned_plan(scope, plan_id, opts \\ []) do
    scope
    |> owned_plans_query()
    |> where([plan: p], p.id == ^plan_id)
    |> maybe_lock(Keyword.get(opts, :lock, false))
    |> Repo.one()
    |> found()
  end

  defp maybe_lock(query, false), do: query
  defp maybe_lock(query, true), do: lock(query, "FOR UPDATE")

  defp found(nil), do: {:error, :not_found}
  defp found(record), do: {:ok, record}

  defp company_plans_query(scope, %Company{id: company_id}) do
    scope
    |> owned_plans_query()
    |> where([plan: p], p.company_id == ^company_id)
    |> order_by([plan: p], desc: p.version)
  end

  defp owned_plans_query(%Scope{user: %{id: user_id}}) do
    from(p in Plan, as: :plan)
    |> join(:inner, [plan: p], c in assoc(p, :company), as: :company)
    |> where([company: c], c.user_id == ^user_id)
  end

  defp broadcast_ok({:ok, plan} = result) do
    broadcast(plan)
    result
  end

  defp broadcast_ok(error), do: error

  # The local PubSub adapter always answers :ok; anything else is a bug.
  defp broadcast(%Plan{} = plan) do
    :ok =
      Phoenix.PubSub.broadcast(
        Firmos.PubSub,
        topic(plan.company_id),
        {:plan_updated,
         %{id: plan.id, company_id: plan.company_id, version: plan.version, status: plan.status}}
      )
  end

  defp topic(company_id), do: "company:#{company_id}:plans"

  defp now, do: DateTime.utc_now(:second)
end
