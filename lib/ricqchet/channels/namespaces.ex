defmodule Ricqchet.Channels.Namespaces do
  @moduledoc """
  Context module for channel namespace operations.

  Namespaces define configuration patterns for channels within an application.
  A namespace matches channels by pattern (exact, prefix wildcard, or catch-all)
  and applies rules for history, caching, limits, and authentication.
  """

  import Ecto.Query

  alias Ricqchet.Channels.Namespace
  alias Ricqchet.Repo

  @doc """
  Creates a namespace for an application.
  """
  @spec create_namespace(map(), String.t(), String.t()) ::
          {:ok, Namespace.t()} | {:error, Ecto.Changeset.t()}
  def create_namespace(attrs, application_id, tenant_id) do
    %Namespace{}
    |> Namespace.changeset(attrs)
    |> Ecto.Changeset.put_change(:application_id, application_id)
    |> Ecto.Changeset.put_change(:tenant_id, tenant_id)
    |> Repo.insert()
  end

  @doc """
  Lists all namespaces for an application, ordered by priority descending.
  """
  @spec list_namespaces(String.t()) :: [Namespace.t()]
  def list_namespaces(application_id) do
    Namespace
    |> where([n], n.application_id == ^application_id)
    |> order_by([n], desc: n.priority)
    |> Repo.all()
  end

  @doc """
  Gets a namespace by ID, scoped to an application.
  """
  @spec get_namespace(String.t(), String.t()) :: Namespace.t() | nil
  def get_namespace(id, application_id) do
    Namespace
    |> where([n], n.id == ^id and n.application_id == ^application_id)
    |> Repo.one()
  end

  @doc """
  Updates a namespace.
  """
  @spec update_namespace(Namespace.t(), map()) ::
          {:ok, Namespace.t()} | {:error, Ecto.Changeset.t()}
  def update_namespace(%Namespace{} = namespace, attrs) do
    namespace
    |> Namespace.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a namespace.
  """
  @spec delete_namespace(Namespace.t()) :: {:ok, Namespace.t()} | {:error, Ecto.Changeset.t()}
  def delete_namespace(%Namespace{} = namespace) do
    Repo.delete(namespace)
  end

  @doc """
  Finds the matching namespace for a channel name within an application.

  Loads all namespaces for the application (ordered by priority descending)
  and returns the first one whose pattern matches the channel name.

  ## Pattern matching rules

  - `"chat-room1"` — exact match only
  - `"private-chat-*"` — matches any channel starting with `private-chat-`
  - `"*"` — matches everything (catch-all fallback)

  Returns `nil` if no namespace matches.
  """
  @spec find_matching_namespace(String.t(), String.t()) :: Namespace.t() | nil
  def find_matching_namespace(application_id, channel_name) do
    application_id
    |> list_namespaces()
    |> Enum.find(&pattern_matches?(&1.pattern, channel_name))
  end

  @doc """
  Checks whether a pattern matches a channel name.

  Supports exact match, prefix wildcard (`prefix-*`), and catch-all (`*`).
  """
  @spec pattern_matches?(String.t(), String.t()) :: boolean()
  def pattern_matches?("*", _channel_name), do: true

  def pattern_matches?(pattern, channel_name) do
    if String.ends_with?(pattern, "*") do
      prefix = String.slice(pattern, 0..(String.length(pattern) - 2))
      String.starts_with?(channel_name, prefix)
    else
      pattern == channel_name
    end
  end
end
