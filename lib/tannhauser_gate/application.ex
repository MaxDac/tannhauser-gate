defmodule TannhauserGate.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      TannhauserGateWeb.Telemetry,
      TannhauserGate.Repo,
      {DNSCluster, query: Application.get_env(:tannhauser_gate, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: TannhauserGate.PubSub},
      # Start a worker by calling: TannhauserGate.Worker.start_link(arg)
      # {TannhauserGate.Worker, arg},
      # Start to serve requests, typically the last entry
      TannhauserGateWeb.Endpoint
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: TannhauserGate.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    TannhauserGateWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
