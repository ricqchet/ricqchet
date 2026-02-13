defmodule RicqchetWeb.ChannelNamespaceJSON do
  @moduledoc """
  JSON views for channel namespace endpoints.
  """

  def render("index.json", %{namespaces: namespaces}) do
    %{data: Enum.map(namespaces, &namespace_data/1)}
  end

  def render("show.json", %{namespace: namespace}) do
    %{data: namespace_data(namespace)}
  end

  defp namespace_data(namespace) do
    %{
      id: namespace.id,
      pattern: namespace.pattern,
      priority: namespace.priority,
      history_enabled: namespace.history_enabled,
      history_ttl_seconds: namespace.history_ttl_seconds,
      history_max_events: namespace.history_max_events,
      cache_enabled: namespace.cache_enabled,
      max_members: namespace.max_members,
      max_event_size_bytes: namespace.max_event_size_bytes,
      max_client_events_per_second: namespace.max_client_events_per_second,
      auth_endpoint: namespace.auth_endpoint,
      webhook_url: namespace.webhook_url,
      inserted_at: namespace.inserted_at,
      updated_at: namespace.updated_at
    }
  end
end
