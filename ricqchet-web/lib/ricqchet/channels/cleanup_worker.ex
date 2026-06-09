defmodule Ricqchet.Channels.CleanupWorker do
  @moduledoc """
  Periodic cleanup of expired channel events.

  Runs every 15 minutes via Oban cron. For each namespace with
  history enabled and cleanup configuration:

  - Deletes events older than `history_ttl_seconds`
  - Trims channels exceeding `history_max_events` (keeps newest)
  """

  use Oban.Worker,
    queue: :default,
    max_attempts: 1

  require Logger

  import Ecto.Query

  alias Ricqchet.Channels.ChannelEvent
  alias Ricqchet.Channels.Namespace
  alias Ricqchet.Channels.Namespaces
  alias Ricqchet.Repo

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    namespaces = get_namespaces_with_cleanup_config()

    stats =
      Enum.reduce(namespaces, %{ttl_deleted: 0, trimmed: 0}, fn namespace, acc ->
        ttl_deleted = cleanup_by_ttl(namespace)
        trimmed = cleanup_by_max_events(namespace)

        %{
          ttl_deleted: acc.ttl_deleted + ttl_deleted,
          trimmed: acc.trimmed + trimmed
        }
      end)

    if stats.ttl_deleted > 0 or stats.trimmed > 0 do
      Logger.info("Channel event cleanup complete",
        ttl_deleted: stats.ttl_deleted,
        trimmed: stats.trimmed
      )
    end

    :ok
  end

  defp get_namespaces_with_cleanup_config do
    query =
      from(n in Namespace,
        where: n.history_enabled == true,
        where: not is_nil(n.history_ttl_seconds) or not is_nil(n.history_max_events)
      )

    Repo.all(query)
  end

  defp cleanup_by_ttl(%{history_ttl_seconds: nil}), do: 0

  defp cleanup_by_ttl(namespace) do
    ttl_seconds = namespace.history_ttl_seconds

    {count, _} =
      ChannelEvent
      |> where([e], e.application_id == ^namespace.application_id)
      |> where([e], e.inserted_at < fragment("now() - interval '1 second' * ?", ^ttl_seconds))
      |> Repo.delete_all()

    count
  end

  defp cleanup_by_max_events(%{history_max_events: nil}), do: 0

  defp cleanup_by_max_events(namespace) do
    query =
      from(e in ChannelEvent,
        where: e.application_id == ^namespace.application_id,
        distinct: e.channel,
        select: e.channel
      )

    channels = Repo.all(query)

    Enum.reduce(channels, 0, fn channel, total ->
      if Namespaces.pattern_matches?(namespace.pattern, channel) do
        total + trim_channel(namespace.application_id, channel, namespace.history_max_events)
      else
        total
      end
    end)
  end

  defp trim_channel(application_id, channel, max_events) do
    ids_to_delete =
      from(e in ChannelEvent,
        where: e.application_id == ^application_id and e.channel == ^channel,
        order_by: [desc: :sequence],
        offset: ^max_events,
        select: e.id
      )

    delete_query = from(e in ChannelEvent, where: e.id in subquery(ids_to_delete))
    {deleted, _} = Repo.delete_all(delete_query)
    deleted
  end
end
