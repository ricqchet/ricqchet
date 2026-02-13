defmodule RicqchetWeb.ChannelController do
  @moduledoc """
  Controller for channel operations.

  Provides endpoints for publishing events to channels and querying
  active channel information.
  """

  use RicqchetWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias OpenApiSpex.Schema
  alias Ricqchet.Channels
  alias RicqchetWeb.Schemas

  action_fallback RicqchetWeb.FallbackController

  tags(["channels"])

  @max_channels 10
  @max_batch_size 10

  operation(:create,
    summary: "Trigger an event",
    description: "Publishes an event to one or more channels.",
    request_body: {"Event payload", "application/json", Schemas.Channels.TriggerEventRequest},
    responses:
      Schemas.Helpers.create_responses(
        Schemas.Channels.TriggerEventResponse,
        202,
        [401, 403, 422, 429]
      ),
    security: [%{"bearer_auth" => []}]
  )

  def create(conn, params) do
    application = conn.assigns.current_application

    with :ok <- check_channels_enabled(application),
         {:ok, channels} <- extract_channels(params),
         {:ok, event} <- extract_event(params),
         :ok <- validate_all_channels(channels),
         {:ok, event_ids} <-
           publish_to_channels(application.id, channels, event, params,
             tenant_id: application.tenant_id
           ) do
      conn
      |> put_status(:accepted)
      |> render(:created, event_ids: event_ids, channels: channels)
    end
  end

  operation(:batch_create,
    summary: "Trigger batch events",
    description:
      "Publishes multiple events in a single API call. Each event is published independently; partial success is possible.",
    request_body: {"Batch payload", "application/json", Schemas.Channels.BatchTriggerRequest},
    responses:
      Schemas.Helpers.create_responses(
        Schemas.Channels.BatchTriggerResponse,
        202,
        [401, 403, 422, 429]
      ),
    security: [%{"bearer_auth" => []}]
  )

  def batch_create(conn, %{"batch" => events}) when is_list(events) do
    application = conn.assigns.current_application

    with :ok <- check_channels_enabled(application),
         :ok <- validate_batch_size(events) do
      results =
        Enum.map(events, fn event_params ->
          publish_batch_event(application, event_params)
        end)

      conn
      |> put_status(:accepted)
      |> render(:batch_created, results: results)
    end
  end

  def batch_create(conn, _params) do
    application = conn.assigns.current_application

    with :ok <- check_channels_enabled(application) do
      {:error, :validation, "batch is required and must be a list"}
    end
  end

  operation(:index,
    summary: "List channels",
    description: "Lists all active channels for the current application.",
    responses: Schemas.Helpers.list_responses(Schemas.Channels.ChannelList, [401, 403, 429]),
    security: [%{"bearer_auth" => []}]
  )

  def index(conn, _params) do
    application = conn.assigns.current_application

    with :ok <- check_channels_enabled(application) do
      channels = Channels.list_channels(application.id)
      render(conn, :index, channels: channels)
    end
  end

  operation(:show,
    summary: "Get channel info",
    description:
      "Returns details for a specific channel including subscriber count and type. For presence channels, includes the list of connected members.",
    parameters: [
      channel_name: [
        in: :path,
        schema: %Schema{type: :string},
        required: true,
        description: "Channel name"
      ]
    ],
    responses: Schemas.Helpers.show_responses(Schemas.Channels.ChannelInfo, [401, 403, 429]),
    security: [%{"bearer_auth" => []}]
  )

  def show(conn, %{"channel_name" => channel_name}) do
    application = conn.assigns.current_application

    with :ok <- check_channels_enabled(application) do
      info = Channels.get_channel_info(application.id, channel_name)
      render(conn, :show, channel: info)
    end
  end

  defp publish_to_channels(application_id, channels, event, params, extra_opts) do
    data = Map.get(params, "data", %{})
    socket_id = Map.get(params, "socket_id")

    opts = Keyword.merge(extra_opts, if(socket_id, do: [socket_id: socket_id], else: []))

    result =
      Enum.reduce_while(channels, {:ok, []}, fn channel, {:ok, ids} ->
        case Channels.publish_event(application_id, channel, event, data, opts) do
          {:ok, publish_result} ->
            {:cont, {:ok, [publish_result.id | ids]}}

          {:error, :event_too_large} ->
            {:halt, {:error, :validation, "event data exceeds maximum allowed size"}}
        end
      end)

    case result do
      {:ok, ids} -> {:ok, Enum.reverse(ids)}
      error -> error
    end
  end

  defp check_channels_enabled(application) do
    if application.channels_enabled do
      :ok
    else
      {:error, :forbidden}
    end
  end

  defp extract_channels(%{"channel" => channel}) when is_binary(channel) and channel != "" do
    {:ok, [channel]}
  end

  defp extract_channels(%{"channels" => channels}) when is_list(channels) do
    channels = Enum.filter(channels, &(is_binary(&1) and &1 != ""))

    cond do
      channels == [] ->
        {:error, :validation, "channels list cannot be empty"}

      length(channels) > @max_channels ->
        {:error, :validation, "cannot publish to more than #{@max_channels} channels at once"}

      true ->
        {:ok, channels}
    end
  end

  defp extract_channels(_) do
    {:error, :validation, "channel or channels is required"}
  end

  defp extract_event(%{"event" => event}) when is_binary(event) and event != "" do
    {:ok, event}
  end

  defp extract_event(_) do
    {:error, :validation, "event is required"}
  end

  defp validate_all_channels(channels) do
    Enum.reduce_while(channels, :ok, fn channel, :ok ->
      case Channels.validate_channel_name(channel) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, :validation, reason}}
      end
    end)
  end

  defp validate_batch_size([]), do: {:error, :validation, "batch cannot be empty"}

  defp validate_batch_size(events) when length(events) > @max_batch_size do
    {:error, :validation, "batch cannot contain more than #{@max_batch_size} events"}
  end

  defp validate_batch_size(_events), do: :ok

  defp publish_batch_event(application, params) do
    channel = Map.get(params, "channel", "")
    event = Map.get(params, "event", "")

    case validate_batch_event_params(channel, event) do
      :ok ->
        do_publish_batch_event(application, channel, event, params)

      {:error, message} ->
        %{channel: channel, event: event, error: message, status: "error"}
    end
  end

  defp validate_batch_event_params(channel, event) do
    with {:ok, _} <- validate_batch_field(channel, "channel"),
         {:ok, _} <- validate_batch_field(event, "event"),
         :ok <- Channels.validate_channel_name(channel) do
      :ok
    else
      {:error, :validation, message} -> {:error, message}
      {:error, message} when is_binary(message) -> {:error, message}
    end
  end

  defp do_publish_batch_event(application, channel, event, params) do
    data = Map.get(params, "data", %{})
    opts = build_publish_opts(application.tenant_id, params)

    case Channels.publish_event(application.id, channel, event, data, opts) do
      {:ok, result} ->
        %{channel: channel, event: event, event_id: result.id, status: "ok"}

      {:error, :event_too_large} ->
        %{
          channel: channel,
          event: event,
          error: "event data exceeds maximum allowed size",
          status: "error"
        }
    end
  end

  defp build_publish_opts(tenant_id, params) do
    opts = [tenant_id: tenant_id]

    case Map.get(params, "socket_id") do
      nil -> opts
      socket_id -> Keyword.put(opts, :socket_id, socket_id)
    end
  end

  defp validate_batch_field(value, _name) when is_binary(value) and value != "", do: {:ok, value}
  defp validate_batch_field(_, name), do: {:error, :validation, "#{name} is required"}
end
