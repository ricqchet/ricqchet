defmodule RicqchetWeb.ApiKeyJSON do
  @moduledoc """
  JSON views for API key endpoints.
  """

  alias Ricqchet.ApiKeys.ApiKey

  @doc """
  Renders API key responses.

  - `index.json` - Renders list of API keys (prefix only, no full key)
  - `created.json` - Renders new API key with full key (shown once)
  - `revoked.json` - Renders revocation confirmation
  - `rotated.json` - Renders new API key after rotation with full key
  """
  def render("index.json", %{api_keys: api_keys, total: total}) do
    %{
      data: Enum.map(api_keys, &api_key_summary/1),
      meta: %{total: total}
    }
  end

  def render("created.json", %{api_key: api_key}) do
    %{
      id: api_key.id,
      name: api_key.name,
      api_key: api_key.api_key,
      prefix: api_key.api_key_prefix,
      status: api_key.status,
      expires_at: api_key.expires_at,
      created_at: api_key.inserted_at
    }
  end

  def render("revoked.json", %{api_key: api_key}) do
    %{
      id: api_key.id,
      name: api_key.name,
      prefix: api_key.api_key_prefix,
      status: api_key.status,
      revoked: true,
      revoked_at: api_key.updated_at
    }
  end

  def render("rotated.json", %{old_api_key: old_key, new_api_key: new_key}) do
    %{
      old_api_key: %{
        id: old_key.id,
        name: old_key.name,
        prefix: old_key.api_key_prefix,
        status: old_key.status
      },
      new_api_key: %{
        id: new_key.id,
        name: new_key.name,
        api_key: new_key.api_key,
        prefix: new_key.api_key_prefix,
        status: new_key.status,
        expires_at: new_key.expires_at,
        created_at: new_key.inserted_at
      }
    }
  end

  defp api_key_summary(%ApiKey{} = key) do
    %{
      id: key.id,
      name: key.name,
      prefix: key.api_key_prefix,
      status: key.status,
      last_used_at: key.last_used_at,
      expires_at: key.expires_at,
      created_at: key.inserted_at
    }
  end
end
