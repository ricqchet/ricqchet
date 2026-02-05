defmodule Ricqchet.FlowControl do
  @moduledoc """
  Flow control for message delivery.

  Enforces per-destination parallelism and rate limits to prevent
  overwhelming webhook endpoints.

  ## Settings

  Flow control is configured per destination (tenant + URL):
  - `parallelism` - Max concurrent deliveries (nil = unlimited)
  - `rate_limit` - Max requests/second (nil = unlimited)

  ## Algorithm

  Uses database-backed state for cluster-wide coordination:
  - Parallelism: Atomic increment with limit check using UPSERT
  - Rate limit: Sliding window with 1-second granularity

  When limits are exceeded, messages are rescheduled with a delay.
  """

  import Ecto.Query
  require Logger

  alias Ricqchet.FlowControl.Destination
  alias Ricqchet.FlowControl.Destinations
  alias Ricqchet.FlowControl.SettingsCache
  alias Ricqchet.FlowControl.State
  alias Ricqchet.Messages.Message
  alias Ricqchet.Repo

  @doc """
  Attempts to acquire a flow control slot for message delivery.

  Returns:
  - `:ok` if the message can be dispatched
  - `{:delay, seconds}` if limits exceeded and message should be rescheduled
  - `:no_destination` if message has no destination_id (no flow control)
  """
  def acquire_slot(%Message{destination_id: nil}), do: :ok

  def acquire_slot(%Message{destination_id: destination_id}) do
    case get_settings(destination_id) do
      {:ok, {nil, nil}} ->
        # No limits configured
        :ok

      {:ok, {parallelism, rate_limit}} ->
        do_acquire_slot(destination_id, parallelism, rate_limit)

      :error ->
        # Destination not found - allow dispatch
        :ok
    end
  end

  @doc """
  Releases a flow control slot after delivery completes.

  Should be called regardless of delivery success or failure.
  """
  def release_slot(%Message{destination_id: nil}), do: :ok

  def release_slot(%Message{destination_id: destination_id}) do
    case get_settings(destination_id) do
      {:ok, {nil, _}} ->
        # No parallelism limit, nothing to release
        :ok

      {:ok, {_parallelism, _rate_limit}} ->
        do_release_slot(destination_id)

      :error ->
        :ok
    end
  end

  @doc """
  Gets flow control settings for a destination, using cache when available.

  Returns `{:ok, {parallelism, rate_limit}}` or `:error` if not found.
  """
  def get_settings(destination_id) do
    case SettingsCache.get(destination_id) do
      {:ok, settings} ->
        {:ok, settings}

      :miss ->
        load_and_cache_settings(destination_id)
    end
  end

  # Private implementation

  defp do_acquire_slot(destination_id, parallelism, rate_limit) do
    now = DateTime.utc_now()

    # Check parallelism first (if configured)
    with :ok <- check_parallelism(destination_id, parallelism, now),
         :ok <- check_rate_limit(destination_id, rate_limit, now) do
      :ok
    end
  end

  defp check_parallelism(_destination_id, nil, _now), do: :ok

  defp check_parallelism(destination_id, limit, now) do
    # Atomic check-and-increment using Postgres UPSERT
    # Only increments if under limit
    query = """
    INSERT INTO flow_control_state (destination_id, in_flight_count, request_count, inserted_at, updated_at)
    VALUES ($1, 1, 0, $2, $2)
    ON CONFLICT (destination_id) DO UPDATE
    SET in_flight_count = flow_control_state.in_flight_count + 1,
        updated_at = $2
    WHERE flow_control_state.in_flight_count < $3
    RETURNING in_flight_count
    """

    case Repo.query(query, [destination_id, now, limit]) do
      {:ok, %{num_rows: 1}} ->
        :ok

      {:ok, %{num_rows: 0}} ->
        # Limit exceeded
        delay = calculate_parallelism_delay()
        Logger.debug("Flow control: parallelism limit reached",
          destination_id: destination_id,
          limit: limit,
          delay: delay
        )
        {:delay, delay}

      {:error, reason} ->
        Logger.warning("Flow control: parallelism check failed",
          destination_id: destination_id,
          error: inspect(reason)
        )
        # Allow dispatch on error to avoid blocking
        :ok
    end
  end

  defp check_rate_limit(_destination_id, nil, _now), do: :ok

  defp check_rate_limit(destination_id, limit, now) do
    window_start = DateTime.truncate(now, :second)

    # Atomic check-and-increment for rate limiting
    # Resets counter if window has changed
    query = """
    INSERT INTO flow_control_state (destination_id, in_flight_count, window_start, request_count, inserted_at, updated_at)
    VALUES ($1, 0, $2, 1, $3, $3)
    ON CONFLICT (destination_id) DO UPDATE
    SET request_count = CASE
          WHEN flow_control_state.window_start < $2 THEN 1
          ELSE flow_control_state.request_count + 1
        END,
        window_start = CASE
          WHEN flow_control_state.window_start < $2 THEN $2
          ELSE flow_control_state.window_start
        END,
        updated_at = $3
    WHERE flow_control_state.window_start < $2
       OR flow_control_state.request_count < $4
    RETURNING request_count, window_start
    """

    case Repo.query(query, [destination_id, window_start, now, limit]) do
      {:ok, %{num_rows: 1}} ->
        :ok

      {:ok, %{num_rows: 0}} ->
        # Rate limit exceeded
        delay = calculate_rate_limit_delay(window_start)
        Logger.debug("Flow control: rate limit reached",
          destination_id: destination_id,
          limit: limit,
          delay: delay
        )
        {:delay, delay}

      {:error, reason} ->
        Logger.warning("Flow control: rate limit check failed",
          destination_id: destination_id,
          error: inspect(reason)
        )
        :ok
    end
  end

  defp do_release_slot(destination_id) do
    query = """
    UPDATE flow_control_state
    SET in_flight_count = GREATEST(in_flight_count - 1, 0),
        updated_at = $2
    WHERE destination_id = $1
    """

    case Repo.query(query, [destination_id, DateTime.utc_now()]) do
      {:ok, _} -> :ok
      {:error, _} -> :ok
    end
  end

  defp load_and_cache_settings(destination_id) do
    case Repo.get(Destination, destination_id) do
      nil ->
        :error

      %Destination{parallelism: parallelism, rate_limit: rate_limit} ->
        SettingsCache.put(destination_id, parallelism, rate_limit)
        {:ok, {parallelism, rate_limit}}
    end
  end

  defp calculate_parallelism_delay do
    # Base delay with jitter to prevent thundering herd
    base_delay = 1
    jitter = :rand.uniform(500) / 1000
    base_delay + jitter
  end

  defp calculate_rate_limit_delay(window_start) do
    # Calculate time until next window
    next_window = DateTime.add(window_start, 1, :second)
    now = DateTime.utc_now()
    diff = DateTime.diff(next_window, now, :millisecond)
    max(diff / 1000, 0.1) + :rand.uniform(100) / 1000
  end
end
