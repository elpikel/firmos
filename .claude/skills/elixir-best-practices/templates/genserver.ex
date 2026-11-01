defmodule Firmos.RateLimiter do
  @moduledoc """
  Fixed-window rate limiter — a legitimate process: shared mutable state
  across requests (otp.md §1).

  Start it under the application supervisor:

      # lib/firmos/application.ex
      children = [
        ...,
        {Firmos.RateLimiter, limit: 100, window_ms: 60_000},
        FirmosWeb.Endpoint
      ]

  Test with `start_supervised!({Firmos.RateLimiter, name: :test_limiter, limit: 2})`
  and the client API — never `Process.sleep/1` (AGENTS.md).
  For high read volume, swap the map state for an ETS table owned by this process.
  """

  use GenServer

  @type key :: term()
  @type option :: {:name, GenServer.name()} | {:limit, pos_integer()} | {:window_ms, pos_integer()}

  # -- Client API -----------------------------------------------------------

  @spec start_link([option()]) :: GenServer.on_start()
  def start_link(opts) do
    {name, opts} = Keyword.pop(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc "Records a hit for `key`; `{:error, :rate_limited}` once over the limit."
  @spec hit(GenServer.server(), key()) :: :ok | {:error, :rate_limited}
  def hit(server \\ __MODULE__, key), do: GenServer.call(server, {:hit, key})

  # -- Server callbacks -----------------------------------------------------

  @impl GenServer
  def init(opts) do
    state = %{
      limit: Keyword.get(opts, :limit, 100),
      window_ms: Keyword.get(opts, :window_ms, 60_000),
      counts: %{}
    }

    # Keep init/1 fast; schedule periodic work instead of doing it here.
    {:ok, state, {:continue, :schedule_reset}}
  end

  @impl GenServer
  def handle_continue(:schedule_reset, state) do
    Process.send_after(self(), :reset, state.window_ms)
    {:noreply, state}
  end

  @impl GenServer
  def handle_call({:hit, key}, _from, %{counts: counts, limit: limit} = state) do
    count = Map.get(counts, key, 0)

    if count < limit do
      {:reply, :ok, %{state | counts: Map.put(counts, key, count + 1)}}
    else
      {:reply, {:error, :rate_limited}, state}
    end
  end

  @impl GenServer
  def handle_info(:reset, state) do
    {:noreply, %{state | counts: %{}}, {:continue, :schedule_reset}}
  end
end
