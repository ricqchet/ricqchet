defmodule Ricqchet.FlowControl.Backends.Postgres do
  @moduledoc """
  PostgreSQL-backed flow control backend.

  Uses atomic UPSERT operations for cluster-wide coordination of
  parallelism and rate limits. Combines both checks into a single
  database round-trip when both are configured.

  ## Error Handling

  Uses a fail-open strategy: if database queries fail, messages are
  allowed through rather than being blocked.
  """

  @behaviour Ricqchet.FlowControl.Backend

  require Logger

  alias Ricqchet.Repo

  @impl Ricqchet.FlowControl.Backend
  def acquire_slot(destination_id, parallelism, rate_limit) do
    now = DateTime.utc_now()
    uuid = dump_uuid!(destination_id)

    case {parallelism, rate_limit} do
      {nil, nil} ->
        :ok

      {parallelism, nil} ->
        check_parallelism(uuid, destination_id, parallelism, now)

      {nil, rate_limit} ->
        check_rate_limit(uuid, destination_id, rate_limit, now)

      {parallelism, rate_limit} ->
        check_both(uuid, destination_id, parallelism, rate_limit, now)
    end
  end

  @impl Ricqchet.FlowControl.Backend
  def release_slot(destination_id) do
    uuid = dump_uuid!(destination_id)

    query = """
    UPDATE flow_control_state
    SET in_flight_count = GREATEST(in_flight_count - 1, 0),
        updated_at = $2
    WHERE destination_id = $1
    """

    case Repo.query(query, [uuid, DateTime.utc_now()]) do
      {:ok, _} -> :ok
      {:error, _} -> :ok
    end
  end

  defp dump_uuid!(id) do
    {:ok, binary} = Ecto.UUID.dump(id)
    binary
  end

  # When both parallelism and rate limit are configured, perform a single
  # atomic operation that checks both constraints. This reduces two DB
  # round-trips to one on the hot path.
  defp check_both(uuid, destination_id, parallelism_limit, rate_limit, now) do
    window_start = DateTime.truncate(now, :second)

    # Single UPSERT that atomically checks both parallelism and rate limit.
    # The WHERE clause ensures we only update if BOTH constraints are met.
    # On insert (new destination): starts with in_flight=1, request_count=1.
    # On conflict (existing): increments both if under limits, resets rate
    # window if it has changed.
    query = """
    INSERT INTO flow_control_state
      (destination_id, in_flight_count, window_start, request_count, inserted_at, updated_at)
    VALUES ($1, 1, $2, 1, $3, $3)
    ON CONFLICT (destination_id) DO UPDATE
    SET in_flight_count = flow_control_state.in_flight_count + 1,
        request_count = CASE
          WHEN flow_control_state.window_start < $2 THEN 1
          ELSE flow_control_state.request_count + 1
        END,
        window_start = CASE
          WHEN flow_control_state.window_start < $2 THEN $2
          ELSE flow_control_state.window_start
        END,
        updated_at = $3
    WHERE flow_control_state.in_flight_count < $4
      AND (flow_control_state.window_start < $2
           OR flow_control_state.request_count < $5)
    RETURNING in_flight_count, request_count, window_start
    """

    case Repo.query(query, [uuid, window_start, now, parallelism_limit, rate_limit]) do
      {:ok, %{num_rows: 1}} ->
        :ok

      {:ok, %{num_rows: 0}} ->
        # At least one limit was exceeded. Determine which one for the
        # appropriate delay. We do a cheap read to figure out which limit
        # was hit so we can calculate the right backoff.
        determine_delay(uuid, destination_id, parallelism_limit, rate_limit, window_start)

      {:error, reason} ->
        Logger.warning("Flow control: combined check failed",
          destination_id: destination_id,
          error: inspect(reason)
        )

        :ok
    end
  end

  defp determine_delay(uuid, destination_id, parallelism_limit, rate_limit, window_start) do
    read_query = """
    SELECT in_flight_count, request_count, window_start
    FROM flow_control_state
    WHERE destination_id = $1
    """

    case Repo.query(read_query, [uuid]) do
      {:ok, %{num_rows: 1, rows: [[in_flight, request_count, current_window]]}} ->
        cond do
          in_flight >= parallelism_limit ->
            delay = calculate_parallelism_delay()

            Logger.debug("Flow control: parallelism limit reached",
              destination_id: destination_id,
              limit: parallelism_limit,
              delay: delay
            )

            {:delay, delay}

          current_window >= window_start and request_count >= rate_limit ->
            delay = calculate_rate_limit_delay(window_start)

            Logger.debug("Flow control: rate limit reached",
              destination_id: destination_id,
              limit: rate_limit,
              delay: delay
            )

            {:delay, delay}

          true ->
            # Race condition: state changed between UPSERT and read
            {:delay, calculate_parallelism_delay()}
        end

      _ ->
        {:delay, calculate_parallelism_delay()}
    end
  end

  defp check_parallelism(uuid, destination_id, limit, now) do
    query = """
    INSERT INTO flow_control_state (destination_id, in_flight_count, request_count, inserted_at, updated_at)
    VALUES ($1, 1, 0, $2, $2)
    ON CONFLICT (destination_id) DO UPDATE
    SET in_flight_count = flow_control_state.in_flight_count + 1,
        updated_at = $2
    WHERE flow_control_state.in_flight_count < $3
    RETURNING in_flight_count
    """

    case Repo.query(query, [uuid, now, limit]) do
      {:ok, %{num_rows: 1}} ->
        :ok

      {:ok, %{num_rows: 0}} ->
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

        :ok
    end
  end

  defp check_rate_limit(uuid, destination_id, limit, now) do
    window_start = DateTime.truncate(now, :second)

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

    case Repo.query(query, [uuid, window_start, now, limit]) do
      {:ok, %{num_rows: 1}} ->
        :ok

      {:ok, %{num_rows: 0}} ->
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

  defp calculate_parallelism_delay do
    base_delay = 1
    jitter = :rand.uniform(500) / 1000
    base_delay + jitter
  end

  defp calculate_rate_limit_delay(window_start) do
    next_window = DateTime.add(window_start, 1, :second)
    now = DateTime.utc_now()
    diff = DateTime.diff(next_window, now, :millisecond)
    max(diff / 1000, 0.1) + :rand.uniform(100) / 1000
  end
end
