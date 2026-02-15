defmodule Ricqchet.Messages do
  @moduledoc """
  Context module for message operations.
  """

  import Ecto.Query
  import Ricqchet.DeliveryHelpers

  alias Ricqchet.ActivityEvents
  alias Ricqchet.FlowControl
  alias Ricqchet.FlowControl.Destinations
  alias Ricqchet.Messages.Message
  alias Ricqchet.Repo
  alias Ricqchet.Tenants.Tenant

  @doc """
  Creates a new message for a tenant.

  ## Options

    * `:destination_url` - Required. The URL to deliver the message to.
    * `:payload` - The request body.
    * `:content_type` - Content type header (default: "application/json").
    * `:method` - HTTP method (default: "POST").
    * `:headers` - Additional headers to forward.
    * `:delay` - Delay in seconds before first delivery attempt.
    * `:dedup_key` - Deduplication key.
    * `:dedup_ttl` - Deduplication TTL in seconds (default: 300).
    * `:max_retries` - Override max retries (default: tenant's default).
    * `:application` - Optional. The application creating the message.
    * `:flow_control` - Optional. Flow control settings `%{parallelism: int, rate_limit: int}`.

  """
  def create(%Tenant{} = tenant, attrs, application \\ nil) do
    destination_url = get_attr(attrs, :destination_url)
    flow_control = get_attr(attrs, :flow_control)

    with {:ok, destination} <- Destinations.upsert(tenant, destination_url, flow_control) do
      attrs =
        attrs
        |> maybe_add_application_id(application)
        |> Map.put(:destination_id, destination.id)

      result =
        %Message{}
        |> Message.create_changeset(tenant, attrs)
        |> Repo.insert()

      case result do
        {:ok, message} ->
          ActivityEvents.message_created(message)
          {:ok, message}

        error ->
          error
      end
    end
  end

  defp maybe_add_application_id(attrs, nil), do: attrs
  defp maybe_add_application_id(attrs, %{id: id}), do: Map.put(attrs, :application_id, id)

  @doc """
  Creates a new message associated with a batch.

  The message status is set to "pending" but it won't be picked up by the
  regular dispatcher since it has a batch_id. It will be delivered when
  the batch is dispatched.
  """
  def create_for_batch(%Tenant{} = tenant, batch, attrs, application \\ nil) do
    destination_url = get_attr(attrs, :destination_url)
    flow_control = get_attr(attrs, :flow_control)

    with {:ok, destination} <- Destinations.upsert(tenant, destination_url, flow_control) do
      attrs =
        attrs
        |> Map.put(:batch_id, batch.id)
        |> Map.put(:destination_id, destination.id)
        |> maybe_add_application_id(application)

      %Message{}
      |> Message.create_changeset(tenant, attrs)
      |> Repo.insert()
    end
  end

  @doc """
  Gets a message by ID.
  """
  def get(id), do: Repo.get(Message, id)

  @doc """
  Gets a message by ID with tenant preloaded for delivery.

  The tenant is needed to access the signing_secret for HMAC signatures.
  """
  def get_for_delivery(id) do
    Message
    |> where([m], m.id == ^id)
    |> preload(:tenant)
    |> Repo.one()
  end

  @doc """
  Gets a message by ID, raising if not found.
  """
  def get!(id), do: Repo.get!(Message, id)

  @doc """
  Gets a message by ID for a specific tenant.
  Returns nil if not found or doesn't belong to tenant.
  """
  def get_by_tenant(%Tenant{id: tenant_id}, message_id) do
    Message
    |> where([m], m.id == ^message_id and m.tenant_id == ^tenant_id)
    |> Repo.one()
  end

  @doc """
  Lists messages for a tenant with optional filtering.

  ## Options

    * `:status` - Filter by status ("pending", "dispatched", "delivered", "failed")
    * `:limit` - Max messages to return (default: 20, max: 100)

  Returns `{:ok, messages}`.
  """
  def list_for_tenant(%Tenant{id: tenant_id}, opts \\ []) do
    status = Keyword.get(opts, :status)
    limit = opts |> Keyword.get(:limit, 20) |> min(100)

    query =
      Message
      |> where([m], m.tenant_id == ^tenant_id)
      |> order_by([m], desc: m.inserted_at)
      |> limit(^limit)

    query =
      if status do
        where(query, [m], m.status == ^status)
      else
        query
      end

    {:ok, Repo.all(query)}
  end

  @doc """
  Gets an existing message by dedup_key for a tenant.

  Only returns messages that are:
  - pending or dispatched status
  - within their dedup TTL window (dedup_expires_at > now)
  """
  def get_by_dedup_key(%Tenant{id: tenant_id}, dedup_key) when is_binary(dedup_key) do
    now = DateTime.utc_now()

    Message
    |> where([m], m.tenant_id == ^tenant_id)
    |> where([m], m.dedup_key == ^dedup_key)
    |> where([m], m.status in ["pending", "dispatched"])
    |> where([m], m.dedup_expires_at > ^now)
    |> Repo.one()
  end

  def get_by_dedup_key(_, _), do: nil

  @doc """
  Claims the next pending message for delivery.

  Uses `FOR UPDATE SKIP LOCKED` for safe concurrent access across
  multiple nodes. Respects flow control limits - if a message's destination
  is at capacity, it will be rescheduled.

  Returns `{:ok, message}` if a message was claimed, or
  `{:error, :none_available}` if no pending messages,
  `{:error, :flow_control_delayed}` if message was rescheduled due to limits.
  """
  def claim_next_pending do
    now = DateTime.utc_now()

    query =
      from m in Message,
        where: m.status == "pending",
        where: m.scheduled_at <= ^now,
        where: is_nil(m.batch_id),
        order_by: [asc: m.scheduled_at, asc: m.inserted_at],
        limit: 1,
        lock: "FOR UPDATE SKIP LOCKED"

    Repo.transaction(fn ->
      query
      |> Repo.one()
      |> claim_message_or_rollback(now)
    end)
  end

  defp claim_message_or_rollback(nil, _now), do: Repo.rollback(:none_available)

  defp claim_message_or_rollback(message, now) do
    case FlowControl.acquire_slot(message) do
      :ok ->
        dispatch_message(message, now)

      {:delay, seconds} ->
        reschedule_for_flow_control(message, seconds)
        Repo.rollback(:flow_control_delayed)
    end
  end

  defp dispatch_message(message, now) do
    updated =
      message
      |> Message.changeset(%{
        status: "dispatched",
        dispatched_at: now
      })
      |> Repo.update!()

    ActivityEvents.message_dispatched(updated)
    updated
  end

  defp reschedule_for_flow_control(message, delay_seconds) do
    # Use ceil to ensure at least 1ms delay, avoiding zero-delay rescheduling
    delay_ms = max(ceil(delay_seconds * 1000), 1)
    new_scheduled_at = DateTime.add(DateTime.utc_now(), delay_ms, :millisecond)

    message
    |> Message.changeset(%{scheduled_at: new_scheduled_at})
    |> Repo.update!()
  end

  @doc """
  Marks a message as successfully delivered.
  """
  def mark_delivered(%Message{} = message, response) do
    now = DateTime.utc_now()

    result =
      message
      |> Message.changeset(%{
        status: "delivered",
        completed_at: now,
        attempts: message.attempts + 1,
        last_response_status: response.status,
        last_response_body: truncate_body(response.body)
      })
      |> Repo.update()

    case result do
      {:ok, updated_message} ->
        ActivityEvents.message_delivered(updated_message)
        {:ok, updated_message}

      error ->
        error
    end
  end

  @doc """
  Marks a message as failed and schedules a retry if attempts remain.

  If the message is permanently failed (attempts >= max_retries), triggers
  a DLQ notification if the application has a DLQ destination configured.
  """
  def mark_failed(%Message{} = message, error, response \\ nil) do
    now = DateTime.utc_now()
    attempts = message.attempts + 1
    permanently_failed = attempts >= message.max_retries
    changes = build_failure_changes(now, attempts, permanently_failed, error, response)

    result =
      message
      |> Message.changeset(changes)
      |> Repo.update()

    handle_failure_result(result, permanently_failed)
  end

  defp build_failure_changes(now, attempts, permanently_failed, error, response) do
    base_changes = %{
      attempts: attempts,
      last_error: format_error(error),
      last_response_status: response && response[:status],
      last_response_body: response && truncate_body(response[:body])
    }

    status_changes = build_failure_status_changes(now, attempts, permanently_failed)
    Map.merge(base_changes, status_changes)
  end

  defp build_failure_status_changes(now, _attempts, true) do
    %{status: "failed", completed_at: now}
  end

  defp build_failure_status_changes(now, attempts, false) do
    %{
      status: "pending",
      scheduled_at: DateTime.add(now, backoff_seconds(attempts), :second)
    }
  end

  defp handle_failure_result({:ok, message}, true) do
    ActivityEvents.message_failed(message, will_retry: false)
    Ricqchet.Dlq.maybe_notify_failure(message)
    {:ok, message}
  end

  defp handle_failure_result({:ok, message}, false) do
    ActivityEvents.message_failed(message, will_retry: true)
    {:ok, message}
  end

  defp handle_failure_result(error, _permanently_failed), do: error

  @doc """
  Cancels a pending message.
  Returns `{:error, :already_dispatched}` if the message is not pending.
  """
  def cancel(%Message{status: "pending"} = message) do
    message
    |> Message.changeset(%{
      status: "failed",
      completed_at: DateTime.utc_now(),
      last_error: "Cancelled by user"
    })
    |> Repo.update()
  end

  def cancel(%Message{}), do: {:error, :already_dispatched}

  @doc """
  Reverts a dispatched message back to pending status.

  Used when job queue insertion fails to prevent messages from being
  stuck in "dispatched" status forever. Also releases the flow control
  slot that was acquired during claim_next_pending.
  """
  def revert_to_pending(%Message{status: "dispatched"} = message) do
    # Release the flow control slot acquired during claim_next_pending
    FlowControl.release_slot(message)

    message
    |> Message.changeset(%{
      status: "pending",
      dispatched_at: nil
    })
    |> Repo.update()
  end

  def revert_to_pending(%Message{} = message), do: {:ok, message}

  defp get_attr(attrs, key) do
    Map.get(attrs, key) || Map.get(attrs, to_string(key))
  end
end
