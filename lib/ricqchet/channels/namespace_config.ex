defmodule Ricqchet.Channels.NamespaceConfig do
  @moduledoc """
  Public API for resolving namespace configuration for a channel.

  Wraps the ETS cache with database fallback. On cache miss, queries the
  database for matching namespaces and caches the result.
  """

  alias Ricqchet.Channels.NamespaceCache
  alias Ricqchet.Channels.Namespaces

  @doc """
  Returns the matching namespace for a channel within an application.

  Checks the cache first; on miss, queries the database and caches the result.
  Returns `{:ok, namespace}` when a match is found, or `{:ok, nil}` when
  no namespace matches the channel name.
  """
  @spec get_namespace_for_channel(String.t(), String.t()) ::
          {:ok, Ricqchet.Channels.Namespace.t() | nil}
  def get_namespace_for_channel(application_id, channel_name) do
    case NamespaceCache.get(application_id, channel_name) do
      {:ok, _value} = hit ->
        hit

      :miss ->
        namespace = Namespaces.find_matching_namespace(application_id, channel_name)
        NamespaceCache.put(application_id, channel_name, namespace)
        {:ok, namespace}
    end
  end

  @doc """
  Invalidates all cached namespace entries for an application.

  Call this when namespaces are created, updated, or deleted.
  """
  @spec invalidate_cache(String.t()) :: :ok
  def invalidate_cache(application_id) do
    NamespaceCache.invalidate(application_id)
  end
end
