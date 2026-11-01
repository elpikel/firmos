defmodule Firmos.Sites.GenerateWorker do
  @moduledoc """
  Generates one landing page version in the background (queue `ai`). All
  the work lives in `Firmos.Sites.generate_site/3`; this module only maps
  its result to an Oban outcome.

  Retries and uniqueness follow `Firmos.Plans.GenerateWorker`: a failed AI
  call or invalid reply is stored on the site as `failed` and the job is
  cancelled (the owner's "try again" is the retry); `max_attempts: 2` only
  lets Lifeline resume a job orphaned by a crashed node, and a final attempt
  that can't store its result marks the site failed. One waiting job per
  site; `executing` is not a unique state, so a retry right after a failure
  still enqueues, and claiming is a conditional update.
  """
  use Oban.Worker,
    queue: :ai,
    max_attempts: 2,
    unique: [keys: [:site_id], states: [:available, :scheduled, :retryable], period: :infinity]

  alias Firmos.Sites

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"site_id" => site_id}} = job) when is_integer(site_id) do
    final? = job.attempt >= job.max_attempts

    case Sites.generate_site(site_id, job.id, resume: job.attempt > 1) do
      {:ok, _version} -> :ok
      {:error, :not_claimable} -> :ok
      {:error, {:generation_failed, code}} -> {:cancel, code}
      {:error, %Ecto.Changeset{}} when final? -> give_up(site_id, job.id, "not_stored")
      {:error, %Ecto.Changeset{}} -> {:error, :site_not_stored}
    end
  rescue
    # Not a silenced failure: on the final attempt the site is marked failed
    # (so the owner can try again) and the exception is re-raised for Oban.
    exception ->
      if job.attempt >= job.max_attempts, do: give_up(site_id, job.id, "crashed")
      reraise exception, __STACKTRACE__
  end

  # `{:error, :not_found}` means this job no longer holds the generation.
  defp give_up(site_id, job_id, code) do
    case Sites.mark_failed(site_id, job_id, code) do
      {:ok, _site} -> {:cancel, code}
      {:error, :not_found} -> {:cancel, code}
    end
  end
end
