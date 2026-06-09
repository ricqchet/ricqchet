defmodule Ricqchet.Stats.ChannelStats do
  @moduledoc """
  Dashboard statistics for the Channels feature.

  Aggregates real-time channel data (from ETS-based trackers) and
  historical event data (from the database) for dashboard display.
  """

  import Ecto.Query

  alias Ricqchet.Channels
  alias Ricqchet.Channels.ChannelEvent
  alias Ricqchet.Channels.ConnectionTracker

  alias Ricqchet.Repo
  alias RicqchetWeb.Channels.Presence

  @default_period "1h"
  @default_limit 25

  @periods %{
    "5m" => 5 * 60,
    "1h" => 60 * 60,
    "4h" => 4 * 60 * 60,
    "1d" => 24 * 60 * 60,
    "1w" => 7 * 24 * 60 * 60
  }

  @doc """
  Returns an overview of channel activity for a single application.

  All data is read from ETS (fast, no DB queries).
  """
  @spec overview(String.t()) :: %{
          total_channels: non_neg_integer(),
          total_connections: non_neg_integer(),
          total_presence_users: non_neg_integer()
        }
  def overview(application_id) do
    channels = Channels.list_channels(application_id)
    connections = ConnectionTracker.get_count(application_id)

    presence_users =
      channels
      |> Enum.filter(&(&1.type == "presence"))
      |> Enum.reduce(0, fn channel, acc ->
        topic = "channels:app:#{application_id}:#{channel.name}"
        acc + map_size(Presence.list(topic))
      end)

    %{
      total_channels: length(channels),
      total_connections: connections,
      total_presence_users: presence_users
    }
  end

  @doc """
  Lists active channels for an application, sorted by subscriber count descending.
  """
  @spec active_channels(String.t()) :: [map()]
  def active_channels(application_id) do
    application_id
    |> Channels.list_channels()
    |> Enum.sort_by(& &1.subscriber_count, :desc)
  end

  @doc """
  Returns a breakdown of active channels by type for an application.
  """
  @spec type_breakdown(String.t()) :: %{
          public: non_neg_integer(),
          private: non_neg_integer(),
          presence: non_neg_integer()
        }
  def type_breakdown(application_id) do
    channels = Channels.list_channels(application_id)

    %{
      public: Enum.count(channels, &(&1.type == "public")),
      private: Enum.count(channels, &(&1.type == "private")),
      presence: Enum.count(channels, &(&1.type == "presence"))
    }
  end

  @doc """
  Returns recent channel events for an application from the database.

  ## Options

    * `:period` - Time period: "5m", "1h", "4h", "1d", "1w" (default: "1h")
    * `:limit` - Number of events to return (default: 25)
  """
  @spec recent_channel_events(String.t(), keyword()) :: [map()]
  def recent_channel_events(application_id, opts \\ []) do
    period = Keyword.get(opts, :period, @default_period)
    limit = Keyword.get(opts, :limit, @default_limit)
    since = period_to_datetime(period)

    ChannelEvent
    |> where([e], e.application_id == ^application_id)
    |> where([e], e.inserted_at >= ^since)
    |> order_by([e], desc: e.sequence)
    |> limit(^limit)
    |> select([e], %{
      id: e.id,
      channel: e.channel,
      event_name: e.event_name,
      data_size_bytes: e.data_size_bytes,
      user_id: e.user_id,
      sequence: e.sequence,
      inserted_at: e.inserted_at
    })
    |> Repo.all()
  end

  defp period_to_datetime(period) do
    seconds = Map.get(@periods, period, @periods[@default_period])
    DateTime.add(DateTime.utc_now(), -seconds, :second)
  end
end
