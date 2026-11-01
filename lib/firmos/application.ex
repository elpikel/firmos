defmodule Firmos.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      FirmosWeb.Telemetry,
      Firmos.Repo,
      {DNSCluster, query: Application.get_env(:firmos, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Firmos.PubSub},
      # Start a worker by calling: Firmos.Worker.start_link(arg)
      # {Firmos.Worker, arg},
      # Start to serve requests, typically the last entry
      FirmosWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Firmos.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    FirmosWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
