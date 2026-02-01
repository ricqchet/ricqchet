defmodule RicqchetWeb.ApplicationJSON do
  @moduledoc """
  JSON views for application endpoints.
  """

  require Logger

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
  def render("index.json", %{applications: applications, meta: meta}) do
    %{
      data: Enum.map(applications, &application_summary/1),
      meta: pagination_meta(meta)
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
        %Ecto.Association.NotLoaded{} ->
          Logger.warning("api_keys not preloaded for application #{app.id}")
          0

        keys when is_list(keys) ->
          length(keys)
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
        %Ecto.Association.NotLoaded{} ->
          Logger.warning("api_keys not preloaded for application #{app.id}")
          []

        keys when is_list(keys) ->
          Enum.map(keys, &api_key_summary/1)
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

  defp pagination_meta(%Flop.Meta{} = meta) do
    base = %{
      total: meta.total_count,
      has_next_page: meta.has_next_page?,
      has_previous_page: meta.has_previous_page?,
      start_cursor: meta.start_cursor,
      end_cursor: meta.end_cursor
    }

    maybe_add_offset_meta(base, meta)
  end

  defp maybe_add_offset_meta(result, %Flop.Meta{current_offset: nil}), do: result

  defp maybe_add_offset_meta(result, %Flop.Meta{} = meta) do
    result
    |> Map.put(:current_offset, meta.current_offset)
    |> Map.put(:current_page, meta.current_page)
    |> Map.put(:total_pages, meta.total_pages)
  end
end
