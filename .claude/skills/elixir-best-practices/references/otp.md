# OTP essentials — processes for runtime concerns only

## §1 When NOT to use a process

A process is a unit of **runtime**: it owns state over time, runs
concurrently, or fails in isolation. It is not a unit of **code
organization** — that is what modules and functions are for.

```elixir
# ❌ bad — a GenServer wrapping pure functions; every call is now
# serialized through one mailbox (a bottleneck) for no benefit
defmodule Firmos.PriceCalculator do
  use GenServer
  def total(items), do: GenServer.call(__MODULE__, {:total, items})
  def handle_call({:total, items}, _from, s), do: {:reply, sum(items), s}
end
```

```elixir
# ✅ idiomatic — a plain module
defmodule Firmos.Carts.Pricing do
  @spec total([LineItem.t()]) :: non_neg_integer()
  def total(items), do: Enum.reduce(items, 0, &(&1.quantity * &1.unit_price + &2))
end
```

Use a process only if you can name the runtime property you need:

| Need | Tool |
|---|---|
| Mutable state shared across requests (cache, counter, rate limit) | `GenServer` / `Agent`; ETS for read-heavy |
| Do N things concurrently and collect results | `Task.async_stream` |
| Background work that must not crash the caller | `Task.Supervisor.start_child` |
| One process per runtime entity (game room, upload session) | `DynamicSupervisor` + `Registry` |
| Isolate a flaky dependency so its crash doesn't spread | Its own supervised process |
| Periodic job | `GenServer` with `Process.send_after/3` (or a job library) |
| Persistent data | **The database**, not a process |

LiveView processes and Phoenix request processes already give you
per-user concurrency and isolation — don't add another process to "make
it async".

## §2 GenServer essentials

See `templates/genserver.ex`. The rules:

- **Client API and server callbacks in the same module**; callers use
  the client functions (`Counter.increment/1`), never `GenServer.call`
  directly.
- **Always started under a supervisor** (add to the `children` list in
  `Firmos.Application`). Never `start_link` from a request or LiveView.
- Keep `init/1` fast — do slow setup in `handle_continue/2`.
- `call` when the caller needs a reply or back-pressure; `cast` only for
  true fire-and-forget. Default `call` timeout is 5s — set it explicitly
  when work is slow.
- Keep state small and the callbacks short. A long `handle_call` blocks
  every other caller.
- Name with `name: __MODULE__` for singletons; with a `Registry` via
  tuple for many instances.

## §3 Supervision, Registry, DynamicSupervisor

```elixir
# lib/firmos/application.ex
children = [
  Firmos.Repo,
  {Registry, keys: :unique, name: Firmos.RoomRegistry},
  {DynamicSupervisor, name: Firmos.RoomSupervisor, strategy: :one_for_one},
  {Task.Supervisor, name: Firmos.TaskSupervisor},
  Firmos.RateLimiter,
  FirmosWeb.Endpoint
]
```

```elixir
# start a per-entity process
def start_room(id) do
  DynamicSupervisor.start_child(Firmos.RoomSupervisor, {Firmos.Room, id: id})
end

# in Firmos.Room
def start_link(opts) do
  id = Keyword.fetch!(opts, :id)
  GenServer.start_link(__MODULE__, opts, name: {:via, Registry, {Firmos.RoomRegistry, id}})
end
```

- Order children by dependency: things started first are stopped last.
- Pick the strategy deliberately: `:one_for_one` (independent),
  `:rest_for_one` (later children depend on earlier ones),
  `:one_for_all` (tightly coupled).
- `restart: :temporary` for processes that should not be restarted
  (e.g. a one-shot session); `:transient` to restart only on crash.
- OTP primitives need names in the child spec (AGENTS.md).

## §4 Tasks

```elixir
# concurrent map with back-pressure — results in input order
urls
|> Task.async_stream(&fetch/1, max_concurrency: 8, timeout: :infinity)
|> Enum.map(fn {:ok, result} -> result end)
```

- `timeout: :infinity` is usually right (let the inner call own its
  timeout, e.g. Req's `receive_timeout`); otherwise use
  `on_timeout: :kill_task` and handle `{:exit, :timeout}`.
- `Task.async/await` links to the caller — a crash in the task crashes
  the caller. That is correct for "I need this result".
- Fire-and-forget: `Task.Supervisor.start_child(Firmos.TaskSupervisor,
  fn -> ... end)` — unlinked, supervised, never a bare `spawn`.
- Work that must survive a deploy/restart belongs in a durable job queue,
  not a Task.

## §5 Testing processes

- Start with `start_supervised!/1` so the test cleans up (AGENTS.md).
- Synchronize with `:sys.get_state/1` or `assert_receive`, never
  `Process.sleep/1`.
- Test through the client API; keep logic in pure functions that can be
  unit-tested without a process at all.
