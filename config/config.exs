# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :firmos, :scopes,
  user: [
    default: true,
    module: Firmos.Accounts.Scope,
    assign_key: :current_scope,
    access_path: [:user, :id],
    schema_key: :user_id,
    schema_type: :id,
    schema_table: :users,
    test_data_fixture: Firmos.AccountsFixtures,
    test_setup_helper: :register_and_log_in_user
  ]

config :firmos,
  ecto_repos: [Firmos.Repo],
  generators: [timestamp_type: :utc_datetime]

# The UI is Polish-first. English msgids stay the source, so any message
# without a Polish translation falls back to English.
config :firmos, FirmosWeb.Gettext, default_locale: "pl"

# AI provider. The adapter is resolved at call time; the API key is set in
# config/runtime.exs.
config :firmos, Firmos.AI, adapter: Firmos.AI.Claude

config :firmos, Firmos.AI.Claude,
  base_url: "https://api.anthropic.com",
  model: "claude-sonnet-5-5",
  max_tokens: 16_000,
  # Non-streaming: the timeout caps the whole generation (16k tokens incl. thinking can exceed 2 min).
  receive_timeout: 600_000,
  retry: true,
  max_retries: 2

# Background jobs (Postgres engine). `ai` runs plan generation; Lifeline
# resumes jobs orphaned by a crashed node, Pruner trims finished ones (#17).
#
# Lifeline treats any job `executing` longer than `rescue_after` as orphaned,
# so it must outlast a live AI call: worst case is receive_timeout 600s ×
# (max_retries 2 + 1) = 30 min plus Req's backoff (seconds). 45 min leaves a
# margin; `Firmos.Plans` calls a plan stalled only after 120 min, past this
# window plus a resumed attempt.
config :firmos, Oban,
  engine: Oban.Engines.Basic,
  repo: Firmos.Repo,
  queues: [ai: 5],
  plugins: [Oban.Plugins.Pruner, {Oban.Plugins.Lifeline, rescue_after: :timer.minutes(45)}]

# Published sites are served on `<slug>.<sites_base_domain>`
# (FirmosWeb.Plugs.SiteHost, #19). `localhost` in dev and test, so a site is
# at http://piekarnia.localhost:4000; prod sets it in config/runtime.exs.
config :firmos, :sites_base_domain, "localhost"

# Configure the endpoint
config :firmos, FirmosWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: FirmosWeb.ErrorHTML, json: FirmosWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Firmos.PubSub,
  live_view: [signing_salt: "Iy/NJoZn"]

# Configure the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :firmos, Firmos.Mailer, adapter: Swoosh.Adapters.Local

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  firmos: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.1.12",
  firmos: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Keep secrets out of request/event logs. Matching is by substring, so "idea"
# also covers the `?idea=<token>` draft capability and the idea form (#15).
config :phoenix, :filter_parameters, ["password", "idea"]

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
