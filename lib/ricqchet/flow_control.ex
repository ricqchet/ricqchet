defmodule Ricqchet.FlowControl do
  @moduledoc """
  Flow control for message delivery.

  Enforces per-destination parallelism and rate limits to prevent
  overwhelming webhook endpoints.

  ## Settings

  Flow control is configured per destination (tenant + URL):
  - `parallelism` - Max concurrent deliveries (nil = unlimited)
  - `rate_limit` - Max requests/second (nil = unlimited)

  ## Backend

  The storage backend is configurable via application config:

      config :ricqchet, flow_control_backend: Ricqchet.FlowControl.Backends.Postgres

  The default backend uses PostgreSQL with atomic UPSERT operations for
  cluster-wide coordination.

  ## Error Handling

  This module uses a **fail-open** strategy: if backend operations fail,
  messages are allowed through rather than being blocked. This prevents
  infrastructure issues from causing complete delivery stoppages.
  The Reconciler corrects any resulting state drift.
  """

  require Logger

  alias Ricqchet.FlowControl.Destination
  alias Ricqchet.FlowControl.SettingsCache
  alias Ricqchet.Messages.Message
  alias Ricqchet.Repo

  @backend Application.compile_env(
             :ricqchet,
             :flow_control_backend,
             Ricqchet.FlowControl.Backends.Postgres
           )

  @doc """
  Attempts to acquire a flow control slot for message delivery.

  Returns:
  - `:ok` if the message can be dispatched
  - `{:delay, seconds}` if limits exceeded and message should be rescheduled
  """
  def acquire_slot(%Message{destination_id: nil}), do: :ok

  def acquire_slot(%Message{destination_id: destination_id}) do
    case get_settings(destination_id) do
      {:ok, {nil, nil}} ->
        :ok

      {:ok, {parallelism, rate_limit}} ->
        @backend.acquire_slot(destination_id, parallelism, rate_limit)

      :error ->
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
        :ok

      {:ok, {_parallelism, _rate_limit}} ->
        @backend.release_slot(destination_id)

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

  defp load_and_cache_settings(destination_id) do
    case Repo.get(Destination, destination_id) do
      nil ->
        :error

      %Destination{parallelism: parallelism, rate_limit: rate_limit} ->
        SettingsCache.put(destination_id, parallelism, rate_limit)
        {:ok, {parallelism, rate_limit}}
    end
  end
end
