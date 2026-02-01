defmodule RicqchetWeb.ApplicationJSON do
  @moduledoc """
  JSON views for application endpoints.
  """

  alias Ricqchet.ApiKeys.ApiKey
  alias Ricqchet.Applications.Application

  @doc """
  Renders application responses.

  - `index.json` - Renders paginated list of applications
  - `show.json` - Renders application details with API keys
  - `created.json` - Renders new application with initial API key
  - `updated.json` - Renders updated application
  - `deleted.json` - Renders deletion confirmation
  """
  def render("index.json", %{applications: applications, total: total}) do
    %{
      data: Enum.map(applications, &application_summary/1),
      meta: %{total: total}
    }
  end

  def render("show.json", %{application: application}) do
    application_detail(application)
  end

  def render("created.json", %{application: application, api_key: api_key}) do
    %{
      id: application.id,
      name: application.name,
      description: application.description,
      status: application.status,
      dlq_destination_url: application.dlq_destination_url,
      api_key: api_key.api_key,
      created_at: application.inserted_at
    }
  end

  def render("updated.json", %{application: application}) do
    application_detail(application)
  end

  def render("deleted.json", %{id: id, api_keys_revoked: count}) do
    %{
      deleted: true,
      id: id,
      api_keys_revoked: count
    }
  end

  defp application_summary(%Application{} = app) do
    api_key_count =
      case app.api_keys do
        %Ecto.Association.NotLoaded{} -> 0
        keys when is_list(keys) -> length(keys)
      end

    %{
      id: app.id,
      name: app.name,
      description: app.description,
      status: app.status,
      dlq_destination_url: app.dlq_destination_url,
      api_key_count: api_key_count,
      created_at: app.inserted_at,
      updated_at: app.updated_at
    }
  end

  defp application_detail(%Application{} = app) do
    api_keys =
      case app.api_keys do
        %Ecto.Association.NotLoaded{} -> []
        keys when is_list(keys) -> Enum.map(keys, &api_key_summary/1)
      end

    %{
      id: app.id,
      name: app.name,
      description: app.description,
      status: app.status,
      dlq_destination_url: app.dlq_destination_url,
      api_keys: api_keys,
      created_at: app.inserted_at,
      updated_at: app.updated_at
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
