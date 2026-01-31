defmodule Ricqchet.Batches.Batch do
  @moduledoc """
  Schema for batches of messages.

  Batches group multiple messages together for delivery as a single JSON array.
  Messages are batched by tenant, destination URL, and batch key.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  # collecting: accepting new messages
  # pending: ready for dispatch (size reached, timeout, or retry)
  # dispatched: claimed for delivery, in flight
  # delivered: successfully delivered
  # failed: permanently failed (max retries exceeded)
  @statuses ~w(collecting pending dispatched delivered failed)

  schema "batches" do
    field :batch_key, :string
    field :destination_url, :string
    field :method, :string, default: "POST"
    field :headers, :map, default: %{}

    field :status, :string, default: "collecting"
    field :message_count, :integer, default: 0
    field :max_size, :integer, default: 10
    field :timeout_seconds, :integer, default: 5

    field :scheduled_at, :utc_datetime_usec
    field :dispatched_at, :utc_datetime_usec
    field :completed_at, :utc_datetime_usec

    field :attempts, :integer, default: 0
    field :max_retries, :integer, default: 3
    field :last_error, :string
    field :last_response_status, :integer
    field :last_response_body, :string

    belongs_to :tenant, Ricqchet.Tenants.Tenant
    has_many :messages, Ricqchet.Messages.Message

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def changeset(batch, attrs) do
    batch
    |> cast(attrs, [
      :batch_key,
      :destination_url,
      :method,
      :headers,
      :status,
      :message_count,
      :max_size,
      :timeout_seconds,
      :scheduled_at,
      :dispatched_at,
      :completed_at,
      :attempts,
      :max_retries,
      :last_error,
      :last_response_status,
      :last_response_body,
      :tenant_id
    ])
    |> validate_required([:batch_key, :destination_url, :tenant_id])
    |> validate_inclusion(:status, @statuses)
    |> validate_inclusion(:method, ~w(GET POST PUT PATCH DELETE HEAD OPTIONS))
    |> foreign_key_constraint(:tenant_id)
  end

  @doc """
  Changeset for creating a new batch.
  """
  def create_changeset(batch, tenant, attrs) do
    now = DateTime.utc_now()
    timeout_seconds = Map.get(attrs, :timeout_seconds, 5)

    attrs =
      attrs
      |> Map.put(:tenant_id, tenant.id)
      |> Map.put(:scheduled_at, DateTime.add(now, timeout_seconds, :second))
      |> Map.put_new(:max_size, 10)
      |> Map.put_new(:timeout_seconds, timeout_seconds)
      |> Map.put_new(:max_retries, tenant.default_max_retries)

    changeset(batch, attrs)
  end
end
