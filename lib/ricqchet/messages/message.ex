defmodule Ricqchet.Messages.Message do
  @moduledoc """
  Schema for messages in the queue.

  Messages represent HTTP requests to be delivered to destination URLs.
  They track delivery status, retry attempts, and support deduplication.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Ricqchet.UrlValidator

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @statuses ~w(pending dispatched delivered failed)

  @type t :: %__MODULE__{}

  schema "messages" do
    field :destination_url, :string
    field :method, :string, default: "POST"
    field :payload, :binary
    field :content_type, :string, default: "application/json"
    field :headers, :map, default: %{}
    field :payload_size_bytes, :integer

    field :status, :string, default: "pending"

    field :attempts, :integer, default: 0
    field :max_retries, :integer, default: 3
    field :last_error, :string
    field :last_response_status, :integer
    field :last_response_body, :string

    field :scheduled_at, :utc_datetime_usec
    field :dispatched_at, :utc_datetime_usec
    field :completed_at, :utc_datetime_usec

    field :dedup_key, :string
    field :dedup_expires_at, :utc_datetime_usec

    field :flow_control_key, :string

    belongs_to :tenant, Ricqchet.Tenants.Tenant
    belongs_to :application, Ricqchet.Applications.Application
    belongs_to :batch, Ricqchet.Batches.Batch

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def changeset(message, attrs) do
    message
    |> cast(attrs, [
      :destination_url,
      :method,
      :payload,
      :content_type,
      :headers,
      :payload_size_bytes,
      :status,
      :attempts,
      :max_retries,
      :last_error,
      :last_response_status,
      :last_response_body,
      :scheduled_at,
      :dispatched_at,
      :completed_at,
      :dedup_key,
      :dedup_expires_at,
      :flow_control_key,
      :tenant_id,
      :application_id,
      :batch_id
    ])
    |> validate_required([:destination_url, :scheduled_at, :flow_control_key, :tenant_id])
    |> validate_inclusion(:status, @statuses)
    |> validate_inclusion(:method, ~w(GET POST PUT PATCH DELETE HEAD OPTIONS))
    |> validate_url(:destination_url)
    |> foreign_key_constraint(:tenant_id)
    |> unique_constraint([:tenant_id, :dedup_key],
      name: :messages_dedup_index,
      message: "duplicate message"
    )
  end

  @doc """
  Changeset for creating a new message.
  """
  def create_changeset(message, tenant, attrs) do
    now = DateTime.utc_now()
    destination_url = get_attr(attrs, :destination_url)

    attrs =
      attrs
      |> Map.put(:tenant_id, tenant.id)
      |> Map.put(:scheduled_at, calculate_scheduled_at(attrs, now))
      |> Map.put(:dedup_expires_at, calculate_dedup_expires_at(attrs, now))
      |> Map.put(:flow_control_key, "#{tenant.id}:#{destination_url}")
      |> Map.put(:max_retries, get_attr(attrs, :max_retries) || tenant.default_max_retries)
      |> Map.put(:payload_size_bytes, calculate_payload_size(attrs))

    changeset(message, attrs)
  end

  defp calculate_scheduled_at(attrs, now) do
    case get_attr(attrs, :delay) do
      nil -> now
      delay -> DateTime.add(now, delay, :second)
    end
  end

  defp calculate_dedup_expires_at(attrs, now) do
    case get_attr(attrs, :dedup_key) do
      nil -> nil
      _key -> DateTime.add(now, get_attr(attrs, :dedup_ttl) || 300, :second)
    end
  end

  defp calculate_payload_size(attrs) do
    case get_attr(attrs, :payload) do
      nil -> 0
      payload when is_binary(payload) -> byte_size(payload)
      _other -> 0
    end
  end

  defp get_attr(attrs, key) do
    Map.get(attrs, key) || Map.get(attrs, to_string(key))
  end

  defp validate_url(changeset, field) do
    validate_change(changeset, field, fn _, value ->
      case UrlValidator.validate_url(value) do
        :ok -> []
        {:error, reason} -> [{field, reason}]
      end
    end)
  end
end
