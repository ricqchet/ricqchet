defmodule Relay.Batches do
  @moduledoc """
  Context module for batch operations.

  Batches collect multiple messages and deliver them as a JSON array
  in a single HTTP request.
  """

  import Ecto.Query

  alias Relay.Batches.Batch
  alias Relay.Messages.Message
  alias Relay.Repo
  alias Relay.Tenants.Tenant

  @doc """
  Gets a batch by ID.
  """
  def get(id), do: Repo.get(Batch, id)

  @doc """
  Gets a batch by ID, raising if not found.
  """
  def get!(id), do: Repo.get!(Batch, id)

  @doc """
  Gets a batch by ID for a specific tenant.
  """
  def get_by_tenant(%Tenant{id: tenant_id}, batch_id) do
    Batch
    |> where([b], b.id == ^batch_id and b.tenant_id == ^tenant_id)
    |> Repo.one()
  end

  @doc """
  Finds an existing collecting batch or creates a new one.

  Batches are identified by tenant_id + destination_url + batch_key.
  """
  def find_or_create_collecting(%Tenant{} = tenant, destination_url, batch_key, opts \\ %{}) do
    query =
      from b in Batch,
        where: b.tenant_id == ^tenant.id,
        where: b.destination_url == ^destination_url,
        where: b.batch_key == ^batch_key,
        where: b.status == "collecting",
        lock: "FOR UPDATE"

    result =
      Repo.transaction(fn ->
        case Repo.one(query) do
          nil ->
            create_batch(tenant, destination_url, batch_key, opts)

          batch ->
            {:existing, batch}
        end
      end)

    case result do
      {:ok, {:existing, batch}} -> {:ok, batch, :existing}
      {:ok, {:ok, batch}} -> {:ok, batch, :new}
      {:ok, {:error, changeset}} -> {:error, changeset}
      {:error, reason} -> {:error, reason}
    end
  end

  defp create_batch(tenant, destination_url, batch_key, opts) do
    attrs =
      opts
      |> Map.put(:destination_url, destination_url)
      |> Map.put(:batch_key, batch_key)

    %Batch{}
    |> Batch.create_changeset(tenant, attrs)
    |> Repo.insert()
  end

  @doc """
  Increments the message count for a batch.

  Returns `{:ok, batch, :ready}` if the batch is ready to dispatch (size reached),
  or `{:ok, batch, :collecting}` if still collecting.
  """
  def increment_message_count(%Batch{} = batch) do
    new_count = batch.message_count + 1

    changeset = Batch.changeset(batch, %{message_count: new_count})

    case Repo.update(changeset) do
      {:ok, updated_batch} ->
        if updated_batch.message_count >= updated_batch.max_size do
          {:ok, updated_batch, :ready}
        else
          {:ok, updated_batch, :collecting}
        end

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  @doc """
  Schedules a batch for immediate dispatch by setting scheduled_at to now.

  This is called when a batch reaches max_size and should be dispatched
  immediately by the BatchDispatcher.
  """
  def schedule_for_immediate_dispatch(%Batch{} = batch) do
    now = DateTime.utc_now()

    batch
    |> Batch.changeset(%{scheduled_at: now})
    |> Repo.update()
  end

  @doc """
  Claims the next batch ready for dispatch.

  A batch is ready when:
  - status is "pending" (waiting for retry), OR
  - status is "collecting" AND (message_count >= max_size OR scheduled_at <= now)

  Uses `FOR UPDATE SKIP LOCKED` for safe concurrent access.
  """
  def claim_next_ready do
    now = DateTime.utc_now()

    # Batches in "pending" are always ready (waiting for retry)
    # Batches in "collecting" are ready when size reached or timeout
    query =
      from b in Batch,
        where:
          b.status == "pending" or
            (b.status == "collecting" and
               (b.message_count >= b.max_size or b.scheduled_at <= ^now)),
        order_by: [asc: b.scheduled_at, asc: b.inserted_at],
        limit: 1,
        lock: "FOR UPDATE SKIP LOCKED"

    Repo.transaction(fn ->
      case Repo.one(query) do
        nil ->
          Repo.rollback(:none_available)

        batch ->
          batch
          |> Batch.changeset(%{
            status: "dispatched",
            dispatched_at: now
          })
          |> Repo.update!()
      end
    end)
  end

  @doc """
  Marks a batch as dispatched.
  """
  def mark_dispatched(%Batch{} = batch) do
    now = DateTime.utc_now()

    batch
    |> Batch.changeset(%{
      status: "dispatched",
      dispatched_at: now
    })
    |> Repo.update()
  end

  @doc """
  Marks a batch and all its messages as successfully delivered.
  """
  def mark_delivered(%Batch{} = batch, response) do
    now = DateTime.utc_now()

    Repo.transaction(fn ->
      # Update batch
      {:ok, updated_batch} =
        batch
        |> Batch.changeset(%{
          status: "delivered",
          completed_at: now,
          attempts: batch.attempts + 1,
          last_response_status: response.status,
          last_response_body: truncate_body(response.body)
        })
        |> Repo.update()

      # Update all messages in the batch
      message_query = from(m in Message, where: m.batch_id == ^batch.id)

      Repo.update_all(message_query,
        set: [
          status: "delivered",
          completed_at: now,
          last_response_status: response.status,
          last_response_body: truncate_body(response.body)
        ],
        inc: [attempts: 1]
      )

      updated_batch
    end)
  end

  @doc """
  Marks a batch as failed and schedules a retry if attempts remain.
  """
  def mark_failed(%Batch{} = batch, error, response \\ nil) do
    attempts = batch.attempts + 1
    now = DateTime.utc_now()
    changes = build_failure_changes(batch, attempts, now, error, response)

    Repo.transaction(fn ->
      {:ok, updated_batch} =
        batch
        |> Batch.changeset(changes)
        |> Repo.update()

      maybe_fail_messages(batch, attempts, now, error, response)

      updated_batch
    end)
  end

  defp build_failure_changes(batch, attempts, now, error, response) do
    base = %{
      attempts: attempts,
      last_error: format_error(error),
      last_response_status: response && response[:status],
      last_response_body: response && truncate_body(response[:body])
    }

    if attempts >= batch.max_retries do
      Map.merge(base, %{status: "failed", completed_at: now})
    else
      backoff = DateTime.add(now, backoff_seconds(attempts), :second)
      # Use "pending" status instead of "collecting" for retry clarity
      # "collecting" means accepting new messages, "pending" means awaiting dispatch
      Map.merge(base, %{status: "pending", scheduled_at: backoff})
    end
  end

  defp maybe_fail_messages(batch, attempts, now, error, response) do
    if attempts >= batch.max_retries do
      message_query = from(m in Message, where: m.batch_id == ^batch.id)

      Repo.update_all(message_query,
        set: [
          status: "failed",
          completed_at: now,
          last_error: format_error(error),
          last_response_status: response && response[:status],
          last_response_body: response && truncate_body(response[:body])
        ]
      )
    end
  end

  @doc """
  Gets all message payloads for a batch as a list.

  Each payload is decoded from JSON if stored as a string.
  """
  def get_batch_payloads(%Batch{id: batch_id}) do
    Message
    |> where([m], m.batch_id == ^batch_id)
    |> order_by([m], asc: m.inserted_at)
    |> select([m], m.payload)
    |> Repo.all()
    |> Enum.map(&decode_payload/1)
  end

  defp decode_payload(nil), do: nil

  defp decode_payload(payload) when is_binary(payload) do
    case Jason.decode(payload) do
      {:ok, decoded} -> decoded
      {:error, _} -> payload
    end
  end

  defp decode_payload(payload), do: payload

  # Exponential backoff: 10s, 30s, 90s, 270s, ... capped at 8 hours
  defp backoff_seconds(attempt) do
    base = 10
    max_backoff = 8 * 60 * 60

    backoff = trunc(base * :math.pow(3, attempt - 1))
    min(backoff, max_backoff)
  end

  defp format_error(error) when is_binary(error), do: error
  defp format_error({:http_error, status}), do: "HTTP #{status}"
  defp format_error(%{reason: reason}), do: inspect(reason)
  defp format_error(error), do: inspect(error)

  defp truncate_body(nil), do: nil
  defp truncate_body(body) when is_binary(body), do: String.slice(body, 0, 10_000)

  defp truncate_body(body) do
    body
    |> inspect()
    |> String.slice(0, 10_000)
  end
end
