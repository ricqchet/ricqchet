defmodule Ricqchet.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl Application
  def start(_type, _args) do
    children =
      [
        RicqchetWeb.Telemetry,
        Ricqchet.Repo,
        {DNSCluster, query: Application.get_env(:ricqchet, :dns_cluster_query) || :ignore},
        {Phoenix.PubSub, name: Ricqchet.PubSub},
        {Oban, Application.fetch_env!(:ricqchet, Oban)}
      ]
      |> Enum.concat(dispatcher_child())
      |> Enum.concat(batch_dispatcher_child())
      |> Enum.concat([RicqchetWeb.Endpoint])

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Ricqchet.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp dispatcher_child do
    if Application.get_env(:ricqchet, :dispatcher_enabled, true) do
      [Ricqchet.Dispatcher]
    else
      []
    end
  end

  defp batch_dispatcher_child do
    if Application.get_env(:ricqchet, :batch_dispatcher_enabled, true) do
      [Ricqchet.BatchDispatcher]
    else
      []
    end
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl Application
  def config_change(changed, _new, removed) do
    RicqchetWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
