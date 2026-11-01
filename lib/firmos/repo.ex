defmodule Firmos.Repo do
  use Ecto.Repo,
    otp_app: :firmos,
    adapter: Ecto.Adapters.Postgres
end
