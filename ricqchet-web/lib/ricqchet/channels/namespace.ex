defmodule Ricqchet.Channels.Namespace do
  @moduledoc """
  Schema for channel namespaces.

  Namespaces define configuration patterns for channels within an application.
  A namespace matches channels by pattern (e.g., `private-chat-*`) and applies
  rules for history, caching, limits, and authentication.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @type t :: %__MODULE__{}

  schema "channel_namespaces" do
    field :pattern, :string
    field :priority, :integer, default: 0
    field :history_enabled, :boolean, default: false
    field :history_ttl_seconds, :integer
    field :history_max_events, :integer
    field :cache_enabled, :boolean, default: false
    field :max_members, :integer
    field :max_event_size_bytes, :integer
    field :max_client_events_per_second, :integer
    field :auth_endpoint, :string
    field :webhook_url, :string

    belongs_to :application, Ricqchet.Applications.Application
    belongs_to :tenant, Ricqchet.Tenants.Tenant

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def changeset(namespace, attrs) do
    namespace
    |> cast(attrs, [
      :pattern,
      :priority,
      :history_enabled,
      :history_ttl_seconds,
      :history_max_events,
      :cache_enabled,
      :max_members,
      :max_event_size_bytes,
      :max_client_events_per_second,
      :auth_endpoint,
      :webhook_url
    ])
    |> validate_required([:pattern])
    |> validate_length(:pattern, min: 1, max: 255)
    |> validate_number(:priority, greater_than_or_equal_to: 0)
    |> validate_number(:history_ttl_seconds, greater_than: 0)
    |> validate_number(:history_max_events, greater_than: 0)
    |> validate_number(:max_members, greater_than: 0)
    |> validate_number(:max_event_size_bytes, greater_than: 0)
    |> validate_number(:max_client_events_per_second, greater_than: 0)
    |> foreign_key_constraint(:application_id)
    |> foreign_key_constraint(:tenant_id)
    |> unique_constraint([:application_id, :pattern])
  end
end
