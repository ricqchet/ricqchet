defmodule Ricqchet.Channels.ChannelEvent do
  @moduledoc """
  Schema for channel events.

  Channel events are published messages that have been persisted for history
  and recovery purposes. Each event belongs to a specific channel within
  an application and has a monotonically increasing sequence number for
  reliable event recovery on client reconnect.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @type t :: %__MODULE__{}

  schema "channel_events" do
    field :channel, :string
    field :event_name, :string
    field :data, :binary
    field :data_size_bytes, :integer
    field :user_id, :string
    field :socket_id, :string
    field :sequence, :integer, read_after_writes: true

    belongs_to :application, Ricqchet.Applications.Application
    belongs_to :tenant, Ricqchet.Tenants.Tenant

    field :inserted_at, :utc_datetime_usec, read_after_writes: true
  end

  @doc false
  def changeset(event, attrs) do
    event
    |> cast(attrs, [:channel, :event_name, :data, :data_size_bytes, :user_id, :socket_id])
    |> validate_required([:channel, :event_name])
    |> validate_length(:channel, min: 1, max: 164)
    |> validate_length(:event_name, min: 1, max: 255)
    |> foreign_key_constraint(:application_id)
    |> foreign_key_constraint(:tenant_id)
  end
end
