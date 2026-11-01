import Config

# Only in tests, remove the complexity from the password hashing algorithm
config :bcrypt_elixir, :log_rounds, 1

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :firmos, Firmos.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "firmos_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :firmos, FirmosWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "D6rSLbeLFQYAyGVtWXitjjUzCgLqXtS4OEv/8KXJFEEw6gTDxiEpI46J4bEGAVKp",
  server: false

# In test we don't send emails
config :firmos, Firmos.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# AI never touches the network in test: features get the Mox mock, and the
# Claude adapter's own tests go through Req.Test stubs with retries off.
config :firmos, Firmos.AI, adapter: Firmos.AI.Mock

config :firmos, Firmos.AI.Claude,
  api_key: "test-anthropic-key",
  retry: false,
  req_options: [plug: {Req.Test, Firmos.AI.Claude}]

# Jobs are only inserted; tests run them with Oban.Testing / drain_queue in
# the test process (so Mox expectations apply).
config :firmos, Oban, testing: :manual

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true
