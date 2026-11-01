defmodule Firmos.Plans.GenerateWorker do
  @moduledoc """
  Generates one business plan in the background (queue `ai`). All the work
  lives in `Firmos.Plans.generate_plan/2`; this module only maps its result
  to an Oban outcome.

  ## Retries

  A failed AI call or an invalid reply is stored on the plan as `failed` and
  the job is cancelled, never retried: `Firmos.AI.Claude` already retries
  transient errors itself, and one call can block for up to ~30 minutes, so
  the owner's "try again" is the retry. `max_attempts: 2` exists only for a
  job orphaned by a crashed node (Lifeline makes it available again): that
  second attempt may take over the plan left in `generating`. If that final
  attempt still can't store a result (a changeset error or an exception), the
  plan is marked failed so the owner can try again. A plan whose job vanished
  entirely is caught by `Firmos.Plans.stalled?/1`.

  ## Uniqueness

  One waiting job per plan. `executing` is deliberately not a unique state:
  the owner may retry a plan the moment it is stored `failed`, while its job
  is still finishing, and that retry must enqueue. Two jobs can't both work
  on a plan, because claiming it is a conditional update.
  """
  use Oban.Worker,
    queue: :ai,
    max_attempts: 2,
    unique: [keys: [:plan_id], states: [:available, :scheduled, :retryable], period: :infinity]

  alias Firmos.Plans

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"plan_id" => plan_id}} = job) when is_integer(plan_id) do
    final? = job.attempt >= job.max_attempts

    case Plans.generate_plan(plan_id, resume: job.attempt > 1) do
      {:ok, _plan} -> :ok
      {:error, :not_claimable} -> :ok
      {:error, {:generation_failed, code}} -> {:cancel, code}
      {:error, %Ecto.Changeset{}} when final? -> give_up(plan_id, "not_stored")
      {:error, %Ecto.Changeset{}} -> {:error, :plan_not_stored}
    end
  rescue
    # Not a silenced failure: on the final attempt the plan is marked failed
    # (so the owner can try again instead of watching a plan that never
    # finishes) and the exception is re-raised for Oban to record.
    exception ->
      if job.attempt >= job.max_attempts, do: give_up(plan_id, "crashed")
      reraise exception, __STACKTRACE__
  end

  # The final attempt couldn't store its result: fail the plan visibly.
  # `{:error, :not_found}` means it already left `generating` (nothing to do).
  defp give_up(plan_id, code) do
    case Plans.mark_failed(plan_id, code) do
      {:ok, _plan} -> {:cancel, code}
      {:error, :not_found} -> {:cancel, code}
    end
  end
end
