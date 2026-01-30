defmodule Relay.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children =
      [
        RelayWeb.Telemetry,
        Relay.Repo,
        {DNSCluster, query: Application.get_env(:relay, :dns_cluster_query) || :ignore},
        {Phoenix.PubSub, name: Relay.PubSub},
        {Oban, Application.fetch_env!(:relay, Oban)}
      ] ++
        dispatcher_child() ++
        [
          # Start to serve requests, typically the last entry
          RelayWeb.Endpoint
        ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Relay.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp dispatcher_child do
    if Application.get_env(:relay, :dispatcher_enabled, true) do
      [Relay.Dispatcher]
    else
      []
    end
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    RelayWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
