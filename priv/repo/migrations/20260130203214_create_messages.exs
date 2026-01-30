defmodule Relay.Repo.Migrations.CreateMessages do
  use Ecto.Migration

  def change do
    create table(:messages, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :tenant_id, references(:tenants, type: :binary_id, on_delete: :delete_all), null: false

      # Destination
      add :destination_url, :text, null: false
      add :method, :string, default: "POST"

      # Payload
      add :payload, :binary
      add :content_type, :string, default: "application/json"
      add :headers, :map, default: %{}

      # Status tracking
      add :status, :string, null: false, default: "pending"

      # Retry tracking
      add :attempts, :integer, default: 0
      add :max_retries, :integer, default: 3
      add :last_error, :text
      add :last_response_status, :integer
      add :last_response_body, :text

      # Scheduling
      add :scheduled_at, :utc_datetime_usec, null: false
      add :dispatched_at, :utc_datetime_usec
      add :completed_at, :utc_datetime_usec

      # Deduplication
      add :dedup_key, :string
      add :dedup_expires_at, :utc_datetime_usec

      # Flow control (for future use)
      add :flow_control_key, :string, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create index(:messages, [:tenant_id, :status])

    create index(:messages, [:flow_control_key, :status, :scheduled_at],
             where: "status = 'pending'"
           )

    # Deduplication: unique constraint on active messages with same dedup_key
    create unique_index(:messages, [:tenant_id, :dedup_key],
             where: "dedup_key IS NOT NULL AND status IN ('pending', 'dispatched')",
             name: :messages_dedup_index
           )
  end
end
