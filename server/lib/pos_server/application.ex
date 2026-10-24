defmodule TigooServer.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      TigooServerWeb.Telemetry,
      TigooServer.Repo,
      TigooServer.Tenants,
      {Task.Supervisor, name: TigooServer.TaskSupervisor},
      {DNSCluster, query: Application.get_env(:tigoo_server, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: TigooServer.PubSub},
      TigooServerWeb.Presence,
      # Start a worker by calling: TigooServer.Worker.start_link(arg)
      # {TigooServer.Worker, arg},
      # Start to serve requests, typically the last entry
      TigooServerWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: TigooServer.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    TigooServerWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
