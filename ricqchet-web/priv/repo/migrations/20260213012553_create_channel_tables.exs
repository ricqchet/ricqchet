defmodule Ricqchet.Repo.Migrations.CreateChannelTables do
  use Ecto.Migration

  def change do
    create table(:channel_namespaces, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :pattern, :string, null: false
      add :priority, :integer, default: 0, null: false
      add :history_enabled, :boolean, default: false, null: false
      add :history_ttl_seconds, :integer
      add :history_max_events, :integer
      add :cache_enabled, :boolean, default: false, null: false
      add :max_members, :integer
      add :max_event_size_bytes, :integer
      add :max_client_events_per_second, :integer
      add :auth_endpoint, :string
      add :webhook_url, :string

      add :application_id, references(:applications, type: :binary_id, on_delete: :delete_all),
        null: false

      add :tenant_id, references(:tenants, type: :binary_id, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:channel_namespaces, [:application_id, :pattern])
    create index(:channel_namespaces, [:tenant_id])

    create table(:channel_events, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :channel, :string, null: false
      add :event_name, :string, null: false
      add :data, :binary
      add :data_size_bytes, :integer
      add :user_id, :string
      add :socket_id, :string
      add :sequence, :bigserial

      add :application_id, references(:applications, type: :binary_id, on_delete: :delete_all),
        null: false

      add :tenant_id, references(:tenants, type: :binary_id, on_delete: :delete_all), null: false

      add :inserted_at, :utc_datetime_usec, null: false, default: fragment("now()")
    end

    create index(:channel_events, [:application_id, :channel, :sequence])
    create index(:channel_events, [:tenant_id, :inserted_at])

    alter table(:applications) do
      add :channels_enabled, :boolean, default: false, null: false
      add :channels_auth_endpoint, :string
      add :channels_webhook_url, :string
    end
  end
end
