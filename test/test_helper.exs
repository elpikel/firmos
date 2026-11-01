ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(Firmos.Repo, :manual)

Mox.defmock(Firmos.AI.Mock, for: Firmos.AI)
