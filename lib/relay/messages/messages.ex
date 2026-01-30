defmodule Relay.Messages do
  @moduledoc """
  Context module for message operations.
  """

  import Ecto.Query

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
  Only returns messages that are pending or dispatched.
  """
  def get_by_dedup_key(%Tenant{id: tenant_id}, dedup_key) when is_binary(dedup_key) do
    Message
    |> where([m], m.tenant_id == ^tenant_id)
    |> where([m], m.dedup_key == ^dedup_key)
    |> where([m], m.status in ["pending", "dispatched"])
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

    changes = %{
      attempts: attempts,
      last_error: format_error(error),
      last_response_status: response && response[:status],
      last_response_body: response && truncate_body(response[:body])
    }

    changes =
      if attempts >= message.max_retries do
        Map.merge(changes, %{
          status: "failed",
          completed_at: now
        })
      else
        Map.merge(changes, %{
          status: "pending",
          scheduled_at: DateTime.add(now, backoff_seconds(attempts), :second)
        })
      end

    message
    |> Message.changeset(changes)
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
  defp truncate_body(body), do: body |> inspect() |> String.slice(0, 10_000)
end
