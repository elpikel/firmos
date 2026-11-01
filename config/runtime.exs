import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/firmos start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :firmos, FirmosWeb.Endpoint, server: true
end

config :firmos, FirmosWeb.Endpoint,
  http: [port: String.to_integer(System.get_env("PORT", "4000"))]

# Anthropic API key for Firmos.AI.Claude. Required in prod; optional in
# other envs (AI calls then answer {:error, :missing_api_key}). Test never
# reads it, so no feature can reach the real API.
if config_env() == :prod do
  anthropic_api_key =
    case System.get_env("ANTHROPIC_API_KEY") do
      key when key in [nil, ""] ->
        raise """
        environment variable ANTHROPIC_API_KEY is missing.
        Create one at https://console.anthropic.com/settings/keys
        """

      key ->
        key
    end

  config :firmos, Firmos.AI.Claude, api_key: anthropic_api_key
else
  if config_env() != :test do
    config :firmos, Firmos.AI.Claude, api_key: System.get_env("ANTHROPIC_API_KEY")
  end
end

if config_env() == :prod do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  config :firmos, Firmos.Repo,
    # ssl: true,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    # For machines with several cores, consider starting multiple pools of `pool_size`
    # pool_count: 4,
    socket_options: maybe_ipv6

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"

  config :firmos, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  # Published sites live on `<slug>.<SITES_BASE_DOMAIN>` (e.g. firmos.pl);
  # the DNS needs a wildcard record for it. Defaults to the app's host.
  normalize_domain = fn domain ->
    domain |> String.trim() |> String.downcase() |> String.trim_trailing(".")
  end

  sites_base_domain =
    case normalize_domain.(System.get_env("SITES_BASE_DOMAIN", "")) do
      "" -> normalize_domain.(host)
      domain -> domain
    end

  # The app may live on the bare base domain or a platform label (www, app),
  # never on a name an owner could claim as a slug. (Kept in sync by hand
  # with Firmos.Sites.Slug: app modules aren't loaded while this file runs.)
  app_label = String.replace_suffix(normalize_domain.(host), "." <> sites_base_domain, "")

  if app_label != normalize_domain.(host) and not String.contains?(app_label, ".") and
       app_label not in ~w(www app) do
    raise """
    PHX_HOST (#{host}) is a single label under SITES_BASE_DOMAIN (#{sites_base_domain}),
    so a company could claim "#{app_label}" as its slug. Run the app on the bare
    domain or on www./app.#{sites_base_domain}, or use another SITES_BASE_DOMAIN.
    """
  end

  config :firmos, :sites_base_domain, sites_base_domain

  config :firmos, FirmosWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://hexdocs.pm/bandit/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0}
    ],
    secret_key_base: secret_key_base

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :firmos, FirmosWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://hexdocs.pm/plug/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :firmos, FirmosWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.

  # ## Configuring the mailer
  #
  # In production you need to configure the mailer to use a different adapter.
  # Here is an example configuration for Mailgun:
  #
  #     config :firmos, Firmos.Mailer,
  #       adapter: Swoosh.Adapters.Mailgun,
  #       api_key: System.get_env("MAILGUN_API_KEY"),
  #       domain: System.get_env("MAILGUN_DOMAIN")
  #
  # Most non-SMTP adapters require an API client. Swoosh supports Req, Hackney,
  # and Finch out-of-the-box. This configuration is typically done at
  # compile-time in your config/prod.exs:
  #
  #     config :swoosh, :api_client, Swoosh.ApiClient.Req
  #
  # See https://hexdocs.pm/swoosh/Swoosh.html#module-installation for details.
end
