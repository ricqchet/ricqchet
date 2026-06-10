defmodule Ricqchet.Channels.History do
  @moduledoc """
  Queries persisted channel events for history and recovery.

  Provides functions to retrieve events by sequence for missed-message
  recovery and recent event listing.
  """

  import Ecto.Query

  alias Ricqchet.Channels.ChannelEvent
  alias Ricqchet.Repo

  @max_events 100

  @doc """
  Returns events after a given event ID for a channel.

  Looks up the sequence of the provided event ID, then returns all
  subsequent events ordered by sequence ascending.

  Returns `{:ok, events}` or `{:error, :event_not_found}` if the
  reference event doesn't exist (may have been pruned).
  """
  @spec get_events_since(String.t(), String.t(), String.t(), keyword()) ::
          {:ok, [ChannelEvent.t()]} | {:error, :event_not_found}
  def get_events_since(application_id, channel, since_event_id, opts \\ []) do
    limit = min(Keyword.get(opts, :limit, @max_events), @max_events)

    case get_sequence_for_event(application_id, channel, since_event_id) do
      {:ok, sequence} ->
        query =
          from(e in ChannelEvent,
            where:
              e.application_id == ^application_id and
                e.channel == ^channel and
                e.sequence > ^sequence,
            order_by: [asc: :sequence],
            limit: ^limit
          )

        {:ok, Repo.all(query)}

      :error ->
        {:error, :event_not_found}
    end
  end

  @doc """
  Returns the most recent events for a channel.

  Events are returned in ascending sequence order (oldest first).
  """
  @spec get_recent_events(String.t(), String.t(), keyword()) :: [ChannelEvent.t()]
  def get_recent_events(application_id, channel, opts \\ []) do
    limit = min(Keyword.get(opts, :limit, @max_events), @max_events)

    subquery =
      from(e in ChannelEvent,
        where: e.application_id == ^application_id and e.channel == ^channel,
        order_by: [desc: :sequence],
        limit: ^limit,
        select: e.id
      )

    query =
      from(e in ChannelEvent,
        where: e.id in subquery(subquery),
        order_by: [asc: :sequence]
      )

    Repo.all(query)
  end

  defp get_sequence_for_event(application_id, channel, event_id) do
    query =
      from(e in ChannelEvent,
        where:
          e.id == ^event_id and
            e.application_id == ^application_id and
            e.channel == ^channel,
        select: e.sequence
      )

    case Repo.one(query) do
      nil -> :error
      sequence -> {:ok, sequence}
    end
  end
end
