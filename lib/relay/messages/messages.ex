defmodule Relay.Messages do
  @moduledoc """
  Context module for message operations.
  """

  import Ecto.Query
  import Relay.DeliveryHelpers

  alias Relay.Messages.Message
  alias Relay.Repo
  alias Relay.Tenants.Tenant

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

  """
  def create(%Tenant{} = tenant, attrs) do
    %Message{}
    |> Message.create_changeset(tenant, attrs)
    |> Repo.insert()
  end

  @doc """
  Creates a new message associated with a batch.

  The message status is set to "pending" but it won't be picked up by the
  regular dispatcher since it has a batch_id. It will be delivered when
  the batch is dispatched.
  """
  def create_for_batch(%Tenant{} = tenant, batch, attrs) do
    attrs = Map.put(attrs, :batch_id, batch.id)

    %Message{}
    |> Message.create_changeset(tenant, attrs)
    |> Repo.insert()
  end

  @doc """
  Gets a message by ID.
  """
  def get(id), do: Repo.get(Message, id)

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
  multiple nodes.

  Returns `{:ok, message}` if a message was claimed, or
  `{:error, :none_available}` if no pending messages.
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
      case Repo.one(query) do
        nil ->
          Repo.rollback(:none_available)

        message ->
          message
          |> Message.changeset(%{
            status: "dispatched",
            dispatched_at: now
          })
          |> Repo.update!()
      end
    end)
  end

  @doc """
  Marks a message as successfully delivered.
  """
  def mark_delivered(%Message{} = message, response) do
    now = DateTime.utc_now()

    message
    |> Message.changeset(%{
      status: "delivered",
      completed_at: now,
      attempts: message.attempts + 1,
      last_response_status: response.status,
      last_response_body: truncate_body(response.body)
    })
    |> Repo.update()
  end

  @doc """
  Marks a message as failed and schedules a retry if attempts remain.
  """
  def mark_failed(%Message{} = message, error, response \\ nil) do
    attempts = message.attempts + 1
    now = DateTime.utc_now()

    base_changes = %{
      attempts: attempts,
      last_error: format_error(error),
      last_response_status: response && response[:status],
      last_response_body: response && truncate_body(response[:body])
    }

    status_changes =
      if attempts >= message.max_retries do
        %{status: "failed", completed_at: now}
      else
        %{status: "pending", scheduled_at: DateTime.add(now, backoff_seconds(attempts), :second)}
      end

    message
    |> Message.changeset(Map.merge(base_changes, status_changes))
    |> Repo.update()
  end

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
  stuck in "dispatched" status forever.
  """
  def revert_to_pending(%Message{status: "dispatched"} = message) do
    message
    |> Message.changeset(%{
      status: "pending",
      dispatched_at: nil
    })
    |> Repo.update()
  end

  def revert_to_pending(%Message{} = message), do: {:ok, message}
end
