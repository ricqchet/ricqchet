defmodule Ricqchet.Repo.Migrations.CreateBatches do
  use Ecto.Migration

  def change do
    create table(:batches, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :tenant_id, references(:tenants, type: :binary_id, on_delete: :delete_all), null: false

      add :batch_key, :string, null: false
      add :destination_url, :string, null: false
      add :method, :string, default: "POST"
      add :headers, :map, default: %{}

      # collecting, dispatched, delivered, failed
      add :status, :string, default: "collecting"
      add :message_count, :integer, default: 0
      add :max_size, :integer, default: 10
      add :timeout_seconds, :integer, default: 5

      add :scheduled_at, :utc_datetime_usec
      add :dispatched_at, :utc_datetime_usec
      add :completed_at, :utc_datetime_usec

      add :attempts, :integer, default: 0
      add :max_retries, :integer, default: 3
      add :last_error, :string
      add :last_response_status, :integer
      add :last_response_body, :string

      timestamps(type: :utc_datetime_usec)
    end

    create index(:batches, [:tenant_id, :batch_key, :destination_url, :status])
    create index(:batches, [:status, :scheduled_at])
  end
end
