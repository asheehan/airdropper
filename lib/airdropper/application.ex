defmodule Airdropper.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      AirdropperWeb.Telemetry,
      Airdropper.Repo,
      {DNSCluster, query: Application.get_env(:airdropper, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Airdropper.PubSub},
      # Start the AirdropWorker GenServer (automatically named Airdropper.AirdropWorker)
      Airdropper.AirdropWorker,
      # Start to serve requests, typically the last entry
      AirdropperWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Airdropper.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    AirdropperWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
